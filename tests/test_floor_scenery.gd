extends GutTest

## Floor scenery lands one image at a time, so the interesting cases are the
## MISSING ones -- six of the seven kinds have no art yet and must draw the
## plain ground rather than a placeholder or an error.

func test_a_kind_with_art_resolves_to_a_texture() -> void:
	var tex := FloorScenery.texture_for("apartments")
	assert_not_null(tex, "art/floors/apartments.png should be imported")
	assert_eq(tex.get_width(), 416, "the 2x width of the 208-unit region")
	assert_eq(tex.get_height(), 240, "the 2x height of the 120-unit row")

func test_the_art_matches_the_region_it_covers() -> void:
	# 208 x 120 units at 2x. A mismatch here means the image is stretched, which
	# on flat poster art shows immediately as skewed doorframes.
	var tex := FloorScenery.texture_for("apartments")
	assert_almost_eq(float(tex.get_width()) / float(tex.get_height()),
		FloorRow.STRIP_RIGHT / BuildingView.FLOOR_HEIGHT, 0.01,
		"the image ratio must equal the region's")

func test_a_kind_without_art_is_null_not_an_error() -> void:
	# Five of six shipped kinds are in this state today. It has to be quiet.
	assert_null(FloorScenery.texture_for("law_firm"))
	assert_false(FloorScenery.has_art("law_firm"))

func test_a_vacant_floor_asks_for_nothing() -> void:
	assert_null(FloorScenery.texture_for(""))

func test_an_unknown_id_does_not_throw() -> void:
	assert_null(FloorScenery.texture_for("not_a_kind_at_all"))

func test_the_lookup_is_cached() -> void:
	# Called from refresh(), which runs every frame for every floor.
	var a := FloorScenery.texture_for("apartments")
	var b := FloorScenery.texture_for("apartments")
	assert_true(a == b, "the same resource, not a reload per frame")
