//! fcitx5 input method for the shell keyboard.
//!
//! The shell keyboard is an input source like any other, so Chinese text takes
//! the same route a desktop input method would: the key events go to fcitx5,
//! and the strings it commits are handed to the focused editor.
//!
//! Only values that need the daemon are reached here. While Chinese input is
//! off, or while fcitx5 cannot be reached, every call returns `None` and the
//! caller keeps its own key handling, so text never stalls behind the input
//! method.

use std::time::{Duration, Instant};

use tracing::debug;
use zbus::blocking::connection::Builder;
use zbus::blocking::{Connection, Proxy};
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

pub(super) const SERVICE: &str = "org.fcitx.Fcitx5";
pub(super) const MANAGER_PATH: &str = "/org/freedesktop/portal/inputmethod";
const MANAGER_INTERFACE: &str = "org.fcitx.Fcitx.InputMethod1";
const CONTEXT_INTERFACE: &str = "org.fcitx.Fcitx.InputContext1";
const CALL_TIMEOUT: Duration = Duration::from_secs(2);

/// fcitx5 reports keys by the keycode its Wayland clients receive, which is
/// the evdev code plus the XKB offset.
const XKB_KEYCODE_OFFSET: u32 = 8;
/// `UpdateClientSideUI` is what would need a capability; finished text arrives
/// in the key replies, so this client declares that it renders nothing itself.
const NO_CLIENT_UI: u64 = 0;
/// How long an unreachable daemon is left alone before the next attempt.
const RETRY_INTERVAL: Duration = Duration::from_secs(30);
const COMMIT_STRING_EVENT: u32 = 0;

/// What happened to one key that was offered to the input method.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum KeyRouting {
    /// The input method took the key; this text belongs at the cursor.
    Consumed { commit: String },
    /// The input method did not take the key; the caller keeps handling it.
    Unhandled,
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

#[derive(Default)]
pub(super) struct FcitxService {
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
        if !enabled
            && let Some(session) = self.session.as_ref()
        {
            let _ = session.context.call::<_, _, ()>("Reset", &());
        }
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

    /// Candidate selection arrives with the shell's candidate strip; the
    /// method exists so that path only has to call it.
    #[allow(dead_code)]
    pub(super) fn select_candidate(&mut self, index: u32) -> bool {
        let Some(session) = self.session() else {
            return false;
        };
        let index = i32::try_from(index).unwrap_or(i32::MAX);
        session
            .context
            .call::<_, _, ()>("SelectCandidate", &(index,))
            .is_ok()
    }

    #[allow(dead_code)]
    pub(super) fn next_page(&mut self, forward: bool) -> bool {
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
    /// Held for as long as the context: closing the connection destroys it.
    _connection: Connection,
    context: Proxy<'static>,
}

impl Session {
    fn connect() -> zbus::Result<Self> {
        let connection = Builder::session()?.method_timeout(CALL_TIMEOUT).build()?;
        let manager = Proxy::new(&connection, SERVICE, MANAGER_PATH, MANAGER_INTERFACE)?;
        let (path, _token): (OwnedObjectPath, Vec<u8>) = manager.call(
            "CreateInputContext",
            &(Vec::<(String, String)>::new(),),
        )?;
        let context = Proxy::new(&connection, SERVICE, path, CONTEXT_INTERFACE)?;
        context.call::<_, _, ()>("SetSupportedCapability", &(NO_CLIENT_UI,))?;
        context.call::<_, _, ()>("FocusIn", &())?;
        Ok(Self {
            _connection: connection,
            context,
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
        Ok(KeyRouting::Consumed {
            commit: commits_in_reply(&events).concat(),
        })
    }
}

#[cfg(test)]
#[path = "fcitx/tests.rs"]
mod tests;
