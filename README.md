# Elevator Incremental

A Godot 4.7 incremental game about elevators. You tap to send cars up and down
a building, deliver passengers before their patience runs out, then buy your
way out of doing it by hand — until the building leaves the atmosphere.

**Play the latest build:** https://seanperkins.github.io/elevator-game-godot/

Design spec: [`docs/superpowers/specs/2026-08-01-elevator-incremental-design.md`](docs/superpowers/specs/2026-08-01-elevator-incremental-design.md)
UI design: [`docs/superpowers/specs/2026-08-02-ui-design.md`](docs/superpowers/specs/2026-08-02-ui-design.md)

## Status

Milestones 1–3 and the full board + management UI are built, tested, and
deployed. The game is played on an iPhone through GitHub Pages, so the web
export is the primary target. Work continues from the current branch
(`tenant-kinds-and-floor-class`) toward Spec A, "Floors you choose and invest
in".

## Running locally

```sh
godot            # editor
godot --headless --export-release "Web" build/web/index.html
```

The web export is deliberately **threadless**: GitHub Pages cannot set the
COOP/COEP headers that Godot's threaded web export requires.

Tests (GUT):

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

The full GUT suite runs in CI before every deploy to Pages.

## Architecture

The code is split into three sealed layers — pure simulation (`sim/`), the
single owning entry point (`game/`), and the render layer (`view/` + `ui/`).
`data/` holds numeric config loaded at runtime. Sim code never touches the
scene tree; views never mutate logic. Per-module maps live in
[`codemaps/`](codemaps/architecture.md).
