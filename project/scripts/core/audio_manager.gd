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

## Play a combat sound only if world_pos is currently visible to the player.
func play_if_visible(sound_id: String, world_pos: Vector2, volume_db: float = 0.0) -> void:
	var fog: FogOfWar = _get_fog()
	if fog != null and fog.get_cell_state(world_pos) != FogOfWar.STATE_VISIBLE:
		return
	play(sound_id, volume_db)

func _get_fog() -> FogOfWar:
	var worlds: Array = get_tree().get_nodes_in_group("world")
	if worlds.is_empty():
		return null
	var fog: Node = (worlds[0] as Node).get_node_or_null("FogOfWar")
	return fog as FogOfWar

func play_music(map_type: int = 0) -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
	_music_player.stream = _build_music_for_map(map_type)
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

	# Unit selection voices
	_register("select_generic",  _synth_sel_generic())
	_register("select_villager", _synth_sel_villager())
	_register("select_infantry", _synth_sel_infantry())
	_register("select_archer",   _synth_sel_archer())
	_register("select_cavalry",  _synth_sel_cavalry())
	_register("select_siege",    _synth_sel_siege())
	_register("select_naval",    _synth_sel_naval())
	_register("select_hero",     _synth_sel_hero())

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

	# Hero critical HP alert
	_register("hero_low_hp",    _synth_hero_low_hp())

	# Weather ambience (looping, pool = 1)
	_register_loop("weather_calima",  _synth_weather_calima())
	_register_loop("weather_storm",   _synth_weather_storm())
	_register_loop("weather_fog",     _synth_weather_fog())
	_register_loop("weather_wind",    _synth_weather_wind())
	_register_loop("weather_ash",     _synth_weather_ash())

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

func _register_loop(sound_id: String, stream: AudioStreamWAV) -> void:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2  # 16-bit mono: bytes/2 = samples
	_register(sound_id, stream, 1)

# ---------------------------------------------------------------------------
# Weather ambient API
# ---------------------------------------------------------------------------

var _weather_ambient_id: String = ""
var _weather_fade_tween: Tween = null

func play_weather_ambient(sound_id: String) -> void:
	if _weather_ambient_id == sound_id:
		return
	stop_weather_ambient()
	if not _pools.has(sound_id):
		return
	_weather_ambient_id = sound_id
	var player: AudioStreamPlayer = (_pools[sound_id] as Array)[0] as AudioStreamPlayer
	var sfx_db: float = GameSettings.volume_to_db(GameSettings.sfx_volume)
	player.volume_db = -80.0
	player.play()
	if is_instance_valid(_weather_fade_tween):
		_weather_fade_tween.kill()
	_weather_fade_tween = create_tween()
	_weather_fade_tween.tween_property(player, "volume_db", -14.0 + sfx_db, 4.0)

func stop_weather_ambient() -> void:
	if _weather_ambient_id.is_empty():
		return
	var prev_id: String = _weather_ambient_id
	_weather_ambient_id = ""
	if not _pools.has(prev_id):
		return
	var player: AudioStreamPlayer = (_pools[prev_id] as Array)[0] as AudioStreamPlayer
	if is_instance_valid(_weather_fade_tween):
		_weather_fade_tween.kill()
	_weather_fade_tween = create_tween()
	_weather_fade_tween.tween_property(player, "volume_db", -80.0, 3.0)
	_weather_fade_tween.tween_callback(func() -> void: player.stop())

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

func _synth_hero_low_hp() -> AudioStreamWAV:
	# Urgent triple pulse: high–low–high, tight gaps, loud
	var hi: PackedFloat32Array = _sine(880.0, 0.07, 0.55)
	var lo: PackedFloat32Array = _sine(520.0, 0.05, 0.40)
	var gap: PackedFloat32Array = _sine(0.0,  0.04, 0.0)
	var seq: PackedFloat32Array = _concat(_concat(_concat(_concat(hi, gap), lo), gap), hi)
	return _make_wav(seq)

# ── Unit selection voices ─────────────────────────────────────────────────────

func _synth_sel_generic() -> AudioStreamWAV:
	# Neutral mid-pitch blip: two rising tones
	var a: PackedFloat32Array = _sine(440.0, 0.06, 0.28)
	var b: PackedFloat32Array = _sine(550.0, 0.08, 0.25)
	return _make_wav(_concat(a, b))

func _synth_sel_villager() -> AudioStreamWAV:
	# Friendly, bright, short chirp — warm and approachable
	var n: int = int(SAMPLE_RATE * 0.22)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 12.0)
		# Two harmonics for warmth
		buf[i] = (sin(TAU * 520.0 * t) * 0.35 + sin(TAU * 780.0 * t) * 0.18) * env
	return _make_wav(buf)

func _synth_sel_infantry() -> AudioStreamWAV:
	# Gruff short grunt: band-passed noise burst with low punch
	var n: int = int(SAMPLE_RATE * 0.18)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var lp: float = 0.0
	var hp: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var raw: float = randf_range(-1.0, 1.0)
		lp = lp + 0.20 * (raw - lp)
		hp = 0.70 * hp + 0.70 * (lp - hp)
		var env: float = exp(-t * 18.0)
		# Mix band-passed noise with a low thud tone
		buf[i] = (hp * 0.40 + sin(TAU * 140.0 * t) * 0.30) * env
	return _make_wav(buf)

func _synth_sel_archer() -> AudioStreamWAV:
	# Light bow-string pluck: sharp attack, fast decay, mid-high pitch
	var n: int = int(SAMPLE_RATE * 0.20)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 22.0)
		# Fundamental + slight inharmonic partial for a pluck timbre
		buf[i] = (sin(TAU * 680.0 * t) * 0.38 + sin(TAU * 1020.0 * t * 1.005) * 0.18) * env
	return _make_wav(buf)

func _synth_sel_cavalry() -> AudioStreamWAV:
	# Confident, bold — rising sweep with a snort-like noise burst
	var sweep: PackedFloat32Array = _sweep(300.0, 520.0, 0.14, 0.38)
	var snort: PackedFloat32Array = _noise(0.08, 0.18)
	var gap: PackedFloat32Array = PackedFloat32Array()
	gap.resize(int(SAMPLE_RATE * 0.02))
	gap.fill(0.0)
	return _make_wav(_concat(_concat(sweep, gap), snort))

func _synth_sel_siege() -> AudioStreamWAV:
	# Heavy, mechanical clunk: low noise burst + iron resonance
	var n: int = int(SAMPLE_RATE * 0.28)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var lp: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var raw: float = randf_range(-1.0, 1.0)
		lp = lp + 0.05 * (raw - lp)
		var env: float = exp(-t * 10.0)
		buf[i] = (lp * 0.45 + sin(TAU * 95.0 * t) * 0.25) * env
	return _make_wav(buf)

func _synth_sel_naval() -> AudioStreamWAV:
	# Bell-like water tone: two partials, slow decay, slight chorus
	var n: int = int(SAMPLE_RATE * 0.32)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 7.0)
		buf[i] = (sin(TAU * 380.0 * t) * 0.35 + sin(TAU * 570.0 * t * 1.003) * 0.22) * env
	return _make_wav(buf)

func _synth_sel_hero() -> AudioStreamWAV:
	# Celestial shimmer: high choir-like harmonics with slow attack and long tail
	var n: int = int(SAMPLE_RATE * 0.70)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		# Soft bell-curve envelope: slow rise, long decay
		var attack: float = 1.0 - exp(-t * 18.0)
		var decay: float = exp(-t * 3.5)
		var env: float = attack * decay
		# Five harmonic partials tuned to an open fifth + octave — airy and pure
		buf[i] = (sin(TAU * 528.0 * t) * 0.30          # fundamental
				+ sin(TAU * 792.0 * t) * 0.20          # fifth above
				+ sin(TAU * 1056.0 * t) * 0.15         # octave
				+ sin(TAU * 1320.0 * t) * 0.10         # fifth + octave
				+ sin(TAU * 1584.0 * t) * 0.06         # double octave
				# Subtle slow vibrato on the top partial for shimmer
				+ sin(TAU * 1058.0 * t + sin(TAU * 5.5 * t) * 0.4) * 0.08) * env
	return _make_wav(buf)

# ---------------------------------------------------------------------------
# Weather ambient synthesizers (looping ~4 s textures)
# ---------------------------------------------------------------------------

func _synth_weather_calima() -> AudioStreamWAV:
	# Dry, dusty hiss: filtered white noise with slow amplitude wobble
	var n: int = int(SAMPLE_RATE * 4.0)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var lp: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var raw: float = randf_range(-1.0, 1.0)
		lp = lp + 0.03 * (raw - lp)   # simple one-pole low-pass (~660 Hz)
		var wobble: float = 0.75 + 0.25 * sin(TAU * 0.18 * t)
		buf[i] = lp * 0.50 * wobble
	return _make_wav(buf)

func _synth_weather_storm() -> AudioStreamWAV:
	# Rain: dense high-frequency noise + low rumble + occasional thunder crack
	var n: int = int(SAMPLE_RATE * 4.0)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var hp: float = 0.0
	var rumble: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var raw: float = randf_range(-1.0, 1.0)
		# High-pass for rain hiss
		hp = 0.85 * hp + 0.85 * (raw - hp)
		# Low-frequency rumble via sine wobble on noise
		rumble = 0.98 * rumble + 0.02 * raw
		var thunder_env: float = 0.0
		# Single thunder crack at t≈1.4 s
		var td: float = absf(t - 1.4)
		if td < 0.18:
			thunder_env = (1.0 - td / 0.18) * 0.5
		buf[i] = clampf(hp * 0.45 + rumble * 0.25 + raw * thunder_env, -1.0, 1.0)
	return _make_wav(buf)

func _synth_weather_fog() -> AudioStreamWAV:
	# Eerie coastal fog: slow low sine drone + soft filtered noise breath
	var n: int = int(SAMPLE_RATE * 4.0)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var lp: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var drone: float = sin(TAU * 55.0 * t) * 0.18
		var raw: float = randf_range(-1.0, 1.0)
		lp = lp + 0.015 * (raw - lp)
		var breath: float = 0.5 + 0.5 * sin(TAU * 0.12 * t)
		buf[i] = clampf(drone + lp * 0.25 * breath, -1.0, 1.0)
	return _make_wav(buf)

func _synth_weather_wind() -> AudioStreamWAV:
	# Trade winds: whooshing bandpass noise with rising/falling gusts
	var n: int = int(SAMPLE_RATE * 4.0)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var lp: float = 0.0
	var hp: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var raw: float = randf_range(-1.0, 1.0)
		# Band-pass: high-pass then low-pass
		hp = 0.92 * hp + 0.92 * (raw - hp)
		lp = lp + 0.08 * (hp - lp)
		# Gust envelope: two gusts in 4 s
		var gust: float = 0.55 + 0.45 * sin(TAU * 0.40 * t + 0.5)
		buf[i] = lp * 0.60 * gust
	return _make_wav(buf)

func _synth_weather_ash() -> AudioStreamWAV:
	# Volcanic ash: deep subterranean rumble + fine grit hiss
	var n: int = int(SAMPLE_RATE * 4.0)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var lp_deep: float = 0.0
	var lp_grit: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var raw: float = randf_range(-1.0, 1.0)
		lp_deep = lp_deep + 0.006 * (raw - lp_deep)  # very low rumble ~130 Hz
		lp_grit = lp_grit + 0.06  * (raw - lp_grit)  # mid hiss ~1.3 kHz
		var pulse: float = 0.65 + 0.35 * sin(TAU * 0.25 * t)
		buf[i] = clampf(lp_deep * 0.60 * pulse + lp_grit * 0.25, -1.0, 1.0)
	return _make_wav(buf)

# ---------------------------------------------------------------------------
# Background music
# ---------------------------------------------------------------------------

func _build_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -22.0
	_music_player.bus = "Master"
	add_child(_music_player)
	_music_player.stream = _build_music_for_map(0)

func _build_music_for_map(map_type: int) -> AudioStreamWAV:
	match map_type:
		1: return _music_standard()       # Standard   — G Major, epic
		2: return _music_volcanic()       # Volcanic   — E Phrygian, dark/tense
		3: return _music_desert()         # Desert     — A Arabic minor, exotic
		4: return _music_islands()        # Islands    — D Major pentatonic, bright/marine
		_: return _music_plains()         # Plains (0) — D Dorian, calm/medieval

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

# Plains — D Dorian pentatonic, slow and meditative
func _music_plains() -> AudioStreamWAV:
	const D3: float = 146.83; const E3: float = 164.81; const F3: float = 174.61
	const A3: float = 220.00; const C4: float = 261.63; const D4: float = 293.66
	const A2: float = 110.00; const D2: float = 73.41
	const B: float = 0.55
	var melody: Array = [
		[D3,1.0],[E3,1.0],[F3,1.0],[A3,2.0],[C4,1.0],[A3,1.0],[F3,1.5],[E3,0.5],
		[D3,2.0],[E3,1.0],[A3,1.0],[C4,1.0],[D4,2.0],[C4,1.0],[A3,1.0],[F3,1.0],
		[E3,1.5],[D3,0.5],[F3,1.0],[A3,2.0],[C4,1.0],[D4,1.5],[C4,0.5],[A3,2.0],
		[F3,1.0],[E3,1.0],[D3,4.0],
	]
	var drone: Array = [
		[D2,4.0],[A2,4.0],[D2,4.0],[A2,4.0],[D2,4.0],[A2,4.0],[D2,8.0],
	]
	return _build_melody_wav(melody, drone, B, 0.28, 0.12)

# Standard — G Major, brighter and more epic
func _music_standard() -> AudioStreamWAV:
	const G3: float = 196.00; const A3: float = 220.00; const B3: float = 246.94
	const D4: float = 293.66; const E4: float = 329.63; const G4: float = 392.00
	const G2: float = 98.00;  const D3: float = 146.83
	const B: float = 0.48
	var melody: Array = [
		[G3,1.0],[A3,1.0],[B3,1.0],[D4,2.0],[E4,1.0],[D4,1.0],[B3,1.5],[A3,0.5],
		[G3,2.0],[B3,1.0],[D4,1.0],[G4,2.0],[E4,1.0],[D4,1.0],[B3,1.0],[A3,1.0],
		[G3,1.0],[A3,1.0],[B3,2.0],[D4,1.0],[E4,1.5],[D4,0.5],[B3,2.0],
		[A3,1.0],[G3,1.0],[B3,1.0],[D4,4.0],
	]
	var drone: Array = [
		[G2,4.0],[D3,4.0],[G2,4.0],[D3,4.0],[G2,4.0],[D3,4.0],[G2,8.0],
	]
	return _build_melody_wav(melody, drone, B, 0.30, 0.10)

# Volcanic Coast — E Phrygian, dark and tense
func _music_volcanic() -> AudioStreamWAV:
	const E3: float = 164.81; const F3: float = 174.61; const G3: float = 196.00
	const A3: float = 220.00; const B3: float = 246.94; const C4: float = 261.63
	const E2: float = 82.41;  const B2: float = 123.47
	const B: float = 0.62
	var melody: Array = [
		[E3,1.0],[F3,1.0],[G3,1.5],[F3,0.5],[E3,2.0],[A3,1.0],[G3,1.0],[F3,1.0],
		[E3,2.0],[B3,1.0],[A3,1.0],[G3,1.0],[F3,1.5],[E3,0.5],[C4,1.0],[B3,1.0],
		[A3,2.0],[G3,1.0],[F3,1.0],[E3,4.0],[F3,1.0],[G3,1.0],[A3,2.0],
		[G3,1.5],[F3,0.5],[E3,4.0],
	]
	var drone: Array = [
		[E2,4.0],[B2,4.0],[E2,4.0],[B2,4.0],[E2,4.0],[B2,4.0],[E2,8.0],
	]
	return _build_melody_wav(melody, drone, B, 0.25, 0.14)

# Desert Coast — A Arabic minor (Hijaz), exotic and dry
func _music_desert() -> AudioStreamWAV:
	const A3: float = 220.00; const Bb3: float = 233.08; const Cs4: float = 277.18
	const D4: float = 293.66; const E4: float = 329.63; const F4: float = 349.23
	const A2: float = 110.00; const E3: float = 164.81
	const B: float = 0.50
	var melody: Array = [
		[A3,1.0],[Bb3,0.5],[Cs4,0.5],[D4,1.5],[Cs4,0.5],[Bb3,1.0],[A3,2.0],
		[E4,1.0],[D4,1.0],[Cs4,1.0],[Bb3,1.0],[A3,2.0],[D4,1.0],[Cs4,1.5],[Bb3,0.5],
		[A3,1.0],[Bb3,1.0],[Cs4,1.0],[D4,2.0],[E4,1.0],[F4,1.0],[E4,1.0],[D4,1.0],
		[Cs4,1.0],[Bb3,1.0],[A3,4.0],
	]
	var drone: Array = [
		[A2,4.0],[E3,4.0],[A2,4.0],[E3,4.0],[A2,4.0],[E3,4.0],[A2,8.0],
	]
	return _build_melody_wav(melody, drone, B, 0.27, 0.13)

# Islands — D Major pentatonic, bright and marine
func _music_islands() -> AudioStreamWAV:
	const D4: float = 293.66; const E4: float = 329.63; const Fs4: float = 369.99
	const A4: float = 440.00; const B4: float = 493.88; const D5: float = 587.33
	const D3: float = 146.83; const A3: float = 220.00
	const B: float = 0.42
	var melody: Array = [
		[D4,1.0],[E4,1.0],[Fs4,1.0],[A4,2.0],[B4,1.0],[A4,1.0],[Fs4,1.5],[E4,0.5],
		[D4,2.0],[Fs4,1.0],[A4,1.0],[D5,2.0],[B4,1.0],[A4,1.0],[Fs4,1.0],[E4,1.0],
		[D4,1.0],[E4,1.0],[Fs4,2.0],[A4,1.0],[B4,1.5],[A4,0.5],[Fs4,2.0],
		[E4,1.0],[D4,1.0],[Fs4,1.0],[A4,4.0],
	]
	var drone: Array = [
		[D3,4.0],[A3,4.0],[D3,4.0],[A3,4.0],[D3,4.0],[A3,4.0],[D3,8.0],
	]
	return _build_melody_wav(melody, drone, B, 0.26, 0.11)

func _build_melody_wav(melody: Array, drone: Array, beat: float, mel_amp: float, drone_amp: float) -> AudioStreamWAV:
	var mel_buf: PackedFloat32Array = PackedFloat32Array()
	const GAP: float = 0.04
	for entry: Array in melody:
		var freq: float = entry[0] as float
		var dur: float = (entry[1] as float) * beat
		mel_buf = _concat(mel_buf, _sine_note(freq, maxf(dur - GAP, 0.05), mel_amp))
		mel_buf = _concat(mel_buf, _silent(GAP))
	var drone_buf: PackedFloat32Array = PackedFloat32Array()
	for entry: Array in drone:
		drone_buf = _concat(drone_buf, _sine_note((entry[0] as float), (entry[1] as float) * beat, drone_amp))
	if drone_buf.size() < mel_buf.size():
		drone_buf = _concat(drone_buf, _silent(float(mel_buf.size() - drone_buf.size()) / float(SAMPLE_RATE)))
	var mixed: PackedFloat32Array = _mix(mel_buf, drone_buf)
	var wav: AudioStreamWAV = _make_wav(mixed)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = mixed.size()
	return wav
