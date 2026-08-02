class_name NumberFormat
extends RefCounted

## Compact currency formatting. The suffix ladder is GENERATED: covering the
## float range needs 98 two-letter entries, which is not worth hand-writing.
##
## Magnitude is selected AFTER rounding. Choosing it first formats 999,950 as
## "1000.0K" instead of "1.0M", and the same bug repeats at every rung.

const SHORT := ["", "K", "M", "B", "T"]

static func compact(v: float) -> String:
	if is_nan(v):
		return "NaN"
	if is_inf(v):
		return "-∞" if v < 0.0 else "∞"
	var sign_prefix := "-" if v < 0.0 else ""
	var a := absf(v)
	if a < 1000.0:
		return sign_prefix + str(int(a))

	var tier := 0
	while a >= 1000.0:
		a /= 1000.0
		tier += 1
	# Round first, THEN re-check the magnitude.
	var rounded := snappedf(a, 0.1)
	if rounded >= 1000.0:
		rounded /= 1000.0
		tier += 1
	return sign_prefix + ("%.1f" % rounded) + _suffix(tier)

static func _suffix(tier: int) -> String:
	if tier < SHORT.size():
		return SHORT[tier]
	var i := tier - SHORT.size()          # 0 -> "aa"
	var first := i / 26
	var second := i % 26
	if first > 25:
		return "e%d" % (tier * 3)         # past the two-letter ladder
	return String.chr(97 + first) + String.chr(97 + second)
