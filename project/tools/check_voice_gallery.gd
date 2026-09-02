extends Node2D

## Voice-bank audition gate: verifies EVERY baked voice clip (selection +
## order acknowledgments, all civs and genders) is real audio, prints a
## per-bank census, and exports a listenable subset to WAV files
## (CALIMA_SHOT_DIR, default /tmp/calima-voices). CALIMA_CIVS narrows the
## export (comma list; default "default,guanches,canarii,fenicios").

func _ready() -> void:
	AudioManager.ensure_voices_ready()
	var dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if dir.is_empty():
		dir = "/tmp/calima-voices"
	DirAccess.make_dir_recursive_absolute(dir)
	var civs_env: String = OS.get_environment("CALIMA_CIVS")
	if civs_env.is_empty():
		civs_env = "default,guanches,canarii,fenicios"
	var export_civs: PackedStringArray = civs_env.split(",", false)
	var ids: Array = []
	for sound_id: Variant in AudioManager._pools.keys():
		if (sound_id as String).begins_with("select_") or (sound_id as String).begins_with("ack_"):
			ids.append(sound_id)
	ids.sort()
	var bad: int = 0
	var exported: int = 0
	for sound_id: String in ids:
		var pool: Array = AudioManager._pools[sound_id] as Array
		var stream: AudioStreamWAV = (pool[0] as AudioStreamPlayer).stream as AudioStreamWAV
		var samples: int = stream.data.size() / 2
		var dur: float = float(samples) / float(AudioManager.SAMPLE_RATE)
		var peak: int = 0
		var data: PackedByteArray = stream.data
		for i: int in range(0, data.size(), 2):
			var v: int = data[i] | (data[i + 1] << 8)
			if v >= 32768:
				v -= 65536
			peak = maxi(peak, absi(v))
		if dur < 0.05 or float(peak) / 32767.0 < 0.05:
			bad += 1
			print("VOICE_GALLERY: DEGENERATE clip %s (%.2fs peak %.2f)" % [
				sound_id, dur, float(peak) / 32767.0])
		for civ: String in export_civs:
			if sound_id.contains("_%s_" % civ) or not sound_id.contains("_"):
				stream.save_to_wav("%s/%s.wav" % [dir, sound_id])
				exported += 1
				break
	print("VOICE_GALLERY: %d clips checked, %d exported to %s" % [ids.size(), exported, dir])
	if bad > 0 or ids.is_empty():
		print("VOICE_GALLERY: FAIL")
		get_tree().quit(1)
		return
	print("VOICE_GALLERY: done")
	get_tree().quit(0)
