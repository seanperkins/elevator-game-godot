Both of my round-2 findings are addressed, and I'll confirm that specifically before closing:

**Finding 2 (the fuzzy tolerance) — resolved correctly, and better than I asked for.** §9.1 does exactly the separation I would have demanded: an *integrator-exactness* test (Test A, 1e-9) that is now legitimate because §5.1's piecewise-constant one-minute buckets make both paths evaluate the *same finite sum* — a real float bound on expected spawn count, not a babysat economy threshold — and a separate *economic-fidelity* test (Test B) at ±5% of seeded live runs plus the ratio bound `max(catch-up/lived) <= 1 + δ`, which is the property the exploit finding was actually about. And it owns the quadrature/step-size reasoning instead of hand-waving a single number. Nothing here is fuzzy machinery anymore.

**Finding 1 (determinism) — fully adopted.** Hard requirement, written intra-tick order with deliver-before-expire pinned, RNG/tick/fractional-accumulator in the save schema, and §9 now asserts exact ints / relative epsilons rather than the brittle exact-N I had objected to.

Two things I flagged only in passing last round were also corrected independently: the false "absolute height is monotone" claim (§3) is deleted in favour of the true board-reset statement, and §5.3's two no-fail rules — which I hadn't even caught cancelled each other — collapsed into one reachable rule.

That's the last review round, and rather than manufacture further refinements, here's the honest check for newly-broken items:

- Catch-up anchored on the sim clock (§7.2) genuinely closes the double-apply/watermark/jank-over-credit family; nothing in the discrete sim path conflicts with it — stalls just lag wall-clock and catch-up stays off that path, which is consistent.
- The sim-clock anchor and §8.6's persistence of `sim_wall_time` and `catchup_residual_seconds` agree; residual conservation is now a named test (120 × 29 s = one 58-min absence), not an assertion.
- The reconciliation rule ("catch-up wins on Hidden→Resumed; continuation state serves zero-elapsed cold start") resolves the only real tension between §8.6 and §7.2 without leaving a gap.
- Test 11's path-equivalence (hidden-then-resumed vs cold-start) is exactly the guard that would catch a divergence between those two entry points.

I could not find anything newly broken, and nothing in my lane — machinery that earns nothing, redundant indirection, phases that could collapse — survived the rewrite. The refinements in §10.2 (pinning all actions, the reachable grep, the double `--import`, excluding GUT/tests from the shipped `.pck`, the gitignore'd credentials) all target real, named failure modes rather than process ornament.

This is solid and ready for the implementation plan that §14 correctly names as the next artifact.

VERDICT: APPROVED
