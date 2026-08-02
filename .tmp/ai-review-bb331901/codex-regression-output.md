The earlier concerns about the persistence probe, parse-before-version ordering, RNG state, fixed-step timing, and swallowed CI import failures are acknowledged and substantially addressed. However, this revision is unchanged in the areas identified in the previous re-review:

- **P0 — It still is not an implementation plan.** [plan.md:5](/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md:5) still says “pending implementation plan.” File-level changes, APIs, algorithms, error contracts, and exact CI commands remain unspecified.

- **P1 — The catch-up accuracy claim remains impossible.** A 60-second coarse step at [plan.md:234](/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md:234) is still required to match a 0.05-second stochastic simulation within `1e-9` at [plan.md:458](/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md:458). A rate transition halfway through a minute alone produces roughly 30 seconds of error. Integer rider counts also cannot match exactly unless catch-up reproduces live spawn events.

- **P1 — Stall reconciliation still has overlapping state ownership.** [plan.md:333](/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md:333) assigns discarded time to catch-up while ticks own sim state, but catch-up itself changes tenancy and capacity at [plan.md:254](/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md:254). No non-overlapping time intervals or merge algorithm are defined, so rent or state transitions can be applied twice after a stall.

- **P1 — A visibility save can still be dropped.** [plan.md:411](/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md:411) says an in-progress save blocks the next request. If a timer save is running when the player buys an upgrade and backgrounds Safari, the required hidden-state save is discarded. Queue or coalesce a final dirty snapshot after the active write completes.

- **P1 — Catch-up still lacks a committed watermark.** The lifecycle computes elapsed time from `saved_at` at [plan.md:215](/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md:215), but never specifies atomically advancing it after catch-up. Persisting awarded cash with the old timestamp lets a reload award the same interval again.

- **P1 — Validation still precedes migration using current data rules.** [plan.md:398](/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md:398) validates IDs and era ranges before migration. A legitimate legacy ID that migration is supposed to rename will be rejected first. Use version-specific structural validation before migration and current-schema validation afterward.

- **P2 — CI import handling still lacks executable exit-code logic.** [plan.md:571](/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md:571) says to tolerate a “documented condition” without naming its exit code or diagnostic. A `.pck` size floor cannot prove imports succeeded. The implementation plan must provide the precise shell condition and fail on every unexplained nonzero status.

VERDICT: REVISE
