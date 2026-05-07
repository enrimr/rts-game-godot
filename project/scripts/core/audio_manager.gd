extends Node

## AudioManager — procedural PCM sound synthesis, no audio files required.
## All waveforms are generated at startup and stored as AudioStreamWAV resources.
## Call AudioManager.play("sound_id") from anywhere.

const SAMPLE_RATE: int = 22050

# Polyphony pools: each sound id gets N players so rapid repeats don't cut out
const POOL_SIZE: int = 4

var _pools: Dictionary = {}   # sound_id -> Array[AudioStreamPlayer]
var _pool_idx: Dictionary = {} # sound_id -> int (round-robin cursor)
var _music_player: AudioStreamPlayer = null

func _ready() -> void:
	_build_all()
	_build_music()

# ---------------------------------------------------------------------------
# Public
# ---------------------------------------------------------------------------

func play(sound_id: String, volume_db: float = 0.0) -> void:
	if not _pools.has(sound_id):
		return
	var pool: Array = _pools[sound_id] as Array
	var idx: int = _pool_idx.get(sound_id, 0) as int
	var player: AudioStreamPlayer = pool[idx] as AudioStreamPlayer
	var sfx_db: float = GameSettings.volume_to_db(GameSettings.sfx_volume)
	player.volume_db = volume_db + sfx_db
	player.play()
	_pool_idx[sound_id] = (idx + 1) % pool.size()

func play_music() -> void:
	if is_instance_valid(_music_player) and not _music_player.playing:
		_music_player.play()
	_apply_music_volume()

func stop_music() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()

func apply_settings() -> void:
	_apply_music_volume()

func _apply_music_volume() -> void:
	if is_instance_valid(_music_player):
		var base_db: float = -22.0
		var vol_db: float = GameSettings.volume_to_db(GameSettings.music_volume)
		_music_player.volume_db = base_db + vol_db

# ---------------------------------------------------------------------------
# Sound bank definition
# ---------------------------------------------------------------------------

func _build_all() -> void:
	# UI / selection
	_register("ui_click",       _synth_click())
	_register("ui_select",      _synth_select())
	_register("ui_error",       _synth_error())

	# Commands
	_register("cmd_move",       _synth_cmd_move())
	_register("cmd_attack",     _synth_cmd_attack())

	# Combat
	_register("hit_melee",      _synth_hit_melee())
	_register("hit_ranged",     _synth_hit_ranged())
	_register("unit_die",       _synth_unit_die())

	# Construction
	_register("build_place",    _synth_build_place())
	_register("build_complete", _synth_build_complete())
	_register("build_destroy",  _synth_build_destroy())

	# Economy
	_register("chop_wood",      _synth_chop())
	_register("mine_resource",  _synth_mine())
	_register("gather_food",    _synth_gather_food())

	# Training
	_register("train_queue",    _synth_train_queue())
	_register("unit_ready",     _synth_unit_ready())

	# Age advancement
	_register("age_advance",    _synth_age_advance())
	_register("age_complete",   _synth_age_complete())

	# Population cap
	_register("pop_cap",        _synth_pop_cap())

# ---------------------------------------------------------------------------
# Registration helpers
# ---------------------------------------------------------------------------

func _register(sound_id: String, stream: AudioStreamWAV, pool_size: int = POOL_SIZE) -> void:
	var pool: Array[AudioStreamPlayer] = []
	for _i: int in range(pool_size):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.stream = stream
		player.bus = "Master"
		add_child(player)
		pool.append(player)
	_pools[sound_id] = pool
	_pool_idx[sound_id] = 0

# ---------------------------------------------------------------------------
# PCM synthesis helpers
# ---------------------------------------------------------------------------

func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		var v: int = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2]     = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	wav.data = data
	return wav

func _sine(freq: float, duration: float, amp: float = 0.5, fade_out: bool = true) -> PackedFloat32Array:
	var n: int = int(SAMPLE_RATE * duration)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = 1.0
		if fade_out:
			env = 1.0 - float(i) / float(n)
		buf[i] = sin(TAU * freq * t) * amp * env
	return buf

func _square(freq: float, duration: float, amp: float = 0.3, fade_out: bool = true) -> PackedFloat32Array:
	var n: int = int(SAMPLE_RATE * duration)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = 1.0 - float(i) / float(n) if fade_out else 1.0
		var v: float = 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0
		buf[i] = v * amp * env
	return buf

func _noise(duration: float, amp: float = 0.4, fade_out: bool = true) -> PackedFloat32Array:
	var n: int = int(SAMPLE_RATE * duration)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	for i: int in range(n):
		var env: float = 1.0 - float(i) / float(n) if fade_out else 1.0
		buf[i] = randf_range(-1.0, 1.0) * amp * env
	return buf

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = maxi(a.size(), b.size())
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i: int in range(n):
		var va: float = a[i] if i < a.size() else 0.0
		var vb: float = b[i] if i < b.size() else 0.0
		out[i] = clampf(va + vb, -1.0, 1.0)
	return out

func _concat(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(a.size() + b.size())
	for i: int in range(a.size()): out[i] = a[i]
	for i: int in range(b.size()): out[a.size() + i] = b[i]
	return out

func _sweep(freq_start: float, freq_end: float, duration: float, amp: float = 0.5) -> PackedFloat32Array:
	var n: int = int(SAMPLE_RATE * duration)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var phase: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / float(n)
		var freq: float = lerp(freq_start, freq_end, t)
		var env: float = 1.0 - t
		buf[i] = sin(phase) * amp * env
		phase += TAU * freq / SAMPLE_RATE
	return buf

# ---------------------------------------------------------------------------
# Individual sound synthesizers
# ---------------------------------------------------------------------------

func _synth_click() -> AudioStreamWAV:
	# Short soft tick
	return _make_wav(_mix(_sine(880.0, 0.06, 0.25), _noise(0.04, 0.08)))

func _synth_select() -> AudioStreamWAV:
	# Rising two-tone chirp
	var a: PackedFloat32Array = _sine(440.0, 0.07, 0.35)
	var b: PackedFloat32Array = _sine(660.0, 0.07, 0.30)
	return _make_wav(_concat(a, b))

func _synth_error() -> AudioStreamWAV:
	# Descending buzzy tone
	return _make_wav(_sweep(300.0, 150.0, 0.18, 0.40))

func _synth_cmd_move() -> AudioStreamWAV:
	# Light double-tap
	var a: PackedFloat32Array = _sine(520.0, 0.05, 0.30)
	var gap: PackedFloat32Array = PackedFloat32Array(); gap.resize(int(SAMPLE_RATE * 0.04)); gap.fill(0.0)
	var b: PackedFloat32Array = _sine(600.0, 0.05, 0.25)
	return _make_wav(_concat(_concat(a, gap), b))

func _synth_cmd_attack() -> AudioStreamWAV:
	# Sharp aggressive blip
	return _make_wav(_mix(_square(200.0, 0.08, 0.35), _noise(0.06, 0.20)))

func _synth_hit_melee() -> AudioStreamWAV:
	# Thud: low noise burst
	return _make_wav(_mix(_noise(0.08, 0.50), _sine(120.0, 0.08, 0.30)))

func _synth_hit_ranged() -> AudioStreamWAV:
	# Lighter thwack
	return _make_wav(_mix(_noise(0.05, 0.35), _sine(200.0, 0.05, 0.20)))

func _synth_unit_die() -> AudioStreamWAV:
	# Descending sweep + noise
	return _make_wav(_mix(_sweep(300.0, 80.0, 0.28, 0.40), _noise(0.20, 0.25)))

func _synth_build_place() -> AudioStreamWAV:
	# Wooden thunk
	return _make_wav(_mix(_noise(0.10, 0.45), _sine(180.0, 0.10, 0.35)))

func _synth_build_complete() -> AudioStreamWAV:
	# Ascending three-note fanfare
	var a: PackedFloat32Array = _sine(440.0, 0.09, 0.35)
	var b: PackedFloat32Array = _sine(550.0, 0.09, 0.35)
	var c: PackedFloat32Array = _sine(660.0, 0.14, 0.40)
	return _make_wav(_concat(_concat(a, b), c))

func _synth_build_destroy() -> AudioStreamWAV:
	# Rumble + crumble
	return _make_wav(_mix(_noise(0.35, 0.55), _sweep(250.0, 60.0, 0.35, 0.30)))

func _synth_chop() -> AudioStreamWAV:
	# Axe chop: sharp mid noise
	return _make_wav(_mix(_noise(0.06, 0.50), _sine(280.0, 0.06, 0.20)))

func _synth_mine() -> AudioStreamWAV:
	# Pickaxe clink: high metallic
	return _make_wav(_mix(_sine(900.0, 0.07, 0.30), _noise(0.05, 0.15)))

func _synth_gather_food() -> AudioStreamWAV:
	# Soft rustle
	return _make_wav(_noise(0.08, 0.30))

func _synth_train_queue() -> AudioStreamWAV:
	# Confirmation blip
	return _make_wav(_sine(500.0, 0.08, 0.30))

func _synth_unit_ready() -> AudioStreamWAV:
	# Two ascending tones
	var a: PackedFloat32Array = _sine(480.0, 0.08, 0.30)
	var b: PackedFloat32Array = _sine(720.0, 0.10, 0.35)
	return _make_wav(_concat(a, b))

func _synth_age_advance() -> AudioStreamWAV:
	# Slow dramatic sweep upward
	return _make_wav(_mix(_sweep(220.0, 440.0, 0.60, 0.45), _noise(0.40, 0.10)))

func _synth_age_complete() -> AudioStreamWAV:
	# Four-note ascending fanfare
	var notes: Array[float] = [330.0, 415.0, 495.0, 660.0]
	var durations: Array[float] = [0.10, 0.10, 0.10, 0.22]
	var out: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(notes.size()):
		out = _concat(out, _sine(notes[i], durations[i], 0.40))
	return _make_wav(out)

func _synth_pop_cap() -> AudioStreamWAV:
	# Descending two-tone warning
	var a: PackedFloat32Array = _sine(400.0, 0.09, 0.35)
	var b: PackedFloat32Array = _sine(280.0, 0.12, 0.35)
	return _make_wav(_concat(a, b))

# ---------------------------------------------------------------------------
# Background music
# ---------------------------------------------------------------------------

func _build_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -22.0
	_music_player.bus = "Master"
	add_child(_music_player)
	_music_player.stream = _synth_melody_loop()

func _sine_note(freq: float, duration: float, amp: float) -> PackedFloat32Array:
	# ADSR-lite envelope: 10 % attack, 80 % sustain, 10 % release
	var n: int = int(SAMPLE_RATE * duration)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var attack_end: int  = int(n * 0.10)
	var release_start: int = int(n * 0.90)
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var env: float
		if i < attack_end:
			env = float(i) / float(attack_end)
		elif i >= release_start:
			env = 1.0 - float(i - release_start) / float(n - release_start)
		else:
			env = 1.0
		buf[i] = sin(TAU * freq * t) * amp * env
	return buf

func _silent(duration: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(int(SAMPLE_RATE * duration))
	buf.fill(0.0)
	return buf

func _synth_melody_loop() -> AudioStreamWAV:
	# D Dorian pentatonic: D3 E3 F3 A3 C4 D4 (medieval-ish, calm)
	# Frequencies (Hz)
	const D3: float  = 146.83
	const E3: float  = 164.81
	const F3: float  = 174.61
	const A3: float  = 220.00
	const C4: float  = 261.63
	const D4: float  = 293.66
	const A2: float  = 110.00
	const D2: float  = 73.41

	# Beat duration in seconds (slow, meditative)
	const B: float = 0.55

	# Melody: (freq, beats)
	var melody: Array = [
		[D3,  1.0], [E3,  1.0], [F3,  1.0], [A3,  2.0],
		[C4,  1.0], [A3,  1.0], [F3,  1.5], [E3,  0.5],
		[D3,  2.0], [E3,  1.0], [A3,  1.0], [C4,  1.0],
		[D4,  2.0], [C4,  1.0], [A3,  1.0], [F3,  1.0],
		[E3,  1.5], [D3,  0.5], [F3,  1.0], [A3,  2.0],
		[C4,  1.0], [D4,  1.5], [C4,  0.5], [A3,  2.0],
		[F3,  1.0], [E3,  1.0], [D3,  4.0],
	]

	# Drone: alternates D2 and A2 every 4 beats for subtle depth
	var drone: Array = [
		[D2, 4.0], [A2, 4.0], [D2, 4.0], [A2, 4.0],
		[D2, 4.0], [A2, 4.0], [D2, 8.0],
	]

	# Build melody buffer
	var mel_buf: PackedFloat32Array = PackedFloat32Array()
	for entry: Array in melody:
		var freq: float = entry[0] as float
		var beats: float = entry[1] as float
		var dur: float = beats * B
		var gap: float = 0.04
		mel_buf = _concat(mel_buf, _sine_note(freq, maxf(dur - gap, 0.05), 0.28))
		if gap > 0.0:
			mel_buf = _concat(mel_buf, _silent(gap))

	# Build drone buffer to match melody length
	var drone_buf: PackedFloat32Array = PackedFloat32Array()
	for entry: Array in drone:
		var freq: float = entry[0] as float
		var beats: float = entry[1] as float
		drone_buf = _concat(drone_buf, _sine_note(freq, beats * B, 0.12))
	# Pad drone to melody length if needed
	if drone_buf.size() < mel_buf.size():
		var pad: PackedFloat32Array = _silent(float(mel_buf.size() - drone_buf.size()) / float(SAMPLE_RATE))
		drone_buf = _concat(drone_buf, pad)

	var mixed: PackedFloat32Array = _mix(mel_buf, drone_buf)

	var wav: AudioStreamWAV = _make_wav(mixed)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = mixed.size()
	return wav
