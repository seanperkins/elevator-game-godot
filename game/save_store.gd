class_name SaveStore
extends RefCounted

## Reads and writes the save file. All the decisions about WHAT is saved live in
## SaveCodec; this is only the file handling.
##
## Writes are ATOMIC: the new save goes to a temp file which then replaces the
## real one. A phone killed mid-write is the ordinary case, not the exotic one,
## and a half-written JSON file is worse than an old save -- it loses everything
## rather than a few seconds.
##
## The file lives in user://, which on iOS is inside the app container and on
## the web is IndexedDB. Nothing here trusts its contents: SaveCodec refuses a
## save it does not recognise, and every dynamic string it produces is rendered
## through Label rather than BBCode, per the design spec's note about a
## github.io origin shared with every other Pages site on the account.

const PATH := "user://save.json"
const TEMP_PATH := "user://save.json.tmp"

static func has_save() -> bool:
	return FileAccess.file_exists(PATH)

static func save(state: GameState) -> bool:
	var f := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(SaveCodec.encode(state)))
	f.close()

	# Replace only once the new file is completely written.
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(PATH):
		dir.remove(PATH)
	return dir.rename(TEMP_PATH, PATH) == OK

## The saved state, or null if there is nothing to load or it cannot be read.
## Null always means "start a new game" -- never a partly applied save.
static func load_state() -> GameState:
	if not FileAccess.file_exists(PATH):
		return null
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return SaveCodec.decode(parsed)

static func clear() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.file_exists(PATH):
		dir.remove(PATH)
	if dir.file_exists(TEMP_PATH):
		dir.remove(TEMP_PATH)
