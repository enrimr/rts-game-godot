extends Node2D

## Voice-bank audition gate: exports every baked selection voice to WAV files
## (CALIMA_SHOT_DIR, default /tmp/calima-voices) and prints a census — id,
## duration, peak — so a regression in the formant synth is visible in the
## numbers and the clips themselves can be listened to from the terminal.

func _ready() -> void:
	AudioManager.ensure_voices_ready()
	var dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if dir.is_empty():
		dir = "/tmp/calima-voices"
	DirAccess.make_dir_recursive_absolute(dir)
	var ids: Array = []
	for sound_id: Variant in AudioManager._pools.keys():
		if (sound_id as String).begins_with("select_"):
			ids.append(sound_id)
	ids.sort()
	var bad: int = 0
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
		var peak01: float = float(peak) / 32767.0
		print("VOICE %-26s %5.2fs peak %.2f" % [sound_id, dur, peak01])
		if dur < 0.05 or peak01 < 0.05:
			bad += 1
			print("VOICE_GALLERY: DEGENERATE clip %s" % sound_id)
		stream.save_to_wav("%s/%s.wav" % [dir, sound_id])
	print("VOICE_GALLERY: %d clips exported to %s" % [ids.size(), dir])
	if bad > 0 or ids.is_empty():
		print("VOICE_GALLERY: FAIL")
		get_tree().quit(1)
		return
	print("VOICE_GALLERY: done")
	get_tree().quit(0)
