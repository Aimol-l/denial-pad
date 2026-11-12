//! The two panes one mobile output is split into.
//!
//! The compositor owns every window rectangle; a split is just this struct
//! telling `mobile_window_geometry` which half a window gets. The shell sends
//! the pair, its axis and the ratio, and draws what the compositor configures.

use smithay::utils::{Logical, Rectangle};

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
    ) -> Option<Rectangle<i32, Logical>> {
        let [first, second] = split_rects(full, self.vertical, self.ratio);
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

/// Both panes of `full`, first then second; the two always tile it exactly.
pub(super) fn split_rects(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    ratio: f32,
) -> [Rectangle<i32, Logical>; 2] {
    let ratio = ratio.clamp(MIN_RATIO, MAX_RATIO);
    if vertical {
        let first_height = ((full.size.h as f32) * ratio).round() as i32;
        [
            Rectangle::new(full.loc, (full.size.w, first_height).into()),
            Rectangle::new(
                (full.loc.x, full.loc.y + first_height).into(),
                (full.size.w, full.size.h - first_height).into(),
            ),
        ]
    } else {
        let first_width = ((full.size.w as f32) * ratio).round() as i32;
        [
            Rectangle::new(full.loc, (first_width, full.size.h).into()),
            Rectangle::new(
                (full.loc.x + first_width, full.loc.y).into(),
                (full.size.w - first_width, full.size.h).into(),
            ),
        ]
    }
}

#[cfg(test)]
#[path = "mobile_split/tests.rs"]
mod tests;
