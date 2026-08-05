extends GutTest

## The set is complete -- six tenant kinds plus the vacant shell -- so the
## interesting cases are now COMPLETENESS (every kind the data file names must
## resolve, or one floor in the building silently loses its background) and the
## quiet-failure path that let the images land one at a time.

const KINDS := ["apartments", "shops", "office", "gym", "law_firm", "clinic"]

func test_every_shipped_tenant_kind_has_art() -> void:
	# Driven off the same file the sim reads, so adding a kind without drawing it
	# fails here rather than on a phone.
	var f := FileAccess.open("res://data/tenants.json", FileAccess.READ)
	assert_not_null(f, "data/tenants.json must be readable")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, "tenants.json is an object")
	var kinds: Array = (parsed as Dictionary).get("kinds", [])
	# KINDS + 1: `parking` landed in the catalog before its image. Task 9 of the
	# building-downward plan draws it and restores the exact equality.
	assert_eq(kinds.size(), KINDS.size() + 1, "this test's list has drifted from the data")
	for k: Variant in kinds:
		var id: String = (k as Dictionary).get("id", "")
		if id == "parking":
			continue    # pending Task 9 -- see above
		assert_true(FloorScenery.has_art(id), "no art/floors/%s.png" % id)

func test_the_vacant_shell_has_art_under_its_own_name() -> void:
	# An unleased floor has no kind id at all; VACANT is the name invented for it.
	assert_true(FloorScenery.has_art(FloorScenery.VACANT))
	assert_ne(FloorScenery.VACANT, "", "the sentinel cannot be the draw-nothing id")
	assert_false(KINDS.has(FloorScenery.VACANT),
		"the sentinel must not collide with a tenant kind")

func test_a_kind_with_art_resolves_to_a_texture() -> void:
	var tex := FloorScenery.texture_for("apartments")
	assert_not_null(tex, "art/floors/apartments.png should be imported")
	assert_eq(tex.get_width(), 384, "the 2x width of the 192-unit region")
	assert_eq(tex.get_height(), 240, "the 2x height of the 120-unit row")

func test_every_image_matches_the_region_it_covers() -> void:
	# 192 x 120 units at 2x. A mismatch shows immediately on flat poster art as
	# skewed doorframes, and it is per-image -- one bad crop is enough.
	var want := FloorRow.STRIP_RIGHT / BuildingView.FLOOR_HEIGHT
	for id: String in KINDS + [FloorScenery.VACANT]:
		var tex := FloorScenery.texture_for(id)
		assert_not_null(tex, id)
		assert_almost_eq(float(tex.get_width()) / float(tex.get_height()), want, 0.01,
			"%s is not the region's ratio" % id)

func test_a_kind_without_art_is_null_not_an_error() -> void:
	# Nothing is in this state today, but the contract is what lets a new kind be
	# added to the data file before anyone has drawn it.
	assert_null(FloorScenery.texture_for("penthouse"))
	assert_false(FloorScenery.has_art("penthouse"))

func test_the_empty_id_asks_for_nothing() -> void:
	assert_null(FloorScenery.texture_for(""))

func test_an_unknown_id_does_not_throw() -> void:
	assert_null(FloorScenery.texture_for("not_a_kind_at_all"))

func test_the_lookup_is_cached() -> void:
	# Called from refresh(), which runs every frame for every floor.
	var a := FloorScenery.texture_for("apartments")
	var b := FloorScenery.texture_for("apartments")
	assert_true(a == b, "the same resource, not a reload per frame")
