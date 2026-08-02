class_name SafeArea
extends RefCounted

## How much of the screen the hardware has already spoken for: the notch or
## Dynamic Island at the top, the home indicator at the bottom, and the rounded
## corners at every side.
##
## The board is laid out in 720x1280 CANVAS units, but the safe area arrives
## from DisplayServer in SCREEN PIXELS, so it has to be converted or the insets
## are wrong by the stretch scale -- on an iPhone 16 Pro that is roughly 3x,
## which is not a subtle error.
##
## Pure, so the conversion is unit-tested rather than checked by squinting at a
## phone. The caller passes what DisplayServer reported; nothing here touches
## the display.

## The rounded corners clip content that is technically inside the safe area,
## because the safe rect is square and the screen is not. Sides get at least
## this much so the leftmost waiting count and the rightmost shaft are not
## shaved by the curve.
const CORNER_MARGIN := 16.0

## Insets in CANVAS units as (left, top, right, bottom).
##
## All zero when no safe area is reported -- desktop, or a headless run. A
## zero-size rect means "not reported" and must never be read as "the whole
## screen is unsafe", which would collapse the board to nothing.
static func insets(window_px: Vector2i, safe_px: Rect2i, canvas: Vector2) -> Vector4:
	if window_px.x <= 0 or window_px.y <= 0 or canvas.y <= 0.0:
		return Vector4.ZERO
	if safe_px.size.x <= 0 or safe_px.size.y <= 0:
		return Vector4.ZERO

	var per_px_y := canvas.y / float(window_px.y)
	var per_px_x := canvas.x / float(window_px.x)
	var top := float(safe_px.position.y) * per_px_y
	var bottom := float(window_px.y - safe_px.end.y) * per_px_y
	var left := float(safe_px.position.x) * per_px_x
	var right := float(window_px.x - safe_px.end.x) * per_px_x
	return Vector4(
		maxf(left, CORNER_MARGIN),
		maxf(top, 0.0),
		maxf(right, CORNER_MARGIN),
		maxf(bottom, 0.0))

## What DisplayServer reports on the running device, already converted. Kept
## here so the one call into the display lives beside the arithmetic it feeds.
static func current(canvas: Vector2) -> Vector4:
	var window := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	return insets(window, safe, canvas)
