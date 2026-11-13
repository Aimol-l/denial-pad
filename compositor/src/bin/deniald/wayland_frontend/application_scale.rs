//! Per-application UI scale: the compositor gives each client a smaller
//! logical screen (`client_scale = 1/k`) and converts every client-space value
//! at its boundary. Scene geometry needs no extra scaling because Smithay
//! already maps committed surface views through the client scale.
//!
//! Two boundaries only:
//! - values sent to the client (configure sizes) are divided by `k`;
//! - values read from the client (xdg geometry, popup positions, size hints,
//!   IME cursor rectangles) are multiplied by `k`.
//!
//! `k = 1` is the identity everywhere.

use std::collections::{HashMap, VecDeque};
use std::sync::{Mutex, OnceLock};

use smithay::desktop::Window;
use smithay::reexports::wayland_server::backend::ObjectId;
use smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;
use smithay::reexports::wayland_server::{Client, Resource};
use smithay::utils::{Logical, Point, Rectangle, Size};
use smithay::wayland::compositor::with_states;
use smithay::wayland::seat::WaylandFocus;
use smithay::wayland::shell::xdg::SurfaceCachedState;

use crate::settings::SettingsManager;

use super::WaylandFrontend;
use super::handlers::DenialClientState;
use super::managed_window::ManagedWindow;

/// The supported application scale, matching the settings document.
pub(super) const MIN_APPLICATION_SCALE: f64 = 0.5;
pub(super) const MAX_APPLICATION_SCALE: f64 = 3.0;

const DEBUG_SCALE_ENV: &str = "DENIAL_APP_SCALE_DEBUG";

/// How many sizes asked of one window are remembered: the ones in flight.
const ASKED_SIZES: usize = 4;

/// Sizes asked of the windows still open, keyed by root surface.
///
/// Kept beside the surfaces rather than in their state: a commit holds the
/// surface's cached state while Denial reads it, so taking it again here
/// would wait on itself.
type AskedSizes = HashMap<ObjectId, VecDeque<(Size<i32, Logical>, Size<i32, Logical>)>>;

fn asked_sizes() -> &'static Mutex<AskedSizes> {
    static ASKED: OnceLock<Mutex<AskedSizes>> = OnceLock::new();
    ASKED.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Remembers `logical` as asked of the client in its own `sent` units.
fn remember_asked(
    asked: &mut VecDeque<(Size<i32, Logical>, Size<i32, Logical>)>,
    sent: Size<i32, Logical>,
    logical: Size<i32, Logical>,
) {
    asked.retain(|&(previous, _)| previous != sent);
    if asked.len() == ASKED_SIZES {
        asked.pop_front();
    }
    asked.push_back((sent, logical));
}

/// The size asked of a client that committed `size`, if it is one of them.
fn recall_asked(
    asked: &VecDeque<(Size<i32, Logical>, Size<i32, Logical>)>,
    size: Size<i32, Logical>,
) -> Option<Size<i32, Logical>> {
    asked
        .iter()
        .find(|&&(sent, _)| sent == size)
        .map(|&(_, logical)| logical)
}

fn asked_size(surface: &WlSurface, committed: Size<i32, Logical>) -> Option<Size<i32, Logical>> {
    let asked = asked_sizes()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    recall_asked(asked.get(&surface.id())?, committed)
}

/// Drops what was asked of a surface that is leaving.
pub(super) fn forget_surface(id: &ObjectId) {
    asked_sizes()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(id);
}

/// Parses the temporary debugging override, such as
/// `DENIAL_APP_SCALE_DEBUG="org.gnome.Nautilus=1.5"`. Entries are comma
/// separated; the first exact app-id match wins.
pub(super) fn parse_debug_scale(raw: &str, app_id: &str) -> Option<f64> {
    for entry in raw.split(',') {
        let Some((name, value)) = entry.split_once('=') else {
            continue;
        };
        if name.trim() != app_id {
            continue;
        }
        let Ok(factor) = value.trim().parse::<f64>() else {
            continue;
        };
        if factor.is_finite() && (MIN_APPLICATION_SCALE..=MAX_APPLICATION_SCALE).contains(&factor) {
            return Some(factor);
        }
    }
    None
}

fn debug_scale(app_id: &str) -> Option<f64> {
    let raw = std::env::var(DEBUG_SCALE_ENV).ok()?;
    parse_debug_scale(&raw, app_id)
}

/// Resolves the scale of an application by its exact Wayland app id.
///
/// Settings are keyed by the standard desktop-file ID, so the lookup appends
/// `.desktop` and requires an exact match. The debugging override wins.
pub(super) fn application_scale_for_app(settings: &SettingsManager, app_id: &str) -> f64 {
    let app_id = app_id.trim();
    if app_id.is_empty() {
        return 1.0;
    }
    if let Some(scale) = debug_scale(app_id) {
        return scale;
    }
    settings
        .application_scale_for(&format!("{app_id}.desktop"))
        .unwrap_or(1.0)
        .clamp(MIN_APPLICATION_SCALE, MAX_APPLICATION_SCALE)
}

pub(super) fn client_scale_for_surface(surface: &WlSurface) -> f64 {
    let Some(client) = surface.client() else {
        return 1.0;
    };
    let Some(state) = client.get_data::<DenialClientState>() else {
        return 1.0;
    };
    let scale = state.compositor_state().client_scale();
    if scale.is_finite() && scale > 0.0 {
        scale
    } else {
        1.0
    }
}

pub(super) fn application_scale_for_surface(surface: &WlSurface) -> f64 {
    (1.0 / client_scale_for_surface(surface)).clamp(MIN_APPLICATION_SCALE, MAX_APPLICATION_SCALE)
}

/// Applies `k` to one native Wayland client. Returns whether it changed.
pub(super) fn set_client_application_scale(client: &Client, scale: f64) -> bool {
    let Some(state) = client.get_data::<DenialClientState>() else {
        return false;
    };
    let target = 1.0 / scale.clamp(MIN_APPLICATION_SCALE, MAX_APPLICATION_SCALE);
    let current = state.compositor_state().client_scale();
    if (current - target).abs() <= 1e-6 {
        return false;
    }
    state.compositor_state().set_client_scale(target);
    true
}

fn scaled(value: i32, factor: f64) -> i32 {
    (f64::from(value) * factor)
        .round()
        .clamp(f64::from(i32::MIN), f64::from(i32::MAX)) as i32
}

/// Client-space size to compositor-logical size.
pub(super) fn scale_size(surface: &WlSurface, size: Size<i32, Logical>) -> Size<i32, Logical> {
    let factor = application_scale_for_surface(surface);
    if (factor - 1.0).abs() <= 1e-6 {
        return size;
    }
    Size::from((scaled(size.w, factor), scaled(size.h, factor)))
}

/// Compositor-logical size to client-space size.
pub(super) fn client_size(surface: &WlSurface, size: Size<i32, Logical>) -> Size<i32, Logical> {
    let factor = application_scale_for_surface(surface);
    if (factor - 1.0).abs() <= 1e-6 {
        return size;
    }
    let inverse = 1.0 / factor;
    let client = Size::from((scaled(size.w, inverse), scaled(size.h, inverse)));
    let mut asked = asked_sizes()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    remember_asked(asked.entry(surface.id()).or_default(), client, size);
    client
}

pub(super) fn scale_rect(
    surface: &WlSurface,
    rect: Rectangle<i32, Logical>,
) -> Rectangle<i32, Logical> {
    let factor = application_scale_for_surface(surface);
    if (factor - 1.0).abs() <= 1e-6 {
        return rect;
    }
    Rectangle::new(
        Point::from((scaled(rect.loc.x, factor), scaled(rect.loc.y, factor))),
        Size::from((scaled(rect.size.w, factor), scaled(rect.size.h, factor))),
    )
}

pub(super) fn scale_point(surface: &WlSurface, point: Point<i32, Logical>) -> Point<i32, Logical> {
    let factor = application_scale_for_surface(surface);
    if (factor - 1.0).abs() <= 1e-6 {
        return point;
    }
    Point::from((scaled(point.x, factor), scaled(point.y, factor)))
}

/// Compositor-logical rectangle to client-space rectangle.
pub(super) fn client_rect(
    surface: &WlSurface,
    rect: Rectangle<i32, Logical>,
) -> Rectangle<i32, Logical> {
    let factor = application_scale_for_surface(surface);
    if (factor - 1.0).abs() <= 1e-6 {
        return rect;
    }
    let inverse = 1.0 / factor;
    Rectangle::new(
        Point::from((scaled(rect.loc.x, inverse), scaled(rect.loc.y, inverse))),
        Size::from((scaled(rect.size.w, inverse), scaled(rect.size.h, inverse))),
    )
}

/// Resolves the scale for a mapped window from its current app id.
pub(super) fn application_scale_for_window(frontend: &WaylandFrontend, window: &Window) -> f64 {
    let Some(root) = frontend.window_root_surface(window) else {
        return 1.0;
    };
    let app_id = toplevel_app_id(&root);
    application_scale_for_app(&frontend.settings, &app_id)
}

/// The window content rectangle in compositor logical coordinates.
///
/// `Window::geometry()` returns the raw xdg window geometry, which stays in
/// client coordinates while the client is scaled, so the compositor scales it
/// before intersecting with the (already compositor-space) surface bounds.
pub(super) fn window_geometry(window: &Window) -> Rectangle<i32, Logical> {
    let Some(surface) = window.wl_surface() else {
        return window.geometry();
    };
    let surface = surface.as_ref();
    let factor = application_scale_for_surface(surface);
    if (factor - 1.0).abs() <= 1e-6 {
        return window.geometry();
    }
    let bbox = window.bbox();
    let declared = with_states(surface, |states| {
        states
            .cached_state
            .get::<SurfaceCachedState>()
            .current()
            .geometry
    });
    match declared {
        Some(geometry) => {
            // A size the client committed because Denial asked for it maps
            // back to the exact logical size asked: rounding through the
            // client scale must not turn it into a size one pixel away.
            let size = asked_size(surface, geometry.size)
                .unwrap_or_else(|| scale_size(surface, geometry.size));
            let scaled_geometry = Rectangle::new(scale_point(surface, geometry.loc), size);
            scaled_geometry.intersection(bbox).unwrap_or(bbox)
        }
        None => bbox,
    }
}

/// Reads a toplevel's app id without allocating through the window metadata.
pub(super) fn toplevel_app_id(surface: &WlSurface) -> String {
    use smithay::wayland::shell::xdg::XdgToplevelSurfaceData;
    with_states(surface, |states| {
        states
            .data_map
            .get::<XdgToplevelSurfaceData>()
            .and_then(|attributes| {
                attributes
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .app_id
                    .clone()
            })
            .unwrap_or_default()
    })
}

/// Re-resolves a window's application scale after its app id became known.
///
/// A changed client scale must be re-advertised on the outputs and the client's
/// windows must receive a new configure so they lay out in the smaller logical
/// screen.
pub(super) fn refresh_window_application_scale(
    frontend: &mut WaylandFrontend,
    window: &Window,
    app_id: &str,
) {
    let scale = application_scale_for_app(&frontend.settings, app_id);
    apply_window_scale(frontend, window, scale);
}

/// Applies an explicit scale to a window's client. Used by the normal app
/// resolution and by the fullscreen exemption.
pub(super) fn apply_window_scale(
    frontend: &mut WaylandFrontend,
    window: &Window,
    scale: f64,
) -> bool {
    let Some(surface) = window.wl_surface() else {
        return false;
    };
    let Some(client) = surface.as_ref().client() else {
        return false;
    };
    if super::xwayland::is_client(&client) {
        return false;
    }
    if !set_client_application_scale(&client, scale) {
        return false;
    }
    tracing::info!(scale, "applied a per-application UI scale");
    for entry in &frontend.outputs {
        entry.output.change_current_state(None, None, None, None);
    }
    let windows: Vec<Window> = frontend
        .space
        .elements()
        .filter(|candidate| {
            candidate
                .wl_surface()
                .and_then(|candidate_surface| candidate_surface.client())
                .is_some_and(|candidate_client| candidate_client == client)
        })
        .cloned()
        .collect();
    for candidate in windows {
        let target = frontend.window_geometry_target(&candidate);
        if let Some(managed) = ManagedWindow::new(&candidate) {
            managed.reassert_geometry_target(target, false);
        }
        if let Some(root) = frontend.window_root_surface(&candidate) {
            frontend.update_surface_fractional_scale(&root);
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_asked_size_comes_back_exactly() {
        let mut asked = VecDeque::new();
        remember_asked(&mut asked, Size::from((640, 400)), Size::from((960, 600)));
        assert_eq!(
            recall_asked(&asked, Size::from((640, 400))),
            Some(Size::from((960, 600)))
        );
        assert_eq!(recall_asked(&asked, Size::from((641, 400))), None);
    }

    #[test]
    fn only_the_sizes_in_flight_are_remembered() {
        let mut asked = VecDeque::new();
        for index in 0..(ASKED_SIZES as i32 + 1) {
            remember_asked(
                &mut asked,
                Size::from((100 + index, 100)),
                Size::from((200 + index, 200)),
            );
        }
        assert_eq!(asked.len(), ASKED_SIZES);
        assert_eq!(recall_asked(&asked, Size::from((100, 100))), None);
        assert_eq!(
            recall_asked(&asked, Size::from((100 + ASKED_SIZES as i32, 100))),
            Some(Size::from((200 + ASKED_SIZES as i32, 200)))
        );
    }

    #[test]
    fn asking_the_same_size_again_keeps_one_entry() {
        let mut asked = VecDeque::new();
        remember_asked(&mut asked, Size::from((640, 400)), Size::from((960, 600)));
        remember_asked(&mut asked, Size::from((640, 400)), Size::from((961, 601)));
        assert_eq!(asked.len(), 1);
        assert_eq!(
            recall_asked(&asked, Size::from((640, 400))),
            Some(Size::from((961, 601)))
        );
    }

    #[test]
    fn parses_exact_debug_overrides() {
        assert_eq!(
            parse_debug_scale("org.gnome.Nautilus=1.5", "org.gnome.Nautilus"),
            Some(1.5)
        );
        assert_eq!(
            parse_debug_scale("a=1.25, org.gnome.Nautilus = 1.5", "org.gnome.Nautilus"),
            Some(1.5)
        );
        assert_eq!(parse_debug_scale("a=1.5", "a "), None);
        assert_eq!(parse_debug_scale("a=1.5", "b"), None);
        assert_eq!(parse_debug_scale("a=3.0", "a"), Some(3.0));
        assert_eq!(parse_debug_scale("a=3.5", "a"), None);
        assert_eq!(parse_debug_scale("a=1.5", "a=1.5"), None);
    }
}
