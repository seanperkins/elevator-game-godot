# Elevator Incremental

A Godot 4.7 incremental game about elevators. You click to move people up and
down a building, buy your way out of clicking, then demolish and rebuild bigger
— until the building leaves the atmosphere.

**Play the latest build:** https://seanperkins.github.io/elevator-game-godot/

Design spec: [`docs/superpowers/specs/2026-08-01-elevator-incremental-design.md`](docs/superpowers/specs/2026-08-01-elevator-incremental-design.md)

## Status

Milestone 0 — pipeline check. The deployed build is not the game; it is a probe
that verifies Godot web export, touch input, and `user://` persistence work in
mobile Safari before any game code is written.

## Running locally

```sh
godot            # editor
godot --headless --export-release "Web" build/web/index.html
```

The web export is deliberately **threadless**: GitHub Pages cannot set the
COOP/COEP headers that Godot's threaded web export requires.
