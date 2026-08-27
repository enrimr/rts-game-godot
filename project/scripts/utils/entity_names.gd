class_name EntityNames
extends RefCounted

## Resolves the localized display name of a unit or building resource.
## Looks up a generated translation key ("UNIT_<ID>" / "BUILDING_<ID>") and
## falls back to the resource's raw display_name when no translation exists
## (e.g. hero proper nouns, which are intentionally not translated).

static func unit_name(data: Resource) -> String:
	return _resolve("UNIT_", data)

static func building_name(data: Resource) -> String:
	return _resolve("BUILDING_", data)

static func _resolve(prefix: String, data: Resource) -> String:
	if data == null:
		return ""
	var fallback_v: Variant = data.get("display_name")
	var fallback: String = str(fallback_v) if fallback_v != null else ""
	var id_v: Variant = data.get("id")
	if id_v == null or str(id_v).is_empty():
		return fallback
	var key: StringName = StringName(prefix + str(id_v).to_upper())
	var translated: String = str(TranslationServer.translate(key))
	return translated if translated != str(key) else fallback
