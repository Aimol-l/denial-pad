use super::*;

fn full() -> Rectangle<i32, Logical> {
    Rectangle::new((0, 45).into(), (1600, 955).into())
}

fn portrait() -> Rectangle<i32, Logical> {
    Rectangle::new((0, 45).into(), (800, 1200).into())
}

#[test]
fn landscape_splits_left_and_right() {
    let [left, right] = split_rects(full(), false, 0.5);
    assert_eq!(left, Rectangle::new((0, 45).into(), (800, 955).into()));
    assert_eq!(right, Rectangle::new((800, 45).into(), (800, 955).into()));
    assert_eq!(left.size.w + right.size.w, full().size.w);
}

#[test]
fn portrait_splits_top_and_bottom() {
    let [top, bottom] = split_rects(portrait(), true, 0.5);
    assert_eq!(top.size.h, 600);
    assert_eq!(top.loc.y, full().loc.y);
    assert_eq!(bottom.loc.y, 45 + 600);
    assert_eq!(top.size.h + bottom.size.h, 1200);
}

#[test]
fn ratio_is_clamped_to_the_draggable_range() {
    assert_eq!(split_rects(full(), false, 0.05)[0].size.w, 320);
    assert_eq!(split_rects(full(), false, 0.95)[0].size.w, 1280);
}

#[test]
fn a_window_outside_the_pair_keeps_the_full_rect() {
    let split = MobileSplit {
        first: 7,
        second: 9,
        vertical: false,
        ratio: 0.53,
    };
    let [left, right] = split_rects(full(), false, 0.53);
    assert_eq!(split.pane(7, full()), Some(left));
    assert_eq!(split.pane(9, full()), Some(right));
    assert_eq!(split.pane(11, full()), None);
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
    let [left, _right] = split_rects(full(), false, 0.53);
    assert_eq!(split.pane(7, full()), Some(left));
    assert_eq!(split.pane(0, full()), None);
    assert!(!split.contains(9));
}

#[test]
fn the_two_panes_never_overlap_or_leave_a_gap() {
    for ratio in [0.2, 0.53, 0.5, 0.8] {
        for vertical in [false, true] {
            let full = if vertical { portrait() } else { full() };
            let [first, second] = split_rects(full, vertical, ratio);
            if vertical {
                assert_eq!(first.loc.y + first.size.h, second.loc.y);
            } else {
                assert_eq!(first.loc.x + first.size.w, second.loc.x);
            }
        }
    }
}
