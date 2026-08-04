# App Store name checker

A tiny script that checks whether candidate app names are already taken on the
Apple App Store, using Apple's public [iTunes Search API](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/Searching.html)
— free, no API key, no account. Adapted from the apple-tv-visualizer copy; the
competing categories are `Games`/`Entertainment` for an idle game. Uses
`requests` because urllib's chunked-encoding reader breaks on Python 3.14.

    python3 appstore_check.py sonance sonoplane kaleidokine

    ✓ sonance: no exact/category collision  ->  see note below
    ✓ sonoplane: CLEAN
    ✓ kaleidokine: CLEAN

## What it flags

For each candidate name it queries the API, then classifies every hit:

- **Exact** — an app whose `trackName` equals the name. Always a collision.
- **Same-category** — a substring match in a competing category (`Music` or
  `Entertainment`, where music visualizers land). A collision *within your
  category* is the disqualifying kind (per the naming doc: App Store names are
  not globally unique — what matters is confusion on the same shelf).
- **Substring, other category** — reported but *not* a collision. A "Sonance
  Design Gallery" (Business) does not threaten a visualizer called Sonance.

Example of why category matters, from the live check:

    ✗ sonance: COLLISION
        - Sonance - Visual Music Player | Entertainment | Rare Works, LLC

`Sonance` alone (Music) and `Sonance - Visual Music Player` (Entertainment)
both exist. The Entertainment hit is a *music visualizer* — a direct
competitor. That is the collision this tool is built to surface.

## Caveats

- **US store only** — `country=US` is hardcoded. Add `--country` if you need
  another region.
- **Not a trademark search.** This checks the App Store, nothing else. A clean
  result means no colliding app *on the App Store*; it says nothing about
  USPTO/EUIPO trademarks, domains, or handles.
- **Not legal advice.** Naming decisions rest on the trademark work, not on
  this script.
- **Fuzzy search.** Apple's API is fuzzy, so "zero hits" almost never happens —
  that's why the script reports *substring* matches rather than raw counts.

## Why this exists

The naming doc (`docs/NAMING.md`) checks names by hand. This script
turns that into a repeatable check: same methodology, no typos, and it catches
the category match a raw "does the name appear" grep would miss.
