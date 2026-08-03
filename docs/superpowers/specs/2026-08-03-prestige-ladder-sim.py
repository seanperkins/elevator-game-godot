"""S5 prestige ladder simulation.

Order of business:
  1. VALIDATE the supply/demand model against 2026-08-03-building-cost-curve-design.md
  2. show why a bare sqrt conversion is DEGENERATE (demolish-spam is rate-optimal)
  3. walk the ladder under the fixed conversion, for two player policies
  4. check every row spends less than it earned

Nothing is fitted to a desired answer. The only inputs are the shipped cost
curves (data/upgrades.json, data/tenants.json) and the model in §1.
"""
import math

# ------------------------------------------------------------- supply model
# Round trip is travel plus dwell; a sweep stops at every floor. 20 Hz sim.
#   travel_s  = 2F / (20 * speed_floors_per_tick)
#   dwell_s   = F * door_ticks / 20
#   trips/min = 60 * seats / round_trip_s


def supply_per_car(F, speed=0.04, door=20, seats=4):
    return 60.0 * seats / (2.0 * F / (20.0 * speed) + F * door / 20.0)


def demand(F):
    return 0.641 * F + 0.102


FARE = 3.09    # $/trip: $12.22/min over 3.95 trips/min at six floors
LEASE = 60.0   # apartments/shops lease_cost, data/tenants.json

FLOOR = (200.0, 1.10)
SHAFT = (500.0, 2.20)
SPEED = (40.0, 1.60)
DOORS = (25.0, 1.55)
CAB = (120.0, 1.90)


def cost(bg, level):
    return bg[0] * bg[1] ** level


def speed_at(l):
    return 0.04 * (1 + 0.25 * l)


def door_at(l):
    return max(20 - 2 * l, 4)


def seats_at(l):
    return 4 + l


# ------------------------------------------------------------- conversion
DEMOLITION_FLOOR = 900.0
EARNINGS_PER_BLUEPRINT = 100.0


def yield_for(E):
    return int(math.sqrt(max(0.0, E - DEMOLITION_FLOOR) / EARNINGS_PER_BLUEPRINT))


def bare_sqrt(E):
    return int(math.sqrt(max(0.0, E) / EARNINGS_PER_BLUEPRINT))


# ------------------------------------------------------------- the run
def trajectory(cap, shafts=1, sp0=0, dr0=0, cb0=0, horizon=1200):
    """Minute-by-minute. Buys the cheapest thing that helps, cash permitting:
    whatever most cheaply restores supply when supply is short, a floor plus
    its lease otherwise. Combo is excluded, so E is a floor, not a forecast."""
    F, C = 6, shafts
    fl, sh = 0, shafts - 1
    sp, dr, cb = sp0, dr0, cb0
    cash = E = spent = 0.0
    out = []
    for t in range(1, horizon + 1):
        s = C * supply_per_car(F, speed_at(sp), door_at(dr), seats_at(cb))
        e = min(demand(F), s) * FARE
        cash += e
        E += e
        while True:
            o = []
            if s < demand(F):
                if C < 8:
                    o.append(("shaft", cost(SHAFT, sh)))
                if sp < 12:
                    o.append(("speed", cost(SPEED, sp)))
                if cb < 8:
                    o.append(("cab", cost(CAB, cb)))
                if dr < 8:
                    o.append(("doors", cost(DOORS, dr)))
            if F < cap:
                o.append(("floor", cost(FLOOR, fl) + LEASE))
            o = [x for x in o if x[1] <= cash]
            if not o:
                break
            w, p = min(o, key=lambda x: x[1])
            cash -= p
            spent += p
            if w == "shaft":
                C += 1
                sh += 1
            elif w == "speed":
                sp += 1
            elif w == "cab":
                cb += 1
            elif w == "doors":
                dr += 1
            else:
                F += 1
                fl += 1
            s = C * supply_per_car(F, speed_at(sp), door_at(dr), seats_at(cb))
        served = min(demand(F), s) / demand(F)
        out.append(dict(t=t, E=E, spent=spent, F=F, C=C, sp=sp, dr=dr, cb=cb,
                        served=served))
    return out


def exit_point(traj, conv, policy, cap, target=1):
    """target: the Blueprints the player is saving for (the next node)."""
    live = [x for x in traj if conv(x["E"]) >= 1]
    if not live:
        return None
    if policy == "rate":                       # maximise Blueprints per hour
        return max(live, key=lambda x: conv(x["E"]) / x["t"])
    # completionist: fill the building, THEN leave once the next node is funded
    ready = [x for x in traj if x["F"] >= cap and conv(x["E"]) >= target]
    return ready[0] if ready else live[-1]


# ------------------------------------------------------------- the tree
HEIGHT, SHAFTS, MOTOR, GEAR, CABIN = (2, 2), (5, 3), (2, 4), (2, 4), (3, 3)
TREE_TOTAL = sum(b * (l + 1) for b, mx in
                 (HEIGHT, SHAFTS, MOTOR, GEAR, CABIN) for l in range(mx))


def walk(conv, policy, runs=6):
    bank = 0
    lv = dict(height=0, shafts=0, motor=0, gearing=0, cabin=0)
    order = [("height", HEIGHT), ("shafts", SHAFTS), ("motor", MOTOR),
             ("gearing", GEAR), ("cabin", CABIN)]
    print(f"{'run':>3} {'cap':>4} {'floors':>7} {'cars':>5} {'s/d/c':>8} {'served':>7}"
          f" {'h:mm':>7} {'E':>9} {'BP':>4} {'bank':>5}  spends")
    rows = []
    for i in range(runs):
        cap = 10 + 5 * lv["height"]
        tj = trajectory(cap, shafts=1 + lv["shafts"], sp0=lv["motor"],
                        dr0=lv["gearing"], cb0=lv["cabin"])
        nxt = (HEIGHT[0] * (lv["height"] + 1) if lv["height"] < HEIGHT[1]
               else SHAFTS[0] * (lv["shafts"] + 1) if lv["shafts"] < SHAFTS[1] else 1)
        x = exit_point(tj, conv, policy, cap, target=max(nxt - bank, 1))
        if x is None:
            print(f"{i+1:>3} {cap:>4}   never reaches 1 BP")
            break
        bp = conv(x["E"])
        bank += bp
        buys = []
        progressed = True
        while progressed:                      # cheapest-first, height always first
            progressed = False
            for name, nd in order:
                if lv[name] < nd[1] and bank >= nd[0] * (lv[name] + 1):
                    bank -= nd[0] * (lv[name] + 1)
                    lv[name] += 1
                    tag = f"{name} L{lv[name]}"
                    if name == "height":
                        tag += f" -> cap {10 + 5 * lv['height']}"
                    buys.append(tag)
                    progressed = True
                    break
        h, mm = divmod(x["t"], 60)
        print(f"{i+1:>3} {cap:>4} {x['F']:>7} {x['C']:>5} "
              f"{x['sp']}/{x['dr']}/{x['cb']:>4} {x['served']*100:>6.0f}%"
              f" {h:>4}:{mm:02d} {x['E']:>9,.0f} {bp:>4} {bank:>5}  {', '.join(buys) or '-'}")
        rows.append(x)
    print()
    return rows


def main():
    print("1. VALIDATION against building-cost-curve-design.md §1   (doc -> model)")
    ok = True
    for F, ds, dd in [(6, 11.43, 3.95), (9, 7.62, 5.88), (12, 5.71, 7.80),
                      (16, 4.29, 10.37), (20, 3.43, 12.93)]:
        ms, md = supply_per_car(F), demand(F)
        ok &= abs(ms - ds) < 0.01 and abs(md - dd) < 0.02
        print(f"   F={F:2d}  supply {ds:5.2f} -> {ms:5.2f}   demand {dd:5.2f} -> {md:5.2f}")
    b, u = 8 * supply_per_car(40), 8 * supply_per_car(40, 0.16, 4, 12)
    ok &= abs(b - 13.7) < 0.1 and abs(u - 174) < 1.0
    print(f"   40 floors, 8 base cars     (doc 13.7/min) -> {b:.1f}/min")
    print(f"   40 floors, 8 upgraded cars (doc  174/min) -> {u:.1f}/min")
    # Same discipline as the affordability check below: a validation that only
    # prints is a false green. If the supply model ever drifts from the
    # cost-curve doc, every table downstream is fiction -- so fail loudly.
    if not ok:
        raise SystemExit("supply/demand model no longer matches the cost-curve doc")
    print("   ALL WITHIN TOLERANCE: True (checked, raises on drift)\n")

    print("2. WHY A BARE sqrt(E/100) IS DEGENERATE")
    print("   the rate-optimal exit under each conversion, at every cap:")
    print(f"   {'conversion':<26} {'cap':>4} {'exit':>7} {'floors':>7} {'BP':>4} {'BP/h':>6}")
    for nm, cv in (("sqrt(E/100)", bare_sqrt), ("sqrt((E-900)/100)", yield_for)):
        for cap in (10, 15, 20):
            x = exit_point(trajectory(cap), cv, "rate", cap)
            print(f"   {nm:<26} {cap:>4} {x['t']//60:>4}:{x['t']%60:02d} {x['F']:>7}"
                  f" {cv(x['E']):>4} {cv(x['E'])/(x['t']/60):>6.2f}")
    print("   -> a bare sqrt pays best if you never build. The offset fixes it.\n")

    print("3. THE LADDER, rate-optimal player (leaves when BP/hour peaks)")
    rate_rows = walk(yield_for, "rate")
    print("4. THE LADDER, completionist (plays every run out to its cap)")
    cap_rows = walk(yield_for, "cap")

    # AFFORDABILITY -- this ASSERTS. A row that spends more than it earned is the
    # signature defect of a hand-written balance table, and a check that only
    # prints is a false green (the exact shape the spec's own S14 complains about
    # in the GUT commands). Both walks are checked; neither is allowed to skip.
    print("5. AFFORDABILITY -- every row must spend less than it earned")
    bad = 0
    for label, rows in (("rate-optimal", rate_rows), ("completionist", cap_rows)):
        for i, x in enumerate(rows):
            ok = x["spent"] <= x["E"] + 1e-6
            bad += 0 if ok else 1
            print(f"   {label:<14} run {i+1}: earned ${x['E']:>9,.0f}"
                  f"   spent ${x['spent']:>9,.0f}{'' if ok else '   <-- IMPOSSIBLE'}")
    print(f"   rows that spend more than they earn: {bad}")
    # NOT `assert`: python3 -O strips assertions, and this check is the answer to
    # a review finding about false greens. It must fail under every interpreter.
    if bad:
        raise SystemExit(f"{bad} row(s) spend more than they earn -- the table is fiction")
    print("   CHECKED (raises under -O too): 0\n")

    print("6. WHY DEMOLITION_FLOOR = 900 -- the incentive gap, not minimality")
    print(f"   {'offset':>7} {'cap10 BP/h':>11} {'cap15 BP/h':>11} {'height inert?':>14} {'gap':>7}")
    for off in (600, 700, 800, 900, 1000):
        cv = lambda E, o=off: int(math.sqrt(max(0.0, E - o) / EARNINGS_PER_BLUEPRINT))
        pt = {}
        for cap in (10, 15):
            live = [x for x in trajectory(cap) if cv(x["E"]) >= 1]
            pt[cap] = max(live, key=lambda x: cv(x["E"]) / x["t"])
        r10 = cv(pt[10]["E"]) / (pt[10]["t"] / 60)
        r15 = cv(pt[15]["E"]) / (pt[15]["t"] / 60)
        inert = (pt[10]["F"], cv(pt[10]["E"])) == (pt[15]["F"], cv(pt[15]["E"]))
        print(f"   {off:>7} {r10:>11.2f} {r15:>11.2f} {str(inert):>14} {(r15/r10-1)*100:>6.1f}%")
    print("   600 makes height inert. 700/800 work but the gap is inside model noise.\n")

    print(f"7. TREE TOTAL: {TREE_TOTAL} Blueprints")
    per_run = sum(yield_for(x["E"]) for x in rate_rows) // len(rate_rows)
    print(f"   at the ~{per_run} BP a run above, that is"
          f" ~{TREE_TOTAL // max(1, per_run)} runs of long tail.")


if __name__ == "__main__":
    main()
