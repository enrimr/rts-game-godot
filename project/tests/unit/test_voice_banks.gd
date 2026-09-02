extends GutTest

## Formant voice banks (audio_manager.gd `_build_voices`).
## Locks the cast contract: every voice kind bakes per civ and gender, order
## acknowledgments exist, siege stays a plain mechanical sound (play_voice
## must fall back to it), the per-civ pitch accent is real, and clips are
## real audio (non-trivial length, normalized peak).

const GENDERED_KINDS: Array[String] = [
	"select_villager", "select_infantry", "select_archer",
	"select_cavalry", "select_hero", "select_generic",
	"ack_move", "ack_attack",
]

func before_all() -> void:
	# The bank bakes on a worker thread at startup — settle it first.
	AudioManager.ensure_voices_ready()

func test_every_kind_bakes_for_every_civ_and_gender() -> void:
	for kind: String in GENDERED_KINDS:
		for civ: String in AudioManager.VOICE_CIV_POOLS:
			for g: String in ["m", "f"]:
				var count: int = AudioManager._voice_counts.get(
					"%s_%s_%s" % [kind, civ, g], 0) as int
				assert_gt(count, 1, "%s_%s_%s needs 2+ variants so clicks vary" % [kind, civ, g])

func test_naval_has_male_banks_only() -> void:
	assert_gt(AudioManager._voice_counts.get("select_naval_default_m", 0) as int, 1,
		"ship crews voice-bank exists; play_voice(female) falls back to it")
	assert_eq(AudioManager._voice_counts.get("select_naval_default_f", 0) as int, 0)

func test_siege_stays_mechanical() -> void:
	assert_false(AudioManager._voice_counts.has("select_siege_default_m"),
		"machines do not talk — play_voice must fall back to the plain clunk")
	assert_true(AudioManager._pools.has("select_siege"))

func test_civ_accent_changes_the_words_and_pitch() -> void:
	assert_ne(AudioManager.VOICE_CIV_PITCH["guanches"], AudioManager.VOICE_CIV_PITCH["fenicios"],
		"deep Guanches and bright Fenicios must not share an accent")
	var a: Array = AudioManager._voice_words_for("select_villager", "guanches", "m",
		AudioManager.VOICE_KINDS["select_villager"])
	var b: Array = AudioManager._voice_words_for("select_villager", "fenicios", "m",
		AudioManager.VOICE_KINDS["select_villager"])
	assert_ne(a, b, "each civ speaks from its own syllable pool")
	var again: Array = AudioManager._voice_words_for("select_villager", "guanches", "m",
		AudioManager.VOICE_KINDS["select_villager"])
	assert_eq(a, again, "generation is deterministic — same seed, same lines")

func test_clips_are_real_audio() -> void:
	for kind: String in ["select_villager_default_m_0", "select_villager_guanches_f_0",
			"select_hero_atlantes_m_0", "ack_attack_fenicios_m_0"]:
		var pool: Array = AudioManager._pools[kind] as Array
		var stream: AudioStreamWAV = (pool[0] as AudioStreamPlayer).stream as AudioStreamWAV
		var samples: int = stream.data.size() / 2
		assert_gt(samples, int(AudioManager.SAMPLE_RATE * 0.08),
			"%s must be at least 80 ms long" % kind)
		var peak: int = 0
		var data: PackedByteArray = stream.data
		for i: int in range(0, data.size(), 2):
			var v: int = data[i] | (data[i + 1] << 8)
			if v >= 32768:
				v -= 65536
			peak = maxi(peak, absi(v))
		assert_between(float(peak) / 32767.0, 0.30, 0.60,
			"%s must be normalized near VOICE_PEAK" % kind)

func test_play_voice_survives_unknown_ids_and_civs() -> void:
	AudioManager.play_voice("select_nonexistent", false)
	AudioManager.play_voice("select_siege", true, "guanches")
	AudioManager.play_voice("select_villager", true, "not_a_civ")
	pass_test("no crash on fallback paths")

func test_combat_sounds_rotate_variants() -> void:
	for sound_id: String in ["hit_melee", "chop_wood", "mine_resource", "unit_die"]:
		var pool: Array = AudioManager._pools[sound_id] as Array
		var distinct: Dictionary = {}
		for player: Variant in pool:
			distinct[(player as AudioStreamPlayer).stream] = true
		assert_gt(distinct.size(), 1,
			"%s must carry several takes in its pool" % sound_id)
