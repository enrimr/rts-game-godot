extends GutTest

## Formant selection voices (audio_manager.gd `_build_voices`).
## Locks the bank contract the HUD relies on: every `get_selection_sound()`
## id a human unit can return has male+female variants registered, siege
## stays a plain mechanical sound (play_voice must fall back to it), and the
## baked clips are real audio (non-trivial length, normalized peak).

const HUMAN_KINDS: Array[String] = [
	"select_villager", "select_infantry", "select_archer",
	"select_cavalry", "select_hero", "select_generic",
]

func test_every_human_kind_has_both_gender_banks() -> void:
	for kind: String in HUMAN_KINDS:
		for g: String in ["m", "f"]:
			var count: int = AudioManager._voice_counts.get("%s_%s" % [kind, g], 0) as int
			assert_gt(count, 1, "%s_%s needs at least 2 variants so clicks vary" % [kind, g])
			for i: int in range(count):
				assert_true(AudioManager._pools.has("%s_%s_%d" % [kind, g, i]),
					"every declared variant must be registered")

func test_naval_has_a_male_bank_for_the_fallback() -> void:
	assert_gt(AudioManager._voice_counts.get("select_naval_m", 0) as int, 1,
		"ship crews voice-bank exists; play_voice(female) falls back to it")
	assert_eq(AudioManager._voice_counts.get("select_naval_f", 0) as int, 0)

func test_siege_stays_mechanical() -> void:
	assert_false(AudioManager._voice_counts.has("select_siege_m"),
		"machines do not talk — play_voice must fall back to the plain clunk")
	assert_true(AudioManager._pools.has("select_siege"))

func test_clips_are_real_audio() -> void:
	for kind: String in ["select_villager_m_0", "select_villager_f_0",
			"select_hero_m_0", "select_naval_m_0"]:
		var pool: Array = AudioManager._pools[kind] as Array
		var stream: AudioStreamWAV = (pool[0] as AudioStreamPlayer).stream as AudioStreamWAV
		var samples: int = stream.data.size() / 2
		assert_gt(samples, int(AudioManager.SAMPLE_RATE * 0.1),
			"%s must be at least 100 ms long" % kind)
		var peak: int = 0
		var data: PackedByteArray = stream.data
		for i: int in range(0, data.size(), 2):
			var v: int = data[i] | (data[i + 1] << 8)
			if v >= 32768:
				v -= 65536
			peak = maxi(peak, absi(v))
		assert_between(float(peak) / 32767.0, 0.30, 0.60,
			"%s must be normalized near VOICE_PEAK" % kind)

func test_play_voice_survives_unknown_ids() -> void:
	AudioManager.play_voice("select_nonexistent", false)
	AudioManager.play_voice("select_siege", true)
	pass_test("no crash on fallback paths")
