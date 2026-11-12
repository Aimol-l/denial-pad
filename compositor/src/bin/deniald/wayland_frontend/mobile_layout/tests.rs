use super::*;
use smithay::utils::{Logical, Rectangle, Size};

fn full() -> Rectangle<i32, Logical> {
    Rectangle::new((0, 45).into(), (1600, 955).into())
}

fn min(width: i32, height: i32) -> Size<i32, Logical> {
    Size::from((width, height))
}

#[test]
fn an_unconstrained_pair_splits_the_screen_in_half() {
    let [first, second] = pane_rects(full(), false, 0.5, min(1, 1), min(1, 1));
    assert_eq!(first, Rectangle::new((0, 45).into(), (800, 955).into()));
    assert_eq!(second, Rectangle::new((800, 45).into(), (800, 955).into()));
}

#[test]
fn the_ratio_never_undersizes_either_client() {
    let [first, second] = pane_rects(full(), false, 0.3, min(900, 1), min(600, 1));
    assert_eq!(first.size.w, 900);
    assert_eq!(second.size.w, 700);
}

#[test]
fn a_pair_that_cannot_fit_is_refused() {
    assert!(!fits(full(), false, min(900, 1), min(800, 1)));
    assert!(fits(full(), false, min(900, 1), min(700, 1)));
}

#[test]
fn ratio_bounds_report_the_draggable_interval() {
    let (low, high) = ratio_bounds(full(), false, min(700, 1), min(600, 1)).unwrap();
    assert!((low - 0.4375).abs() < 1e-6, "{low}");
    assert!((high - 0.625).abs() < 1e-6, "{high}");
    assert_eq!(ratio_bounds(full(), false, min(900, 1), min(800, 1)), None);
}

#[test]
fn portrait_uses_the_short_side() {
    let tall = Rectangle::new((0, 45).into(), (800, 1200).into());
    let [first, second] = pane_rects(tall, true, 0.5, min(1, 1), min(1, 1));
    assert_eq!(first.size.h, 600);
    assert_eq!(second.loc.y, 45 + 600);
}
