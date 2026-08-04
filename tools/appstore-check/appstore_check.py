#!/usr/bin/env python3
"""App Store name-availability checker for the elevator game.

Uses Apple's public iTunes Search API to check whether a candidate app name
is already taken on the App Store — exact name first, then substring matches
across the same category (an idle game should care about a colliding
"Elevator Simulator" far more than a colliding dental app).

Usage:
    python3 appstore_check.py <name> [name2 ...]
    python3 appstore_check.py --list names.txt

Prints one verdict line per name. Exit code 0 if every name is clean,
1 if any name has an exact or same-category collision.

This is an App Store collision check only. It is not a trademark search,
does not check domains or social handles, and a clean result is not legal
advice — see README.md.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse

import requests  # urllib's chunked-encoding reader breaks on Python 3.14

ITUNES_SEARCH_URL = "https://itunes.apple.com/search"
DEFAULT_LIMIT = 200
# Competing categories — a substring collision here is the dangerous kind.
# Games is the direct shelf; Entertainment is where casual/puzzle games also
# land, so an Entertainment "Elevator something" must not read as clean.
COMPETING_CATEGORIES = {"Games", "Entertainment"}


def search(name: str) -> list[dict]:
    """Query the iTunes Search API for software apps matching name."""
    params = urllib.parse.urlencode({
        "term": name,
        "entity": "software",
        "country": "US",
        "limit": str(DEFAULT_LIMIT),
    })
    resp = requests.get(f"{ITUNES_SEARCH_URL}?{params}",
                        headers={"User-Agent": "appstore-check/1.0"}, timeout=20)
    resp.raise_for_status()
    data = resp.json()
    return data.get("results", [])


def classify(name: str) -> list[dict]:
    """Return (kind, app) rows for each app matching name.

    kind is 'exact' for an exact trackName match, else 'substring' for a
    substring match. Each row carries the app dict for context.
    """
    needle = name.lower()
    rows = []
    for app in search(name):
        track = (app.get("trackName") or "").lower()
        if track == needle:
            rows.append({"kind": "exact", "app": app})
        elif needle in track:
            rows.append({"kind": "substring", "app": app})
    return rows


def verdict(name: str) -> tuple[str, list[dict]]:
    rows = classify(name)
    if not rows:
        return "CLEAN", []
    exact = [r for r in rows if r["kind"] == "exact"]
    same_cat = [r for r in rows
                if (r["app"].get("primaryGenreName") or "") in COMPETING_CATEGORIES]
    # exact match, or a substring match in a competing category
    if exact or same_cat:
        worst = exact if exact else same_cat
        return "COLLISION", worst
    return "CLEAN (substring only)", rows


def fmt(app: dict) -> str:
    return f"{app.get('trackName')} | {app.get('primaryGenreName')} | {app.get('sellerName')}"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*", help="candidate names to check")
    parser.add_argument("--list", metavar="FILE",
                        help="read candidate names from a file, one per line")
    args = parser.parse_args(argv)

    names = list(args.names)
    if args.list:
        with open(args.list) as f:
            names += [ln.strip() for ln in f if ln.strip()]
    if not names:
        parser.error("provide at least one name, or --list FILE")

    any_collision = False
    for name in names:
        state, rows = verdict(name)
        if state == "COLLISION":
            any_collision = True
            print(f"✗ {name}: COLLISION")
            for r in rows[:5]:
                print(f"    - {fmt(r['app'])}")
        elif state == "CLEAN (substring only)":
            print(f"~ {name}: no exact/category collision ({len(rows)} substring hit(s))")
            for r in rows[:3]:
                print(f"    ~ {fmt(r['app'])}")
        else:
            print(f"✓ {name}: CLEAN on the US App Store")
        time.sleep(0.3)  # be polite to the public API

    return 1 if any_collision else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
