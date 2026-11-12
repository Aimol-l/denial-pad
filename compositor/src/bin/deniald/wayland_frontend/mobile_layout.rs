//! The two panes a phone screen is split into.
//!
//! The rectangles themselves come from the desktop layout's split math so the
//! tablet and the desk cannot drift apart: same axis rules, same minimum-size
//! clamping, same rounding.

use smithay::utils::{Logical, Rectangle, Size};

use crate::window_layout::{LayoutAxis, split_geometry_on_axis_with_minimums};

/// The two panes of `full`, first then second.
pub(super) fn pane_rects(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    ratio: f64,
    first_min: Size<i32, Logical>,
    second_min: Size<i32, Logical>,
) -> [Rectangle<i32, Logical>; 2] {
    let axis = if vertical {
        LayoutAxis::Vertical
    } else {
        LayoutAxis::Horizontal
    };
    let (first, second) =
        split_geometry_on_axis_with_minimums(full, 0, ratio, first_min, second_min, axis);
    [first, second]
}

/// Whether a split at 50:50 can host both clients at their minimum size.
pub(super) fn fits(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    first_min: Size<i32, Logical>,
    second_min: Size<i32, Logical>,
) -> bool {
    ratio_bounds(full, vertical, first_min, second_min).is_some()
}

/// The ratio interval that keeps both clients at or above their minimum size,
/// intersected with the draggable range.
pub(super) fn ratio_bounds(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    first_min: Size<i32, Logical>,
    second_min: Size<i32, Logical>,
) -> Option<(f64, f64)> {
    let extent = if vertical { full.size.h } else { full.size.w }.max(2) as f64;
    let first = if vertical { first_min.h } else { first_min.w }.max(1) as f64;
    let second = if vertical { second_min.h } else { second_min.w }.max(1) as f64;
    if first + second > extent {
        return None;
    }
    let low = (first / extent).max(0.2);
    let high = (1.0 - second / extent).min(0.8);
    (low <= high).then_some((low, high))
}

#[cfg(test)]
#[path = "mobile_layout/tests.rs"]
mod tests;
