use super::*;
use std::sync::{Arc, Mutex};
use zbus::blocking::connection::Builder;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

const CONTEXT_PATH: &str = "/org/fcitx/test/context";

fn owned(text: &str) -> OwnedValue {
    OwnedValue::try_from(Value::from(text.to_owned())).unwrap()
}

fn seen(calls: &Arc<Mutex<Vec<String>>>) -> Vec<String> {
    calls.lock().unwrap().clone()
}

#[test]
fn named_keys_map_to_their_keysyms() {
    assert_eq!(keysym_for_named_key("BackSpace"), Some(0xff08));
    assert_eq!(keysym_for_named_key("Return"), Some(0xff0d));
    assert_eq!(keysym_for_named_key("space"), Some(0x20));
    assert_eq!(keysym_for_named_key("Left"), Some(0xff51));
    assert_eq!(keysym_for_named_key("Nope"), None);
}

#[test]
fn a_key_reply_commits_only_commit_events() {
    let reply = [
        (0u32, owned("你好")),
        (5u32, owned("ignored")),
        (0u32, owned("世界")),
    ];
    assert_eq!(
        commits_in_reply(&reply),
        vec!["你好".to_string(), "世界".to_string()]
    );
}

#[test]
fn keys_that_type_by_themselves_survive_an_empty_commit() {
    // fcitx takes Space and Return to finish or cancel a composition. With no
    // composition at all they must still type, not vanish.
    assert!(keep_key_when_nothing_committed(0x20));
    assert!(keep_key_when_nothing_committed(0xff0d));
    assert!(!keep_key_when_nothing_committed(u32::from(b'a')));
    // Backspace edits a composition rather than typing anything.
    assert!(!keep_key_when_nothing_committed(0xff08));
}

#[test]
fn chinese_input_is_off_until_it_is_turned_on() {
    let mut service = FcitxService::new();
    assert!(!service.enabled());
    assert!(service.key(0x6e, 49, false).is_none());
}

#[test]
fn an_unreachable_ime_leaves_the_key_alone() {
    // The caller keeps its own key handling instead of losing the keystroke.
    let mut service = FcitxService::unavailable();
    service.set_enabled(true);
    assert_eq!(service.key(0x6e, 49, false), Some(KeyRouting::Unhandled));
}

#[test]
fn chinese_keys_run_through_a_fcitx_context() {
    // Run explicitly inside dbus-run-session; never reach the desk's fcitx5.
    if std::env::var_os("DENIAL_FCITX_TEST_BUS").is_none() {
        return;
    }
    let calls = Arc::new(Mutex::new(Vec::new()));
    let server = Builder::session()
        .unwrap()
        .name(SERVICE)
        .unwrap()
        .serve_at(
            MANAGER_PATH,
            MockManager {
                calls: Arc::clone(&calls),
            },
        )
        .unwrap()
        .serve_at(
            CONTEXT_PATH,
            MockContext {
                calls: Arc::clone(&calls),
            },
        )
        .unwrap()
        .build()
        .unwrap();

    let mut service = FcitxService::new();
    service.set_enabled(true);

    assert_eq!(
        service.key(u32::from(b'n'), 49, false),
        Some(KeyRouting::Consumed {
            commit: "你好".into()
        })
    );
    assert!(service.select_candidate(2));

    drop(server);
    let calls = seen(&calls);
    assert_eq!(calls[0], "create");
    assert_eq!(calls[1], "capability 0");
    assert_eq!(calls[2], "focus-in");
    assert_eq!(calls[3], "batch 110 57 0");
    assert_eq!(calls[4], "select 2");
}

struct MockManager {
    calls: Arc<Mutex<Vec<String>>>,
}

#[zbus::interface(name = "org.fcitx.Fcitx.InputMethod1")]
impl MockManager {
    fn create_input_context(&self, _args: Vec<(String, String)>) -> (OwnedObjectPath, Vec<u8>) {
        self.calls.lock().unwrap().push("create".into());
        (OwnedObjectPath::try_from(CONTEXT_PATH).unwrap(), Vec::new())
    }
}

struct MockContext {
    calls: Arc<Mutex<Vec<String>>>,
}

#[zbus::interface(name = "org.fcitx.Fcitx.InputContext1")]
impl MockContext {
    fn focus_in(&self) {
        self.calls.lock().unwrap().push("focus-in".into());
    }

    fn set_supported_capability(&self, capability: u64) {
        self.calls
            .lock()
            .unwrap()
            .push(format!("capability {capability}"));
    }

    fn process_key_event_batch(
        &self,
        keyval: u32,
        keycode: u32,
        state: u32,
        _release: bool,
        _time: u32,
    ) -> (Vec<(u32, Value<'static>)>, bool) {
        self.calls
            .lock()
            .unwrap()
            .push(format!("batch {keyval} {keycode} {state}"));
        if keyval == u32::from(b'n') {
            (vec![(0, Value::from(String::from("你好")))], true)
        } else {
            (Vec::new(), false)
        }
    }

    fn select_candidate(&self, index: i32) {
        self.calls.lock().unwrap().push(format!("select {index}"));
    }

    fn reset(&self) {
        self.calls.lock().unwrap().push("reset".into());
    }

    fn destroy_ic(&self) {}
}
