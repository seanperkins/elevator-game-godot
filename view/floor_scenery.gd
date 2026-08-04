class_name FloorScenery
extends RefCounted

## What a floor looks like, by tenant kind.
##
## One lookup, cached, so a row does not load a texture every frame and the
## path convention lives in exactly one place: `art/floors/<kind id>.png`.
##
## RETURNS NULL FOR ANYTHING WITHOUT ART rather than erroring. The set is
## complete today -- six kinds plus the vacant shell -- but that stayed the
## contract: it let the images land one at a time, and it means a kind added to
## `data/tenants.json` before its image exists draws plain ground instead of
## crashing the board.
##
## The images are 416 x 240 for a 208 x 120 region (2x), and cover the board from
## x 0 to FloorRow.STRIP_RIGHT -- everything left of the shafts. See
## `brand/floor-art-prompts.md`.

const DIR := "res://art/floors/"

## An unleased floor has NO tenant kind, so it has no id to look one up with --
## and "" is already the "draw nothing" answer this returns for a kind whose
## image has not landed. The construction shell therefore needs a name of its
## own. It is not a tenant kind and never appears in `data/tenants.json`.
const VACANT := "vacant"

static var _cache: Dictionary = {}

static func texture_for(kind_id: String) -> Texture2D:
	if kind_id == "":
		return null
	if _cache.has(kind_id):
		return _cache[kind_id]
	var path := DIR + kind_id + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[kind_id] = tex
	return tex

## Which kinds currently have art. Exists so a test can state the truth about the
## set rather than hard-coding a list that rots as images land.
static func has_art(kind_id: String) -> bool:
	return texture_for(kind_id) != null
