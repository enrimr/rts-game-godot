# Procedural Audio Synthesis

Calima ships **zero audio files**. Every sound effect, every unit voice and
every music track is synthesized as raw PCM at runtime by
`project/scripts/core/audio_manager.gd` and stored in memory as
`AudioStreamWAV` resources. This document explains how each layer is
generated, why it is structured the way it is, and how to extend it.

## 1. PCM foundation

All synthesis produces a `PackedFloat32Array` of samples in `[-1, 1]` at
`SAMPLE_RATE = 22050` Hz, mono, converted once by `_make_wav()` into a
16-bit `AudioStreamWAV`. The building blocks (all in `audio_manager.gd`):

| Helper | Produces |
|---|---|
| `_sine(freq, dur, amp)` | pure tone with linear fade-out |
| `_square(freq, dur, amp)` | hollow/buzzy tone |
| `_noise(dur, amp)` | white noise burst |
| `_sweep(f0, f1, dur, amp)` | pitch glide (rise/fall) |
| `_mix(a, b)` / `_concat(a, b)` | layer two buffers / play one after another |

Simple one-pole filters are inlined where a timbre needs shaping
(`lp = lp + k * (raw - lp)` is a low-pass; subtracting it from the input
gives a high-pass; chaining both gives a band-pass). See the weather
ambiences for worked examples.

## 2. Sound effects

Each effect is a tiny recipe over the helpers — e.g. an axe chop is a
noise burst mixed with a 280 Hz thump; a build-complete fanfare is three
concatenated sine notes. Two registration modes:

- `_register(id, stream)` — a polyphony pool of `POOL_SIZE` players sharing
  one stream. `play(id)` round-robins the pool so rapid repeats overlap
  instead of cutting each other.
- `_register_multi(id, [streams])` — the pool's players carry **different
  takes** (the same recipe with a pitch/length factor `k`, e.g.
  `_synth_chop(0.86)` … `_synth_chop(1.15)`), so the round-robin rotates
  variants for free. Used for the repetitive sounds: hits, deaths,
  chopping, mining.

Looping ambiences (weather) use `_register_loop`, which marks the WAV as
`LOOP_FORWARD` over its whole length; the recipes are ~4 s filtered-noise
textures with slow amplitude wobbles.

## 3. Unit voices (formant synthesis)

The voices are AoE2-style gibberish barks, built like a tiny vocal tract:

1. **Glottal source** — a band-limited sawtooth at the fundamental
   frequency F0: the sum of `sin(h·phase)/h` harmonics up to ~8.8 kHz,
   with 2.2 % vibrato at 5.3 Hz plus a slow random pitch jitter. A
   `growl` option amplitude-modulates the source at 74 Hz (throaty
   soldiers); `breath` mixes in white noise.
2. **Formant filters** — the source runs through three parallel two-pole
   resonators (`y = g·x + 2r·cos(ω)·y₁ − r²·y₂`) tuned to the F1/F2/F3
   frequencies of the target vowel (`VOICE_VOWELS`: /a/ 800·1150·2500 Hz,
   /i/ 320·2300·3000 Hz, …). Female voices scale the formants ×1.16 and
   use a higher F0.
3. **Consonant onsets** (`VOICE_CONSONANTS`) — plosives are a beat of
   closure silence plus a resonator-filtered noise burst (t/k/p/d/g/b at
   different center frequencies); fricatives (s/h) are longer shaped
   noise; nasals (m/n) a voiced hum; liquids (r/l) a short schwa glide.
4. **Prosody** — a "word" is 1–3 syllables with a natural pitch
   declination; the last syllable's contour mark decides the melody:
   `?` rises ×1.32 (attentive question — selections), `!` attacks high
   and drops to ×0.74 (bark — infantry, attack orders), no mark falls
   softly (statement — acknowledgments). Heroes add a single 85 ms
   delayed reflection (`echo`) that reads as a stone hall.
5. Every word is peak-normalized to `VOICE_PEAK = 0.42`.

### The cast: kinds × civs × genders

- `VOICE_KINDS` defines the **class prosody**: F0 per gender, syllable
  count range, contour mark and render opts. Selection kinds
  (`select_villager`, `select_infantry`, …) ask; order confirmations
  (`ack_move`, `ack_attack`) affirm. A kind with `f0_f = 0` bakes no
  female bank (ship crews).
- `VOICE_CIV_POOLS` gives each civilization its **syllable pool** — its
  phonetic identity — plus a `default` pool for unowned/unknown speakers.
- `VOICE_CIV_PITCH` is the per-civ **accent**: a multiplier on the class
  F0 (Guanches 0.94 deep … Fenicios 1.06 bright).
- Words are generated **deterministically**: an RNG seeded with
  `"kind|civ|gender".hash()` draws `VOICE_VARIANTS = 3` lines from the
  civ pool. Same seed → the same lines on every machine, every launch.

Playback goes through `play_voice(kind, female, civ_id)`, which resolves
bank `kind_civ_gender` with fallbacks (civ male → default gender →
default male → the plain sound id, so siege keeps its mechanical clunk),
and never repeats the same variant twice in a row. Call sites: unit
selection in `hud_manager.gd` (`get_selection_sound()` + lead unit's
`is_female`/`civ_id`) and order confirmation in `world_commands.gd`
(`_play_order_voice`).

### Bake threading

The full cast is ~460 clips (~7 s of DSP), so:

- Windowed runs bake it in parallel with
  `WorkerThreadPool.add_group_task` — one voice kind per worker, each
  writing its own pre-sized slot of `_baked_by_kind` (no shared-array
  writes). A main-thread poll in `_process` installs the finished banks;
  until then `play_voice` falls back to the generic blip (in practice the
  bake finishes while the player is still in the main menu).
- **Headless runs skip the bake entirely** (dummy audio can't play it and
  the engine waits for worker tasks on exit). Tools and tests that need
  the cast call `ensure_voices_ready()`, which bakes synchronously.

## 4. Music

Each map type owns a looping track built from a melody table
(`[[freq, beats], …]`) over a two-note drone, rendered with `_sine_note`
(ADSR-lite envelope) by `_build_melody_wav`. The five tracks differ in
mode and mood: Plains D Dorian (calm), Standard G Major (epic), Volcanic
E Phrygian (tense), Desert A Hijaz (exotic), Islands D Major pentatonic
(marine).

## 5. Extending it

- **New civ**: add a syllable pool to `VOICE_CIV_POOLS` and an accent to
  `VOICE_CIV_PITCH`. Everything else (all kinds × genders) bakes itself.
- **New voice kind** (e.g. a "repair" ack): add a `VOICE_KINDS` entry and
  call `play_voice("your_kind", female, civ)` from the UI layer.
- **New syllables**: single consonant + single vowel only (`"ka"`, `"o"`),
  consonants limited to the `VOICE_CONSONANTS` table — the parser takes
  the last character as the vowel and looks up the rest as the onset.
- **New sfx take**: give the synth a `k` factor parameter and register
  with `_register_multi`.
- **Tuning voices**: `CALIMA_SHOT_DIR=/tmp/calima-voices godot --headless
  --path project res://tools/check_voice_gallery.tscn` exports listenable
  WAVs (narrow with `CALIMA_CIVS=guanches,fenicios`), checks all clips
  for degeneracy, and `afplay` plays them from the terminal.

## 6. Guardrails

- `tests/unit/test_voice_banks.gd` locks the cast contract: every kind
  bakes per civ and gender, generation is deterministic, accents differ,
  clips are normalized real audio, fallback paths don't crash, and the
  multi-take pools actually carry distinct takes.
- `tools/check_voice_gallery.tscn` is the audition/regression gate for
  the whole cast.
- GDScript note: the DSP runs on worker threads — keep it pure (const
  tables + local state, no nodes, no autoload writes) or the bake will
  race the main thread.
