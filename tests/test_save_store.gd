extends GutTest

## The save file is the one thing a player cannot re-earn, and after prestige it
## carries permanent progress. These tests are about the FILE HANDLING only --
## what goes in it is test_save_codec.gd's job.

func before_each() -> void:
	SaveStore.clear()

func after_each() -> void:
	SaveStore.clear()

func fresh() -> GameState:
	return GameState.new(6, 1, 1)

func write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func test_a_save_over_an_existing_file_succeeds_and_loads_back() -> void:
	assert_true(SaveStore.save(fresh()), "first save")
	assert_true(SaveStore.save(fresh()), "second save, over the first")
	assert_not_null(SaveStore.load_state(), "the replaced file still loads")

func test_a_pre_existing_backup_does_not_brick_the_next_save() -> void:
	# The bricking case: a crash between the commit and the cleanup leaves both
	# PATH and BACKUP present, and an algorithm that cannot rename onto an
	# existing destination would then fail forever.
	assert_true(SaveStore.save(fresh()), "seed a real save")
	write_raw(SaveStore.BACKUP_PATH, "{}")
	assert_true(SaveStore.save(fresh()), "a stale backup must not block rotation")

func test_load_state_falls_back_to_the_backup_when_the_save_is_gone() -> void:
	assert_true(SaveStore.save(fresh()), "seed")
	var dir := DirAccess.open("user://")
	dir.rename(SaveStore.PATH, SaveStore.BACKUP_PATH)
	assert_false(FileAccess.file_exists(SaveStore.PATH), "PATH is gone")
	assert_not_null(SaveStore.load_state(), "the backup is loadable")

func test_has_save_agrees_with_load_state() -> void:
	# Otherwise test_board_input.gd's assert_false(has_save()) silently stops
	# meaning what it says.
	assert_true(SaveStore.save(fresh()), "seed")
	var dir := DirAccess.open("user://")
	dir.rename(SaveStore.PATH, SaveStore.BACKUP_PATH)
	assert_true(SaveStore.has_save(), "a backup-only state still has a save")

func test_clear_removes_the_backup_too() -> void:
	assert_true(SaveStore.save(fresh()), "seed")
	write_raw(SaveStore.BACKUP_PATH, "{}")
	SaveStore.clear()
	assert_false(FileAccess.file_exists(SaveStore.BACKUP_PATH),
		"a surviving backup becomes the fixture for every later test")

func test_a_save_whose_temp_write_fails_leaves_the_old_save_intact() -> void:
	# A DIRECTORY at TEMP_PATH makes FileAccess.open fail for real, through
	# save()'s own code path, rather than through a double the static call
	# site could never see.
	assert_true(SaveStore.save(fresh()), "seed a real save")
	var dir := DirAccess.open("user://")
	if dir.file_exists(SaveStore.TEMP_PATH):
		dir.remove(SaveStore.TEMP_PATH)
	dir.make_dir(SaveStore.TEMP_PATH)
	assert_false(SaveStore.save(fresh()), "the write cannot succeed")
	assert_not_null(SaveStore.load_state(), "and the old save survived it")
	dir.remove(SaveStore.TEMP_PATH)

func test_a_corrupt_save_beside_a_good_backup_is_recovered() -> void:
	# _select skips the unparseable PATH; step 1 must then REMOVE it before
	# promoting, or step 3 deletes the only loadable copy.
	assert_true(SaveStore.save(fresh()), "seed")
	var dir := DirAccess.open("user://")
	dir.rename(SaveStore.PATH, SaveStore.BACKUP_PATH)
	write_raw(SaveStore.PATH, "{ this is not json")
	assert_not_null(SaveStore.load_state(), "the good backup is selected")
	assert_true(SaveStore.save(fresh()), "and the next save is not blocked")
	assert_not_null(SaveStore.load_state(), "which still loads")
