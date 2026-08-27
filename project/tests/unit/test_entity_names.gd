extends GutTest

## EntityNames resolves localized unit/building names via generated
## translation keys (UNIT_<ID> / BUILDING_<ID>), falling back to the raw
## resource display_name when no translation exists (hero proper nouns).

const VILLAGER_DATA: UnitResource = preload("res://resources/units/villager_data.tres")
const TOWN_CENTER_DATA: BuildingResource = preload("res://resources/buildings/town_center.tres")
const HERO_BENCOMO_DATA: UnitResource = preload("res://resources/units/hero_bencomo.tres")

var _previous_locale: String = ""

func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()

func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)

func test_unit_key_hit_spanish() -> void:
	TranslationServer.set_locale("es")
	assert_eq(EntityNames.unit_name(VILLAGER_DATA), "Aldeano")

func test_unit_key_hit_english() -> void:
	TranslationServer.set_locale("en")
	assert_eq(EntityNames.unit_name(VILLAGER_DATA), "Villager")

func test_building_key_hit_spanish() -> void:
	TranslationServer.set_locale("es")
	assert_eq(EntityNames.building_name(TOWN_CENTER_DATA), "Centro Urbano")

func test_key_miss_falls_back_to_display_name() -> void:
	TranslationServer.set_locale("es")
	# Hero names are proper nouns: no UNIT_BENCOMO key exists on purpose.
	assert_eq(EntityNames.unit_name(HERO_BENCOMO_DATA), HERO_BENCOMO_DATA.display_name)

func test_missing_id_falls_back_to_display_name() -> void:
	var data: UnitResource = UnitResource.new()
	data.id = ""
	data.display_name = "Nameless"
	assert_eq(EntityNames.unit_name(data), "Nameless")

func test_null_resource_returns_empty() -> void:
	assert_eq(EntityNames.unit_name(null), "")
	assert_eq(EntityNames.building_name(null), "")
