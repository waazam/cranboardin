extends SceneTree
## Offline audio generator: synthesizes every sound in the game into
## res://audio/*.wav (22050 Hz mono 16-bit). Run from the project root:
##
##   godot --headless --path . -s res://tools/gen_audio.gd
##
## Outputs:
##   music_loop.wav  -- retro synthwave loop: Am-F-C-G, saw bass on 8ths,
##                      detuned saw pads, square arp, kick/snare/hat
##   wind_loop.wav   -- filtered noise bed (pitch/volume scaled in-game)
##   city_loop.wav   -- low rumble + sparse distant horn tones
##   sfx_hit.wav     -- noise burst + low thump
##   sfx_jump.wav    -- short rising whoosh
##   sfx_finish.wav  -- little victory arp
##
## Everything is procedural, so the project stays free of third-party
## audio licensing.

const SR := 22050

var _noise_state: int = 12345


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://audio")
	_save("res://audio/music_loop.wav", _gen_music())
	_save("res://audio/wind_loop.wav", _gen_wind())
	_save("res://audio/city_loop.wav", _gen_city())
	_save("res://audio/sfx_hit.wav", _gen_hit())
	_save("res://audio/sfx_jump.wav", _gen_jump())
	_save("res://audio/sfx_finish.wav", _gen_finish())
	_save("res://audio/sfx_pickup.wav", _gen_pickup())
	print("gen_audio: done")
	quit(0)


func _save(path: String, samples: PackedFloat32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v: int = int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = bytes
	var err := wav.save_to_wav(path)
	print("gen_audio: %s (%d samples, err=%d)" % [path, samples.size(), err])


func _noise() -> float:
	# Tiny deterministic LCG noise, [-1, 1].
	_noise_state = (_noise_state * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_noise_state) / float(0x3FFFFFFF) - 1.0


# --- Music ------------------------------------------------------------------

func _gen_music() -> PackedFloat32Array:
	var bpm := 112.0
	var spb: int = int(SR * 60.0 / bpm)      # samples per beat
	var total: int = spb * 32                # 8 bars of 4/4
	var out := PackedFloat32Array()
	out.resize(total)

	# Chord progression: Am / F / C / G, two bars each... 8 beats each.
	var bass_roots: Array[float] = [55.0, 43.65, 65.41, 49.0]         # A1 F1 C2 G1
	var chords: Array = [
		[110.0, 130.81, 164.81],   # Am: A2 C3 E3
		[87.31, 110.0, 130.81],    # F:  F2 A2 C3
		[130.81, 164.81, 196.0],   # C:  C3 E3 G3
		[98.0, 123.47, 146.83],    # G:  G2 B2 D3
	]

	var pad_lp := 0.0
	var pad_lp_k := 0.12

	for i in total:
		var t := float(i) / SR
		var beat := float(i) / spb
		var chord_idx: int = int(beat / 8.0) % 4
		var chord: Array = chords[chord_idx]
		var root: float = bass_roots[chord_idx]

		# Bass: gated saw on 8th notes with per-note decay.
		var eighth_pos := fmod(beat * 2.0, 1.0)
		var bass_env := exp(-4.0 * eighth_pos)
		var bass := (2.0 * fmod(root * t, 1.0) - 1.0) * bass_env * 0.32

		# Pad: two detuned saws per chord tone, lowpassed.
		var pad := 0.0
		for f in chord:
			var fr: float = f
			pad += (2.0 * fmod(fr * 0.998 * t, 1.0) - 1.0)
			pad += (2.0 * fmod(fr * 1.002 * t, 1.0) - 1.0)
		pad_lp += pad_lp_k * (pad / 6.0 - pad_lp)
		var pad_out := pad_lp * 0.22

		# Arp: square-wave 16ths cycling chord tones an octave up.
		var sixteenth: int = int(beat * 4.0)
		var arp_freq: float = chord[sixteenth % 3] * 2.0
		var arp_pos := fmod(beat * 4.0, 1.0)
		var arp_env := exp(-6.0 * arp_pos)
		var arp := (1.0 if fmod(arp_freq * t, 1.0) < 0.5 else -1.0) * arp_env * 0.10

		# Drums.
		var beat_pos := fmod(beat, 1.0)
		var tb := beat_pos * 60.0 / bpm
		var kick := sin(TAU * tb * (50.0 + 60.0 * exp(-tb * 25.0))) * exp(-9.0 * tb) * 0.5
		var snare := 0.0
		var beat_in_bar: int = int(beat) % 4
		if beat_in_bar == 1 or beat_in_bar == 3:
			snare = _noise() * exp(-14.0 * tb) * 0.28
		var hat_pos := fmod(beat * 2.0, 1.0) * 60.0 / bpm
		var hat := _noise() * exp(-70.0 * hat_pos) * 0.12

		var v := bass + pad_out + arp + kick + snare + hat
		# Gentle edge fades mask the loop seam (kick on beat 1 covers it).
		var fade := 1.0
		var edge: int = int(SR * 0.04)
		if i < edge:
			fade = float(i) / edge
		elif i > total - edge:
			fade = float(total - i) / edge
		out[i] = tanh(v * 1.2) * 0.85 * fade

	return out


# --- Loops ------------------------------------------------------------------

func _gen_wind() -> PackedFloat32Array:
	var total: int = SR * 4
	var out := PackedFloat32Array()
	out.resize(total)
	var brown := 0.0
	for i in total:
		brown = clampf(brown + _noise() * 0.06, -1.0, 1.0)
		brown *= 0.997
		out[i] = brown * 0.7 + _noise() * 0.05
	return _bake_loop_crossfade(out, int(SR * 0.3))


func _gen_city() -> PackedFloat32Array:
	var total: int = SR * 8
	var out := PackedFloat32Array()
	out.resize(total)
	var rumble := 0.0
	for i in total:
		rumble = clampf(rumble + _noise() * 0.02, -1.0, 1.0)
		rumble *= 0.999
		out[i] = rumble * 0.6
	# A few soft distant "horn" tones at fixed spots in the loop.
	var horn_times: Array[float] = [1.2, 3.9, 6.1]
	var horn_freqs: Array[float] = [196.0, 233.08, 174.61]
	for h in horn_times.size():
		var start: int = int(horn_times[h] * SR)
		var dur: int = int(SR * 0.5)
		for j in dur:
			var idx: int = start + j
			if idx >= total:
				break
			var tt := float(j) / SR
			var env := sin(PI * float(j) / dur)
			out[idx] += sin(TAU * horn_freqs[h] * tt) * env * 0.05
	return _bake_loop_crossfade(out, int(SR * 0.4))


## Crossfades the tail into the head so the loop point is seamless.
func _bake_loop_crossfade(samples: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := samples.size() - fade
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = samples[i]
	for i in fade:
		var mix := float(i) / fade
		out[i] = samples[n + i] * (1.0 - mix) + samples[i] * mix
	return out


# --- One-shots --------------------------------------------------------------

func _gen_hit() -> PackedFloat32Array:
	var total: int = int(SR * 0.35)
	var out := PackedFloat32Array()
	out.resize(total)
	for i in total:
		var t := float(i) / SR
		var thump := sin(TAU * t * (70.0 + 50.0 * exp(-t * 30.0))) * exp(-12.0 * t) * 0.7
		var crunch := _noise() * exp(-18.0 * t) * 0.5
		out[i] = tanh(thump + crunch)
	return out


func _gen_jump() -> PackedFloat32Array:
	var total: int = int(SR * 0.25)
	var out := PackedFloat32Array()
	out.resize(total)
	var lp := 0.0
	for i in total:
		var t := float(i) / SR
		var k := 0.05 + t * 1.6  # opening filter = rising whoosh
		lp += clampf(k, 0.0, 0.9) * (_noise() - lp)
		var env := sin(PI * float(i) / total)
		out[i] = lp * env * 0.5
	return out


func _gen_pickup() -> PackedFloat32Array:
	# Bright rising two-note blip for the cranberry bottle.
	var total: int = int(SR * 0.3)
	var out := PackedFloat32Array()
	out.resize(total)
	var half: int = total / 2
	for i in total:
		var t := float(i) / SR
		var f := 659.26 if i < half else 880.0  # E5 -> A5
		var local_t := t if i < half else t - float(half) / SR
		var env := exp(-9.0 * local_t)
		out[i] = (sin(TAU * f * t) * 0.7 + sin(TAU * f * 2.0 * t) * 0.2) * env * 0.5
	return out


func _gen_finish() -> PackedFloat32Array:
	var notes: Array[float] = [220.0, 261.63, 329.63, 440.0]  # A3 C4 E4 A4
	var note_len: int = int(SR * 0.16)
	var total: int = note_len * notes.size() + int(SR * 0.3)
	var out := PackedFloat32Array()
	out.resize(total)
	for n in notes.size():
		var f: float = notes[n]
		for j in note_len * 3:
			var idx: int = n * note_len + j
			if idx >= total:
				break
			var t := float(j) / SR
			var env := exp(-6.0 * t)
			var sq := 1.0 if fmod(f * t, 1.0) < 0.5 else -1.0
			out[idx] += sq * env * 0.16
	return out
