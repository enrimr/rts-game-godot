extends GutTest

## Pins the research-UI glyph contract: every shipped technology id resolves
## to its own texture instance via UiIcons.tech_glyph, and unknown ids share
## the generic research fallback instead of crashing the HUD.

const TECH_DIR: String = "res://resources/technologies"

func _shipped_tech_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir: DirAccess = DirAccess.open(TECH_DIR)
	assert_not_null(dir, "technology resource dir must open")
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var tech: TechnologyResource = load("%s/%s" % [TECH_DIR, file]) as TechnologyResource
		assert_not_null(tech, file + " must load as TechnologyResource")
		ids.append(tech.id)
	return ids

func test_every_shipped_tech_has_a_dedicated_glyph() -> void:
	var ids: Array[String] = _shipped_tech_ids()
	assert_eq(ids.size(), 32, "32 technologies shipped")
	for id: String in ids:
		assert_true(id in UiIcons.TECH_GLYPHS,
			"tech '%s' must have a dedicated glyph id" % id)

func test_tech_glyphs_are_non_null_and_distinct() -> void:
	var seen: Dictionary = {}
	for id: String in UiIcons.TECH_GLYPHS:
		var tex: Texture2D = UiIcons.tech_glyph(id)
		assert_not_null(tex, "glyph for '%s'" % id)
		var key: int = tex.get_instance_id()
		assert_false(seen.has(key),
			"'%s' must not share a texture with '%s'" % [id, seen.get(key, "")])
		seen[key] = id

func test_unknown_id_falls_back_to_generic_research_glyph() -> void:
	var fallback: Texture2D = UiIcons.tech_glyph("some_future_tech")
	assert_not_null(fallback)
	assert_eq(fallback, UiIcons.tech_glyph("another_unknown"),
		"all unknown ids share the generic research glyph")
	assert_ne(fallback, UiIcons.tech_glyph("loom"),
		"the fallback is not a known tech's glyph")
