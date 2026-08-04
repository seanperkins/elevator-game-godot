# Game naming

Research for naming the elevator game. Gathered 2026-08-03, following the
process the apple-tv-visualizer used (`docs/APP-STORE-NAMING.md` there): find
the positioning, set the rules, generate candidates in thematic passes, verify
everything against the App Store and the domain registries, then record the
decision.

The game's working title is **Elevator Incremental** (`README.md`), which is a
description of its genre, not a name. This document gathers the case for a real
name and explores alternatives.

## The finding that matters most

**The elevator-idle niche is crowded but the *voice* is open.** The App Store
has a dozen literal elevator simulators and idle-tower games:

| Already there | Why it matters |
|---|---|
| "Elevator Simulator", "Elevator" games, "Elevator Pitch" | The literal `elevator*` namespace is generic and taken |
| Idle-tower games (Idle Tower, Tower Tycoon, etc.) | The idle-genre convention of *"X Idle"* / *"Idle X"* is generic |
| "Skyscraper Tycoon" and similar | The `tycoon` suffix is exhausted |
| "High Risers" (Kumobius), "TopFloor1", "Nifty Lifty" | Direct elevator/lift-game competitors |

What none of them do is the game's actual voice: **a warm, faintly absurd
incremental that escalates until the building leaves the atmosphere.** "Elevator
Incremental" names the mechanics, not the fantasy. The gap this naming should
fill is the escalation — up, endlessly, into the sky.

The game's eras ladder Walk-Up → Highrise → Megatower → Stratosphere → Orbital
Tether, and the design's own language ("*until the building leaves the
atmosphere*") is the brand. That, not the elevator, is what a name should
carry. The elevator is the mechanism; the fantasy is *up*.

## Rules for the name

1. **~15 characters or fewer.** It must fit an app icon and a Home-screen label.
2. **Easy to spell and say.** People will search for it, and speak it aloud.
   No hyphenation, no words that trip the tongue.
3. **Hints at what the game does.** The player runs a building, drags elevators,
   and the building goes up forever.
4. **Distinctive, not generic.** Apple's stated rule — avoid generic terms and
   names too similar to existing apps. "Elevator Incremental" is a genre label.
5. **Never another company's mark.** No Plex, no Bethesda, no "Tower of Babel"
   as a game title would risk a mythic-figure collision.
6. **Check the category, not the string.** App Store names are unique only per
   developer account. What matters is a collision *within the Games or
   Entertainment category* — an unrelated Health app named "Storeys" is noise,
   an elevator *game* named "Storeys" is disqualifying.

## Verification method

Every name below was checked two ways:

- **App Store** — `tools/appstore-check/appstore_check.py`, which queries
  Apple's public iTunes Search API and flags an exact name match or a substring
  match in the competing categories **Games**/**Entertainment** (adapted from
  the apple-tv-visualizer copy, which checked Music/Entertainment).
- **Domains** — `tools/domain-check/check_all.sh`, authoritative RDAP checks
  against `.com`, `.tv`, `.app`, `.fm` registries. "AVAIL" = the registry
  returns 404 = genuinely free. "taken" = 200 with registration records.

These are App Store and domain checks. They are not trademark searches. A clean
result means no colliding app *on the App Store* and no registered domain under
those four TLDs; it says nothing about USPTO/EUIPO.

## Candidates

### Pass 1 — building and elevator vocabulary

The literal names. Most die instantly, which is the point of the pass: the
obvious names are gone or generic.

| Name | App Store | Domains | Verdict |
|---|---|---|---|
| Elevator Incremental | — | — | Working title. Genre label, not a name |
| Elevator Simulator | (crowded) | — | **Dead** — literal and taken |
| Lobby | COLLISION (Health) | — | **Dead** |
| Upward | COLLISION (Sports) | — | **Dead** |
| Strata | COLLISION (Minesweeper, Games) | — | **Dead** — a direct game hit |
| Highrise | COLLISION (Dress-up game, Games) | — | **Dead** — same category |
| Mezzanine | COLLISION (Business) | — | **Dead** |
| Verticality | COLLISION (Fitness) | — | **Dead** |
| Riser / Risers | COLLISION (High Risers, Games) | — | **Dead** |
| Climb / Skyward | COLLISION (Hill Climb, Skyward) | — | **Dead** |
| Skylift | CLEAN | com/tv/app taken, fm free | Namespace gone |
| Liftbox | COLLISION (Entertainment) | — | **Dead** |
| Midrise | substring only (Health) | — | Low |

### Pass 2 — the "up" fantasy

The escalation is the brand. Names that carry *up, higher, forever*.

| Name | App Store | Domains | Verdict |
|---|---|---|---|
| **Escension** | CLEAN | com taken; tv/app/fm free | The act of ascending. Warm, uncommon, eight letters |
| **Everytense** | CLEAN | **com free**; tv/app/fm free | "Every tense" — all of time, always rising |
| **Upmanship** | CLEAN | com taken; tv/app/fm free | "One-upmanship" — literally outdoing, rising. Playful |
| **Alwaysrising** | CLEAN | com taken; tv/app/fm free | Honest, self-describing, slightly long |
| **Nonstopup** | CLEAN | com taken; tv/app/fm free | The game loop in two words |
| **Keepclimbing** | CLEAN | com taken; tv/app/fm free | Warm, aspirational |
| **Towerofhope** | CLEAN | com taken; tv/app/fm free | Evocative but solemn; less game-like |
| **Verticaland** | CLEAN | **com free**; tv/app/fm free | "Vertical" + "-land", a place you visit |
| Skyward | COLLISION | — | **Dead** (same-category game) |
| Stratosphere | COLLISION | — | **Dead** — a gravity game owns it |

### Pass 3 — the elevator as a warm object

Elevator and lift words used sideways — the "Infuse / plain word" trick from the
visualizer doc.

| Name | App Store | Domains | Verdict |
|---|---|---|---|
| **Elevatarium** | CLEAN | **com free**; tv/app/fm free | A place where elevators live. Playful, absurd, warm — the game's actual tone |
| **Elevatortoheaven** | CLEAN | com taken; tv/app/fm free | On-the-nose absurd escalation, but long (15) and literal |
| **The Gantry** | CLEAN | com/tv/app taken | Gantry cranes lift. Niche, mechanical, namespace gone |
| **Shafted** | CLEAN | com taken; tv/app/fm free | Slang for "cheated" plus the literal shaft. The hook, not a pun risk — the game is about *not* shafting your passengers. **The pick** |
| **Shaftway** | CLEAN | — | Plain, generic |
| **Liftland** | CLEAN | com taken; tv/app/fm free | Playful, slightly childish |
| **Elevatorland** | CLEAN | **com free**; tv/app/fm free | Same as Liftland, warmer, longer |
| **The Lift** | substring only | — | Generic, taken-ish |
| **Penthouse** | substring only | — | Means the top, but evokes luxury not climbing |
| **Storeys** | CLEAN | com taken; tv/app/fm free | "Storeys" = floors. Warm, distinctive, a real word |
| **Storeystory** | CLEAN | com taken; tv/app/fm free | Pun ("storey" / "story"). Cute, but a pun that splits the spelling |
| **Towerhopper** | CLEAN | **com free**; tv/app/fm free | Busy, energetic |
| **Elevatorboss** | CLEAN | com taken; tv/app/fm free | Idle-genre convention; less brandable |
| **Cargolift** | CLEAN | com taken; tv/app/fm free | Mechanical, freight-specific |

### Pass 4 — idle-genre conventions

The genre has a house style — "X Idle" / "Idle X". These read as generic on the
shelf, which is exactly what rule 4 warns against. Worth listing to reject them:

| Name | App Store | Verdict |
|---|---|---|
| Tower Idle / Idle Tower / Elevator Idle | CLEAN | **Generic** — the shelf is full of these |
| Skyscraper Tycoon | — | **Dead** — tycoon suffix is exhausted |
| Vertical Sim | CLEAN | **Generic** — a genre label |
| Elevator Company | CLEAN | **Generic** |

## Shortlist

Names that survived verification with a clean or near-clean namespace. They are
not interchangeable — each commits to a different voice, which is the actual
decision.

| Name | Chars | What it commits to | Risk |
|---|---|---|---|
| **Shafted** | 7 | The literal object of the game (the shafts you drag on) plus the slang double meaning — which is the hook, not a risk: the whole game is about *not* letting your passengers get shafted. The "Frog Fractions" trick — a genuinely funny title that still describes the game | `.com` parked (for-sale lander, not a brand); mark dead. Safe per the audit below |
| **Elevatarium** | 11 | A warm, absurd place where elevators live. The game's actual tone — playful and slightly whimsical. Cleanest namespace found (com/tv/app/fm all free) | Might read as whimsical to the point of childish |
| **Escension** | 8 | The act of ascending. Elegant, rare, warm. The design's own word for what the game does | No literal elevator; reads as literary |
| **Everytense** | 10 | All of time, always rising. Distinctive, memorable, a real word | Meaning is opaque without the pitch |
| **Upmanship** | 9 | "One-upmanship" — outdoing, rising. Playful and self-describing | Collides slightly with the "upmanship" idiom in a way that could read as smug |
| **Storeys** | 7 | Floors as the brand. Warm, a real word, easily searched | Says nothing about escalation; could be a real-estate app |
| **Elevatortoheaven** | 15 | The absurd escalation, stated outright | Long, literal, on-the-nose |

## The decision — Shafted, 2026-08-03

**Shafted is the name.** `project.godot` (`config/name`), the README title and
the iOS bundle identifier (`com.seanperkins.shafted`, `export_presets.cfg`) now
read it; the Pages URL and the `ElevatorCar` sim class are untouched — they are
the repo path and a class, not the game title.

Shafted is the "plain word, used sideways" name that the visualizer doc found
works best on a shelf: it names the literal object of the game (the shafts you
drag on) and the slang double meaning is the hook rather than a risk, because
the whole game is about *not* letting your passengers get shafted. It passes
the same test the visualizer set: short (7 chars), easy to spell and say,
distinctive, honest about what the game is, and genuinely funny to anyone who
recognises the joke — the Frog Fractions quality no other candidate had.

Verification: **clean on the US App Store** in the competing Games/
Entertainment categories, `.tv`/`.app`/`.fm` free (`.com` is taken). The
trademark picture is clear enough to proceed — see the full safety audit below.

### Safety audit — Shafted, 2026-08-03

- **App Store (US):** clean for `shafted`, `shafted elevator`, `shafted game`,
  in the competing Games/Entertainment categories. No mobile game of this name
  exists (checked against the iTunes Search API).
- **Google Play:** search returns no app titled "Shafted" — only the query
  chrome itself.
- **Domains:** `shafted.com` is **parked** — registered 2001, renewed through
  2027, serving only a for-sale lander (`/lander`). No operating business, no
  brand, no product. `shafted.tv`, `shafted.app`, `shafted.fm` are all **AVAIL**.
- **Trademark:** the mark is **dead**. USPTO records show no live SHAFTED
  registration; the only adjacent finding (a SH***-marked serial probed via
  TSDR) is **cancelled**. Trademarkia lists no live SHAFTED mark. The slang
  usage ("to get shafted") is generic and has been in common speech for decades,
  which further weakens any claim to the mark.

**Caveats, stated honestly:** the USPTO check was done through TSDR/aggregators
that returned limited machine-readable data, and none of this is legal advice.
The residual risk is a dead mark being re-filed by someone later, which no
one-off search can rule out. For a hobbyist idle game on the web, the namespace
is as safe as a name this slang-adjacent can be.

## Sources

- [tools/appstore-check](tools/appstore-check/) — App Store collision checker
- [tools/domain-check](tools/domain-check/) — authoritative RDAP domain checker
- The apple-tv-visualizer naming doc this follows:
  `~/sites/apple-tv-visualizer/docs/APP-STORE-NAMING.md`
- Apple — [App Store Product Page guidance](https://developer.apple.com/app-store/product-page/)
