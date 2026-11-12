use super::*;

fn full() -> Rectangle<i32, Logical> {
    Rectangle::new((0, 45).into(), (1600, 955).into())
}

fn portrait() -> Rectangle<i32, Logical> {
    Rectangle::new((0, 45).into(), (800, 1200).into())
}

#[test]
fn landscape_splits_into_two_inset_cards() {
    let [left, right] = split_rects(full(), false, 0.5);
    assert_eq!(left, Rectangle::new((14, 55).into(), (779, 931).into()));
    assert_eq!(right, Rectangle::new((807, 55).into(), (779, 931).into()));
    // 14 px of margin on both sides and 14 px between the cards.
    assert_eq!(left.loc.x, SPLIT_MARGIN);
    assert_eq!(right.loc.x + right.size.w, 1600 - SPLIT_MARGIN);
    assert_eq!(right.loc.x - (left.loc.x + left.size.w), SPLIT_GUTTER);
}

#[test]
fn portrait_splits_into_two_inset_cards() {
    let [top, bottom] = split_rects(portrait(), true, 0.5);
    assert_eq!(top.loc, (14, 55).into());
    assert_eq!(top.size, (772, 581).into());
    assert_eq!(bottom.loc.y, 55 + 581 + SPLIT_GUTTER);
    assert_eq!(bottom.size, (772, 581).into());
    assert_eq!(bottom.loc.y + bottom.size.h, 1200 - SPLIT_MARGIN + 45);
}

#[test]
fn ratio_is_clamped_to_the_draggable_range() {
    let span = 1600 - SPLIT_MARGIN * 2 - SPLIT_GUTTER;
    assert_eq!(
        split_rects(full(), false, 0.05)[0].size.w,
        (span as f32 * 0.2).round() as i32
    );
    assert_eq!(
        split_rects(full(), false, 0.95)[0].size.w,
        (span as f32 * 0.8).round() as i32
    );
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
fn the_cards_keep_their_margins_and_the_same_gutter() {
    for ratio in [0.2, 0.53, 0.5, 0.8] {
        for vertical in [false, true] {
            let full = if vertical { portrait() } else { full() };
            let [first, second] = split_rects(full, vertical, ratio);
            if vertical {
                assert_eq!(first.loc.y + first.size.h + SPLIT_GUTTER, second.loc.y);
                assert_eq!(first.size.w, second.size.w);
                assert_eq!(second.loc.y + second.size.h + SPLIT_MARGIN, full.size.h + full.loc.y);
            } else {
                assert_eq!(first.loc.x + first.size.w + SPLIT_GUTTER, second.loc.x);
                assert_eq!(first.size.h, second.size.h);
                assert_eq!(second.loc.x + second.size.w + SPLIT_MARGIN, full.size.w);
            }
        }
    }
}
