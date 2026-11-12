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
/// The margin each card keeps from the screen edge.
pub(super) const SPLIT_MARGIN: i32 = 14;
/// The gap between the two cards, where the divider sits.
pub(super) const SPLIT_GUTTER: i32 = 14;
/// The extra room below the status bar before the first card starts.
pub(super) const SPLIT_TOP: i32 = 10;

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

/// Both panes of `full`, first then second, inset into two cards.
///
/// `full` already starts below the status bar. Each card keeps [SPLIT_MARGIN]
/// from the edges, [SPLIT_TOP] below the bar, and [SPLIT_GUTTER] separates the
/// two so the shell has room for its floating divider.
pub(super) fn split_rects(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    ratio: f32,
) -> [Rectangle<i32, Logical>; 2] {
    let ratio = ratio.clamp(MIN_RATIO, MAX_RATIO);
    let margin = SPLIT_MARGIN
        .min(full.size.w / 4)
        .min(full.size.h / 4)
        .max(0);
    let top = SPLIT_TOP.min((full.size.h - margin * 2).max(0));
    let card = Rectangle::new(
        (full.loc.x + margin, full.loc.y + top).into(),
        (
            (full.size.w - margin * 2).max(1),
            (full.size.h - margin - top).max(1),
        )
            .into(),
    );
    let span = if vertical { card.size.h } else { card.size.w };
    let gutter = SPLIT_GUTTER.min((span - 2).max(0));
    let first_extent = (((span - gutter) as f32) * ratio).round() as i32;
    let first_extent = first_extent.clamp(1, (span - gutter - 1).max(1));
    let second_extent = (span - gutter - first_extent).max(1);
    if vertical {
        [
            Rectangle::new(card.loc, (card.size.w, first_extent).into()),
            Rectangle::new(
                (card.loc.x, card.loc.y + first_extent + gutter).into(),
                (card.size.w, second_extent).into(),
            ),
        ]
    } else {
        [
            Rectangle::new(card.loc, (first_extent, card.size.h).into()),
            Rectangle::new(
                (card.loc.x + first_extent + gutter, card.loc.y).into(),
                (second_extent, card.size.h).into(),
            ),
        ]
    }
}

#[cfg(test)]
#[path = "mobile_split/tests.rs"]
mod tests;
