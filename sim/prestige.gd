class_name Prestige
extends RefCounted

## Static functions only. The one place that knows a run can end.
##
## Demolish BUILDS a fresh GameState rather than wiping the live one. Every
## container GameState.new already initialises from zero stays initialised from
## zero, so a wipe-in-place would be a second clearing path that can only ever
## desync from the one construction uses.

## == Meta.MAX_BLUEPRINTS, deliberately: a legitimately clamped yield must not
## fail its own decode on the next load. Pinned by a test.
const MAX_YIELD := 1_000_000_000

## A flat sum of earnings that pays for the demolition itself. It exists to
## break the SCALE INVARIANCE of a bare square root: without it the first
## Blueprint is always the cheapest one, so leaving immediately after it is
## always rate-optimal, and the simulated rate-optimal exit is nine minutes at
## six floors. Scaling the divisor moves the exit time but not the shape.
const DEMOLITION_FLOOR := 900.0
const EARNINGS_PER_BLUEPRINT := 100.0

## n Blueprints need DEMOLITION_FLOOR + 100n^2 of earnings, so the n-th one
## costs $100(2n - 1) -- each $200 more than the one before it, which is the
## property that made the square root the right family and which a logarithm
## does not have.
##
## THE ARGUMENT ORDER IN maxf IS LOAD-BEARING AND MUST NOT BE TIDIED.
## maxf(a, b) returns `a > b ? a : b`, so maxf(NAN - FLOOR, 0.0) returns 0.0 and
## a NAN input is absorbed into a zero yield. Written the other way round,
## maxf(0.0, NAN - FLOOR) returns NAN, and minf(NAN, MAX_YIELD) then returns
## MAX_YIELD -- a billion Blueprints from a poisoned save. A test pins it.
##
## The clamp is in FLOAT space because mini() takes ints, which would do the
## out-of-range cast FIRST: int(sqrt(1e308 / 100)) is 1e153 against an int64 max
## of 9.22e18, and out-of-range float->int is platform-defined. It saturates
## harmlessly on arm64 and the ship target is a different toolchain (threadless
## WASM), so a dev-machine test would pass either way. maxf additionally guards
## sqrt against a negative argument.
static func yield_for(earnings: float) -> int:
	return int(minf(sqrt(maxf(earnings - DEMOLITION_FLOOR, 0.0) / EARNINGS_PER_BLUEPRINT),
			float(MAX_YIELD)))

## The gate is 1 Blueprint. Without it a new player can wipe a run for nothing,
## which would be a self-inflicted fail state in a game whose stated invariant
## is that it has none.
static func can_demolish(state: GameState) -> bool:
	return yield_for(state.economy.lifetime_earnings) >= 1

## Returns the run that REPLACES this one, or null when anything refuses.
##
## The order is load-bearing and it took three attempts to get right:
##
##   1. compute the yield and refuse under the gate
##   2. CLONE the Meta, checking BOTH bools
##   3. credit the CLONE only
##   4. build the fresh state against the clone
##   5. validate -- the handed Meta was never touched, so there is nothing to
##      roll back
##   6. return; the credit exists ONLY inside `fresh`
##
## Crediting the live Meta instead is not merely untidy. GameState holds it BY
## REFERENCE, so the credit becomes visible to the old run the moment this
## returns -- and the caller's save can still fail. When it does, the old run
## plays on holding Blueprints it never earned, Meta.buy() can spend them this
## session, and the ten-second autosave writes that credited Meta beside a
## still-demolish-eligible building in one perfectly valid payload. Storage
## failures on iOS are typically transient, so the next successful autosave
## makes the mint durable: demolish again and the same earnings pay twice.
##
## Both bools at step 2 are checked HERE, in the block an implementer copies.
## Unchecked, a failed defs load makes restore() drop every spent level (it
## iterates ids()), and step 6 would then hand back a state whose save durably
## persists an emptied tree.
static func demolish(state: GameState) -> GameState:
	var bp := yield_for(state.economy.lifetime_earnings)
	if bp < 1:
		return null

	var staged := Meta.new()
	if not staged.load_defs(state.blueprints_path()):
		return null
	if not staged.restore(state.meta.to_dict()):
		return null

	# mini() is not decoration: the codec clamps `blueprints` to MAX_BLUEPRINTS
	# at decode, so an uncapped credit would exceed a bound the next load
	# silently trims. The in-memory and on-disk invariants are one statement.
	staged.blueprints = mini(staged.blueprints + bp, Meta.MAX_BLUEPRINTS)
	staged.runs_completed = mini(staged.runs_completed + 1, Meta.MAX_RUNS)

	# The seed is derived, not random, so the game stays reproducible from a
	# save and the determinism the spawner tests pin survives prestige. Read
	# AFTER the increment: pre-increment, run 2 draws BASE_SEED + 0 and replays
	# run 1's traffic forever.
	var fresh := GameState.new(GameState.BASE_FLOORS, staged.starting_shafts(),
			GameState.BASE_SEED + staged.runs_completed,
			state.catalog_path(), staged, state.blueprints_path())
	if not fresh.is_valid():
		return null
	return fresh
