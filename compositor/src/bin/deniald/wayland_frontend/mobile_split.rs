//! The two panes one mobile output is split into.
//!
//! The compositor owns every window rectangle; a split is just this struct
//! telling `mobile_window_geometry` which half a window gets. The shell sends
//! the pair, its axis and the ratio, and draws what the compositor configures.

use smithay::utils::{Logical, Rectangle, Size};

/// The closest a divider may bring a pane to the screen edge.
pub(super) const MIN_RATIO: f32 = 0.2;
/// The furthest a divider may push a pane.
pub(super) const MAX_RATIO: f32 = 0.8;
/// The ratio a split starts with.
pub(super) const DEFAULT_RATIO: f32 = 0.5;


#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct MobileSplit {
    /// The pane on the left (landscape) or top (portrait).
    pub(super) first: u64,
    /// The pane on the right or bottom; zero while the shell is still picking
    /// the second app.
    pub(super) second: u64,
    pub(super) vertical: bool,
    /// How much of the screen the first pane takes.
    pub(super) ratio: f32,
}

impl MobileSplit {
    pub(super) fn clamped(mut self) -> Self {
        self.ratio = self.ratio.clamp(MIN_RATIO, MAX_RATIO);
        self
    }

    /// The rectangle `window_id` occupies, or `None` when it is not in the pair.
    pub(super) fn pane(
        &self,
        window_id: u64,
        full: Rectangle<i32, Logical>,
        first_min: Size<i32, Logical>,
        second_min: Size<i32, Logical>,
    ) -> Option<Rectangle<i32, Logical>> {
        let [first, second] = split_rects(full, self.vertical, self.ratio, first_min, second_min);
        if self.first != 0 && window_id == self.first {
            return Some(first);
        }
        if self.second != 0 && window_id == self.second {
            return Some(second);
        }
        None
    }

    pub(super) fn contains(&self, window_id: u64) -> bool {
        (self.first != 0 && window_id == self.first)
            || (self.second != 0 && window_id == self.second)
    }
}

/// Both panes of `full`, first then second.
///
/// The rectangles come from the desktop layout's split math, so a pane never
/// goes below its client's minimum size; the two still tile `full` exactly
/// whenever that is possible.
pub(super) fn split_rects(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    ratio: f32,
    first_min: Size<i32, Logical>,
    second_min: Size<i32, Logical>,
) -> [Rectangle<i32, Logical>; 2] {
    super::mobile_layout::pane_rects(
        full,
        vertical,
        f64::from(ratio.clamp(MIN_RATIO, MAX_RATIO)),
        first_min,
        second_min,
    )
}

#[cfg(test)]
#[path = "mobile_split/tests.rs"]
mod tests;
