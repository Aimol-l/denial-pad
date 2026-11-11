//! fcitx5 input method for the shell keyboard.
//!
//! The shell keyboard is an input source like any other, so Chinese text takes
//! the same route a desktop input method would: the key events go to fcitx5,
//! and the strings it commits are handed to the focused editor. The
//! composition it reports — the pinyin line and its candidates — is sent back
//! to the shell, which draws that panel itself instead of letting fcitx5 open
//! its own window.
//!
//! Only values that need the daemon are reached here. While Chinese input is
//! off, or while fcitx5 cannot be reached, every call returns `None` and the
//! caller keeps its own key handling, so text never stalls behind the input
//! method.

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use tracing::debug;
use zbus::blocking::connection::Builder;
use zbus::blocking::{Connection, MessageIterator, Proxy};
use zbus::message::Type as MessageType;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};
use zbus::MatchRule;

pub(super) const SERVICE: &str = "org.fcitx.Fcitx5";
pub(super) const MANAGER_PATH: &str = "/org/freedesktop/portal/inputmethod";
const MANAGER_INTERFACE: &str = "org.fcitx.Fcitx.InputMethod1";
const CONTEXT_INTERFACE: &str = "org.fcitx.Fcitx.InputContext1";
const CALL_TIMEOUT: Duration = Duration::from_secs(2);

/// fcitx5 reports keys by the keycode its Wayland clients receive, which is
/// the evdev code plus the XKB offset.
const XKB_KEYCODE_OFFSET: u32 = 8;
/// The client draws the preedit and candidates, so fcitx5 keeps its own
/// window closed. Without this bit it opens a separate UI window.
const CLIENT_SIDE_INPUT_PANEL: u64 = 1 << 39;
/// The client renders the preedit text itself.
const PREEDIT: u64 = 1 << 0;
const CAPABILITY: u64 = PREEDIT | CLIENT_SIDE_INPUT_PANEL;
/// How long an unreachable daemon is left alone before the next attempt.
const RETRY_INTERVAL: Duration = Duration::from_secs(30);
const COMMIT_STRING_EVENT: u32 = 0;
/// What one page of candidates may carry, and how long the preedit may be.
const MAX_CANDIDATES: usize = 64;
const MAX_PREEDIT_CHARS: usize = 128;
/// Commits queued between two frames; the shell keyboard never produces more.
const MAX_COMMITS: usize = 16;

/// What happened to one key that was offered to the input method.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum KeyRouting {
    /// The input method took the key; this text belongs at the cursor.
    Consumed { commit: String },
    /// The input method did not take the key; the caller keeps handling it.
    Unhandled,
}

/// The composition the shell draws: the pinyin line and its candidates.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct Composition {
    pub(crate) preedit: String,
    /// Candidate text in the input method's order, without its numeric labels.
    pub(crate) items: Vec<String>,
    /// Index in `items` that Space commits.
    pub(crate) highlighted: i32,
    pub(crate) has_prev: bool,
    pub(crate) has_next: bool,
}

impl Composition {
    pub(super) fn is_empty(&self) -> bool {
        self.preedit.is_empty() && self.items.is_empty()
    }
}

/// Keysyms for the named keys the shell keyboard sends without text.
pub(super) fn keysym_for_named_key(key: &str) -> Option<u32> {
    Some(match key {
        "BackSpace" | "Backspace" => 0xff08,
        "Return" | "Enter" => 0xff0d,
        "Tab" => 0xff09,
        "Escape" => 0xff1b,
        "Delete" => 0xffff,
        "space" | "Space" => 0x20,
        "Left" => 0xff51,
        "Up" => 0xff52,
        "Right" => 0xff53,
        "Down" => 0xff54,
        _ => return None,
    })
}

/// Keys that type by themselves when no composition is active.
///
/// fcitx5 takes Space and Return to finish or cancel a composition; it reports
/// them as handled even when it committed nothing. The caller still owns the
/// key in that case, or a space with no composition would type nothing.
pub(super) fn keep_key_when_nothing_committed(keyval: u32) -> bool {
    matches!(keyval, 0x20 | 0xff0d)
}

/// The text fcitx5 committed while answering one key.
fn commits_in_reply(reply: &[(u32, OwnedValue)]) -> Vec<String> {
    reply
        .iter()
        .filter(|(event, _)| *event == COMMIT_STRING_EVENT)
        .filter_map(|(_, value)| match &**value {
            Value::Str(text) => Some(text.as_str().to_owned()),
            _ => None,
        })
        .collect()
}

/// Turns one `UpdateClientSideUI` report into a bounded composition.
///
/// fcitx5 sends the preedit as formatted segments and each candidate as a
/// label and a text; the shell only shows the text.
pub(super) fn composition_from(
    preedit: Vec<(String, i32)>,
    candidates: Vec<(String, String)>,
    highlighted: i32,
    has_prev: bool,
    has_next: bool,
) -> Composition {
    let preedit = preedit
        .into_iter()
        .flat_map(|(text, _)| text.chars().collect::<Vec<_>>())
        .take(MAX_PREEDIT_CHARS)
        .collect();
    Composition {
        preedit,
        items: candidates
            .into_iter()
            .take(MAX_CANDIDATES)
            .map(|(_, text)| text)
            .collect(),
        highlighted,
        has_prev,
        has_next,
    }
}

#[derive(Default)]
pub(crate) struct FcitxService {
    enabled: bool,
    session: Option<Session>,
    /// Set after a failed connection so a missing daemon is not retried on
    /// every keystroke.
    retry_at: Option<Instant>,
}

impl FcitxService {
    pub(super) fn new() -> Self {
        Self::default()
    }

    pub(super) fn enabled(&self) -> bool {
        self.enabled
    }

    /// Turning Chinese input off abandons any half-typed composition, so the
    /// next key cannot suddenly commit a stale word.
    pub(super) fn set_enabled(&mut self, enabled: bool) {
        if self.enabled == enabled {
            return;
        }
        self.enabled = enabled;
        let Some(session) = self.session.as_ref() else {
            return;
        };
        if enabled {
            return;
        }
        let _ = session.context.call::<_, _, ()>("Reset", &());
        session.clear_composition();
    }

    /// Offers one key press to the input method. `None` means the input method
    /// is not in charge of this key: Chinese input is off, or fcitx5 is not
    /// reachable.
    pub(super) fn key(
        &mut self,
        keyval: u32,
        evdev_keycode: u32,
        shift: bool,
    ) -> Option<KeyRouting> {
        if !self.enabled {
            return None;
        }
        let Some(session) = self.session() else {
            return Some(KeyRouting::Unhandled);
        };
        match session.key(keyval, evdev_keycode, shift) {
            Ok(routing) => Some(routing),
            Err(error) => {
                debug!(%error, "fcitx5 did not answer; typing without it");
                self.session = None;
                self.retry_at = Some(Instant::now() + RETRY_INTERVAL);
                Some(KeyRouting::Unhandled)
            }
        }
    }

    /// The newest composition the shell has not drawn yet.
    pub(crate) fn take_composition(&mut self) -> Option<Composition> {
        self.session.as_ref().and_then(Session::take_composition)
    }

    /// Text the daemon committed without answering a key, for the editor.
    pub(crate) fn take_commit(&mut self) -> Option<String> {
        self.session.as_ref().and_then(Session::take_commit)
    }

    pub(crate) fn select_candidate(&mut self, index: u32) -> bool {
        let Some(session) = self.session() else {
            return false;
        };
        let index = i32::try_from(index).unwrap_or(i32::MAX);
        session
            .context
            .call::<_, _, ()>("SelectCandidate", &(index,))
            .is_ok()
    }

    pub(crate) fn next_page(&mut self, forward: bool) -> bool {
        let Some(session) = self.session() else {
            return false;
        };
        let method = if forward { "NextPage" } else { "PrevPage" };
        session.context.call::<_, _, ()>(method, &()).is_ok()
    }

    /// The context is created on the first key that needs it, so a session
    /// that never turns on Chinese input never talks to the daemon.
    fn session(&mut self) -> Option<&mut Session> {
        if self.session.is_none() {
            if self.retry_at.is_some_and(|at| Instant::now() < at) {
                return None;
            }
            match Session::connect() {
                Ok(session) => {
                    self.session = Some(session);
                    self.retry_at = None;
                }
                Err(error) => {
                    debug!(%error, "fcitx5 input method is unavailable");
                    self.retry_at = Some(Instant::now() + RETRY_INTERVAL);
                    return None;
                }
            }
        }
        self.session.as_mut()
    }

    #[cfg(test)]
    pub(super) fn unavailable() -> Self {
        Self {
            enabled: false,
            session: None,
            retry_at: Some(Instant::now() + RETRY_INTERVAL),
        }
    }
}

struct Session {
    /// Closing the connection ends the signal thread as well.
    connection: Option<Connection>,
    context: Proxy<'static>,
    /// The newest composition the signal thread has read.
    composition: Arc<Mutex<Option<Composition>>>,
    /// Text the daemon committed outside a key reply, such as a candidate the
    /// shell picked or a word it finished on its own.
    commits: Arc<Mutex<VecDeque<String>>>,
}

impl Drop for Session {
    fn drop(&mut self) {
        if let Some(connection) = self.connection.take() {
            // The signal thread blocks on this connection; closing it retires
            // the thread with the session instead of leaking one per daemon
            // restart.
            let _ = connection.close();
        }
    }
}

impl Session {
    fn connect() -> zbus::Result<Self> {
        let connection = Builder::session()?.method_timeout(CALL_TIMEOUT).build()?;
        let manager = Proxy::new(&connection, SERVICE, MANAGER_PATH, MANAGER_INTERFACE)?;
        let (path, _token): (OwnedObjectPath, Vec<u8>) =
            manager.call("CreateInputContext", &(Vec::<(String, String)>::new(),))?;
        let context = Proxy::new(&connection, SERVICE, path.clone(), CONTEXT_INTERFACE)?;
        // Both calls are required: fcitx5 records the supported set first and
        // only applies capabilities through the second.
        context.call::<_, _, ()>("SetSupportedCapability", &(CAPABILITY,))?;
        context.call::<_, _, ()>("SetCapability", &(CAPABILITY,))?;
        context.call::<_, _, ()>("FocusIn", &())?;
        let composition = Arc::new(Mutex::new(None));
        let commits = Arc::new(Mutex::new(VecDeque::new()));
        watch_panel(
            &connection,
            path,
            Arc::clone(&composition),
            Arc::clone(&commits),
        );
        Ok(Self {
            connection: Some(connection),
            context,
            composition,
            commits,
        })
    }

    fn key(&self, keyval: u32, evdev_keycode: u32, shift: bool) -> zbus::Result<KeyRouting> {
        let keycode = evdev_keycode + XKB_KEYCODE_OFFSET;
        // fcitx5 reads the modifier state in XKB's spelling, where shift is the
        // lowest bit.
        let state = u32::from(shift);
        let (events, handled): (Vec<(u32, OwnedValue)>, bool) = self.context.call(
            "ProcessKeyEventBatch",
            &(keyval, keycode, state, false, 0u32),
        )?;
        if !handled {
            return Ok(KeyRouting::Unhandled);
        }
        let commit = commits_in_reply(&events).concat();
        if !commit.is_empty() {
            // The input method finished a word; its panel is empty again.
            self.clear_composition();
        }
        Ok(KeyRouting::Consumed { commit })
    }

    fn take_composition(&self) -> Option<Composition> {
        lock(&self.composition).take()
    }

    fn take_commit(&self) -> Option<String> {
        lock(&self.commits).pop_front()
    }

    fn clear_composition(&self) {
        let mut slot = lock(&self.composition);
        match slot.as_ref() {
            // Nothing drawn yet, or already cleared.
            None => {}
            Some(composition) if composition.is_empty() => {}
            Some(_) => *slot = Some(Composition::default()),
        }
    }
}

fn lock<T>(state: &Arc<Mutex<T>>) -> std::sync::MutexGuard<'_, T> {
    state.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Reads the input method's panel updates and unnudged commits on a thread of
/// their own: the compositor only polls them between frames.
fn watch_panel(
    connection: &Connection,
    path: OwnedObjectPath,
    composition: Arc<Mutex<Option<Composition>>>,
    commits: Arc<Mutex<VecDeque<String>>>,
) {
    let rule = MatchRule::builder()
        .msg_type(MessageType::Signal)
        .interface(CONTEXT_INTERFACE)
        .and_then(|rule| rule.path(path.as_str().to_owned()));
    let Ok(rule) = rule else {
        return;
    };
    let rule = rule.build();
    let connection = connection.clone();
    let reader = thread::Builder::new()
        .name("fcitx-signals".into())
        .spawn(move || {
            let Ok(iterator) = MessageIterator::for_match_rule(rule, &connection, Some(64)) else {
                return;
            };
            for message in iterator {
                let Ok(message) = message else {
                    break;
                };
                match message.header().member().map(|member| member.as_str()) {
                    Some("UpdateClientSideUI") => match composition_of(&message) {
                        Ok(next) => *lock(&composition) = Some(next),
                        Err(error) => debug!(%error, "fcitx5 panel update was unreadable"),
                    },
                    Some("CommitString") => {
                        let Ok(text) = message.body().deserialize::<String>() else {
                            continue;
                        };
                        let mut commits = lock(&commits);
                        if commits.len() >= MAX_COMMITS {
                            commits.pop_front();
                        }
                        commits.push_back(text);
                    }
                    _ => {}
                }
            }
        });
    if let Err(error) = reader {
        debug!(%error, "fcitx5 panel updates are unavailable");
    }
}

fn composition_of(message: &zbus::Message) -> zbus::Result<Composition> {
    #[allow(clippy::type_complexity)]
    let (preedit, _cursor, _aux_up, _aux_down, candidates, highlighted, _layout, has_prev, has_next): (
        Vec<(String, i32)>,
        i32,
        Vec<(String, i32)>,
        Vec<(String, i32)>,
        Vec<(String, String)>,
        i32,
        i32,
        bool,
        bool,
    ) = message.body().deserialize()?;
    Ok(composition_from(
        preedit,
        candidates,
        highlighted,
        has_prev,
        has_next,
    ))
}

#[cfg(test)]
#[path = "fcitx/tests.rs"]
mod tests;
