class_name Economy
extends RefCounted

## The combo is what makes active play pay more than idling without punishing
## idling. It is HARD CAPPED: uncapped 1%-per-delivery compounding reaches
## infinity at ~71,270 consecutive deliveries, which automation makes
## reachable, and once any currency is INF every comparison degrades silently.

const COMBO_MAX := 10.0
const COMBO_STEP := 0.02

## What one person taking the stairs costs, in multiples of their unearned fare.
const STAIRS_PENALTY_FARES := 1.0

var cash: float = 0.0
var lifetime_earnings: float = 0.0
var combo: float = 1.0
var streak: int = 0
var riders_served: int = 0

## Credits a delivered fare at the current combo and advances the streak.
## Returns the amount actually paid.
func credit_delivery(fare: float) -> float:
	var paid := fare * combo
	cash += paid
	lifetime_earnings += paid
	riders_served += 1
	streak += 1
	combo = minf(combo + COMBO_STEP, COMBO_MAX)
	return paid

## Somebody gave up and took the stairs. It breaks the streak entirely, and it
## COSTS: a fare's worth of goodwill on top of the fare never earned, so bad
## service is actively expensive rather than merely unprofitable.
##
## Floored at zero cash, never negative. The design has a hard no-fail rule, and
## a debt that outruns income is a fail state wearing a number. Losing what you
## have is punishment enough; owing what you do not have is a dead end.
func note_expiry(fare: float) -> void:
	combo = 1.0
	streak = 0
	var penalty := minf(fare * STAIRS_PENALTY_FARES, cash)
	cash -= maxf(penalty, 0.0)

## Rent and other non-delivery income. Does not touch the combo.
func accrue(amount: float) -> void:
	cash += amount
	lifetime_earnings += amount

func can_afford(amount: float) -> bool:
	return cash >= amount

func spend(amount: float) -> bool:
	if not can_afford(amount):
		return false
	cash -= amount
	return true
