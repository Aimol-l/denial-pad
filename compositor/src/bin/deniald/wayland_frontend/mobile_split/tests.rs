use super::*;
use smithay::utils::Size;

fn full() -> Rectangle<i32, Logical> {
    Rectangle::new((0, 45).into(), (1600, 955).into())
}

fn min(width: i32, height: i32) -> Size<i32, Logical> {
    Size::from((width, height))
}

fn portrait() -> Rectangle<i32, Logical> {
    Rectangle::new((0, 45).into(), (800, 1200).into())
}

#[test]
fn landscape_splits_left_and_right() {
    let [left, right] = split_rects(full(), false, 0.5, min(1, 1), min(1, 1));
    assert_eq!(left, Rectangle::new((0, 45).into(), (800, 955).into()));
    assert_eq!(right, Rectangle::new((800, 45).into(), (800, 955).into()));
    assert_eq!(left.size.w + right.size.w, full().size.w);
}

#[test]
fn portrait_splits_top_and_bottom() {
    let [top, bottom] = split_rects(portrait(), true, 0.5, min(1, 1), min(1, 1));
    assert_eq!(top.size.h, 600);
    assert_eq!(top.loc.y, full().loc.y);
    assert_eq!(bottom.loc.y, 45 + 600);
    assert_eq!(top.size.h + bottom.size.h, 1200);
}

#[test]
fn ratio_is_clamped_to_the_draggable_range() {
    assert_eq!(split_rects(full(), false, 0.05, min(1, 1), min(1, 1))[0].size.w, 320);
    assert_eq!(split_rects(full(), false, 0.95, min(1, 1), min(1, 1))[0].size.w, 1280);
}

#[test]
fn a_window_outside_the_pair_keeps_the_full_rect() {
    let split = MobileSplit {
        first: 7,
        second: 9,
        vertical: false,
        ratio: 0.53,
    };
    let [left, right] = split_rects(full(), false, 0.53, min(1, 1), min(1, 1));
    assert_eq!(split.pane(7, full(), min(1, 1), min(1, 1)), Some(left));
    assert_eq!(split.pane(9, full(), min(1, 1), min(1, 1)), Some(right));
    assert_eq!(split.pane(11, full(), min(1, 1), min(1, 1)), None);
    assert!(!split.contains(11));
}

#[test]
fn an_open_pair_keeps_the_second_pane_free() {
    let split = MobileSplit {
        first: 7,
        second: 0,
        vertical: false,
        ratio: 0.53,
    };
    let [left, _right] = split_rects(full(), false, 0.53, min(1, 1), min(1, 1));
    assert_eq!(split.pane(7, full(), min(1, 1), min(1, 1)), Some(left));
    assert_eq!(split.pane(0, full(), min(1, 1), min(1, 1)), None);
    assert!(!split.contains(9));
}

#[test]
fn the_two_panes_never_overlap_or_leave_a_gap() {
    for ratio in [0.2, 0.53, 0.5, 0.8] {
        for vertical in [false, true] {
            let full = if vertical { portrait() } else { full() };
            let [first, second] = split_rects(full, vertical, ratio, min(1, 1), min(1, 1));
            if vertical {
                assert_eq!(first.loc.y + first.size.h, second.loc.y);
            } else {
                assert_eq!(first.loc.x + first.size.w, second.loc.x);
            }
        }
    }
}

#[test]
fn the_ratio_respects_the_clients_minimum_sizes() {
    let [left, right] = split_rects(full(), false, 0.3, min(900, 1), min(600, 1));
    assert_eq!(left.size.w, 900);
    assert_eq!(right.size.w, 700);
}
