class_name DaySparkline
extends Control

## A kind's whole day as 24 bars, one per simulated hour, with each bar split
## vertically by that hour's directional mix.
##
## Volume and direction at once is what makes two kinds at the same tier
## comparable -- the choice between them is a shape decision, and a number
## cannot show a shape. Apartments and a Gym may earn the same, but one peaks
## outbound at seven and the other inbound through the morning, and that is
## the decision.
##
## bar_heights() and segment_shares() are the testable seams; _draw() reads
## them, so a mismatch between the seams and the picture cannot hide.

const BAR_COUNT := 24

var _kind: TenantKind

const COLOUR_INBOUND := Color("4cc2ff")     # incoming visitors, up
const COLOUR_OUTBOUND := Color("f59e0b")    # leavers, down
const COLOUR_INTERFLOOR := Color("8b98aa")  # neither, blunt

func show_kind(kind: TenantKind) -> void:
	_kind = kind
	queue_redraw()

## One bar height per hour, 0..1, proportional to that hour's rate normalised
## to the kind's OWN maximum -- so the shape is comparable across kinds even
## when their absolute volumes differ by an order of magnitude.
func bar_heights() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var top := 0.0
	if _kind != null:
		for h in range(BAR_COUNT):
			top = maxf(top, _kind.rate[h])
	top = maxf(top, 0.0001)
	for h in range(BAR_COUNT):
		out.append(_kind.rate[h] / top if _kind != null else 0.0)
	return out

## (inbound, outbound, interfloor) shares of the hour, summing to 1.
func segment_shares(bucket: int) -> Vector3:
	if _kind == null:
		return Vector3.ZERO
	var i := posmod(bucket, TenantKind.BUCKETS)
	var inbound := _kind.inbound[i]
	var outbound := _kind.outbound[i]
	var interfloor := maxf(1.0 - inbound - outbound, 0.0)
	return Vector3(inbound, outbound, interfloor)

func _draw() -> void:
	if _kind == null:
		return
	var heights := bar_heights()
	var bar_width := size.x / float(BAR_COUNT)
	for h in range(BAR_COUNT):
		var filled := heights[h] * size.y
		if filled <= 0.0:
			continue
		var x := float(h) * bar_width
		var seg := segment_shares(h)
		var y := size.y - filled
		_segment(Rect2(x, y, bar_width, filled), seg)

## Draws one bar as up to three stacked slices. Heights are proportional to the
## hour's mix, bottom-up: inbound, outbound, then interfloor.
func _segment(rect: Rect2, seg: Vector3) -> void:
	var cursor := rect.position.y
	_draw_slice(rect, cursor, seg.x, COLOUR_INBOUND)
	cursor += rect.size.y * seg.x
	_draw_slice(rect, cursor, seg.y, COLOUR_OUTBOUND)
	cursor += rect.size.y * seg.y
	_draw_slice(rect, cursor, seg.z, COLOUR_INTERFLOOR)

func _draw_slice(rect: Rect2, y: float, share: float, colour: Color) -> void:
	if share <= 0.0:
		return
	draw_rect(Rect2(rect.position.x, y, rect.size.x, rect.size.y * share), colour)
