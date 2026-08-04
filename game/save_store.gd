class_name SaveStore
extends RefCounted

## Reads and writes the save file. All the decisions about WHAT is saved live in
## SaveCodec; this is only the file handling.
##
## Writes are a REAL REPLACE, not a delete-then-rename: the new save goes to a
## temp file, the current save rotates to BACKUP_PATH, and only then does the
## temp file become the save. No window exists in which neither PATH nor
## BACKUP_PATH holds a complete save. A phone killed mid-write is the ordinary
## case, not the exotic one, and a half-written JSON file is worse than an old
## save -- it loses everything rather than a few seconds.
##
## BACKUP_PATH protects against TRUNCATION (a parse failure), not against a
## decode REFUSAL -- see _select().
##
## Web durability is UNVERIFIED: user:// on the ship target is IDBFS, where
## Godot flushes asynchronously with flush points tied to file-handle close
## rather than to DirAccess rename/remove, so a tab killed mid-sequence can
## recover into a state this algorithm never produces. tests/test_save_store.gd
## runs headless on desktop and pins the LOGIC only.
##
## The file lives in user://, which on iOS is inside the app container and on
## the web is IndexedDB. Nothing here trusts its contents: SaveCodec refuses a
## save it does not recognise, and every dynamic string it produces is rendered
## through Label rather than BBCode, per the design spec's note about a
## github.io origin shared with every other Pages site on the account.

const PATH := "user://save.json"
const TEMP_PATH := "user://save.json.tmp"
const BACKUP_PATH := "user://save.json.bak"

static func has_save() -> bool:
	return FileAccess.file_exists(PATH) or FileAccess.file_exists(BACKUP_PATH)

## Replaces the save file. Every step's result is checked, and the rule on
## failure is "restore the invariant 'if any copy exists, PATH exists'", not
## "preserve BACKUP for its own sake" -- rolling back a failed commit means
## renaming BACKUP onto PATH, which necessarily consumes BACKUP.
static func save(state: GameState) -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		return false

	# 1. RECOVERY, not cleanup: promote a backup-only (or unusable-PATH) state
	#    before anything is written. Keyed on whether PATH is a USABLE copy
	#    rather than on whether it merely exists -- {PATH corrupt, BACKUP good}
	#    would otherwise no-op here, and step 3 would then delete the only
	#    loadable copy.
	if FileAccess.file_exists(BACKUP_PATH) and not _parses(PATH):
		if dir.file_exists(PATH) and dir.remove(PATH) != OK:
			return false
		if dir.rename(BACKUP_PATH, PATH) != OK:
			return false                # keep BACKUP; PATH is untouched

	# 2. Write the whole new save before anything durable is disturbed.
	var f := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(SaveCodec.encode(state)))
	f.close()

	# 3. CLEANUP, and only now that a complete TEMP exists. A stale backup would
	#    otherwise block step 4 on any platform whose rename refuses an existing
	#    destination; removing it any earlier is the data-loss mirror of the
	#    same bug, because load_state deliberately supports {PATH absent,
	#    BACKUP present}.
	if dir.file_exists(BACKUP_PATH) and dir.remove(BACKUP_PATH) != OK:
		return false

	# 4. Rotate. PATH is legitimately absent on a first save.
	if dir.file_exists(PATH) and dir.rename(PATH, BACKUP_PATH) != OK:
		return false

	# 5. THE COMMIT POINT.
	if dir.rename(TEMP_PATH, PATH) != OK:
		# The only step that removes PATH, so the only one that rolls back.
		if dir.file_exists(BACKUP_PATH):
			dir.rename(BACKUP_PATH, PATH)
		return false

	# 6. PATH already holds the new bytes, so the write IS durable. Reporting
	#    false here would make a demolish discard a save that actually
	#    succeeded, re-creating the double-credit from the other side.
	if dir.file_exists(BACKUP_PATH):
		dir.remove(BACKUP_PATH)
	return true

static func _parses(path: String) -> bool:
	return typeof(_read(path)) == TYPE_DICTIONARY

## JSON.new().parse() rather than JSON.parse_string(): the static helper PUSHES
## an engine error on malformed input, and a truncated save is the ordinary case
## this whole algorithm exists for, not an exceptional one. The instance form
## returns an error code instead, which keeps a corrupt file from spamming a
## console the player cannot see -- and keeps GUT from failing the recovery test
## on the error it is deliberately provoking.
static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data

## ONE source selection, shared by everything that reads the save. Two
## independent choices would let the run and the persistent state come from
## DIFFERENT files, and the autosave commits that mixture ten seconds later as
## one perfectly valid payload.
##
## The fallback triggers on a PARSE failure, never on a decode refusal: a
## refused run is exactly when the persistent half must still be readable.
static func _select() -> Variant:
	var primary: Variant = _read(PATH)
	if typeof(primary) == TYPE_DICTIONARY:
		return primary
	var backup: Variant = _read(BACKUP_PATH)
	if typeof(backup) == TYPE_DICTIONARY:
		return backup
	return null

## Everything the save carries, read from one parsed dictionary.
static func load_all(catalog_path := "res://data/tenants.json",
		blueprints_path := "res://data/blueprints.json") -> Dictionary:
	var parsed: Variant = _select()
	if typeof(parsed) != TYPE_DICTIONARY:
		# No save file is still a DEFS-LOADED Meta, never a bare Meta.new():
		# GameState checks is_usable() unconditionally, so a bare one would make
		# a brand-new game invalid.
		return {"state": null, "meta": SaveCodec.salvage_meta({}, blueprints_path)}
	var data := parsed as Dictionary
	return {
		"state": SaveCodec.decode(data, catalog_path, blueprints_path),
		# From the SAME parsed dictionary, so a refused run still surrenders its
		# tree and the two can never come from different files.
		"meta": SaveCodec.salvage_meta(data, blueprints_path),
	}

## The saved state, or null if there is nothing to load or it cannot be read.
## Null always means "start a new game" -- never a partly applied save.
static func load_state(catalog_path := "res://data/tenants.json",
		blueprints_path := "res://data/blueprints.json") -> GameState:
	return load_all(catalog_path, blueprints_path)["state"]

## The persistent half, salvaged even when the run is refused. Null ONLY when
## the shipped blueprint catalog will not load, which is fatal.
static func load_meta(blueprints_path := "res://data/blueprints.json") -> Meta:
	return load_all("res://data/tenants.json", blueprints_path)["meta"]

static func clear() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for path in [PATH, TEMP_PATH, BACKUP_PATH]:
		if dir.file_exists(path):
			dir.remove(path)
		elif dir.dir_exists(path):
			# file_exists() is FALSE for a directory, so a test fixture that
			# pre-creates one at PATH would otherwise survive before_each and
			# become the fixture for every later test in that file.
			dir.remove(path)
