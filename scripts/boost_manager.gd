extends Node3D
## Neon boost pads laid flat on the road: cyan ">>>" chevrons that pulse
## and surge the player forward for a good couple of seconds when ridden
## over (airborne players sail past them). Pads are plentiful and their
## pickup window is deliberately generous -- grazing one at speed should
## count, so runs chain surge to surge instead of punishing near-misses.
## One-shot per pass; placement is seeded per level like every other
## spawner.

signal boosted()

const PAD_S_RANGE := 2.0
const PAD_LATERAL_RANGE := 1.7
const PAD_MAX_HEIGHT := 0.35

## One shared unshaded shader for every chevron: each chevron bakes its 0..1
## position down the pad into its vertex COLOR.r, and a single time uniform
## sweeps a sine wave through those phases so light appears to run downhill
## across the ">>>" -- no per-instance materials, one uniform set per frame.
## Wave crests push the albedo well past 1.0 so the pads bloom.
const CHEVRON_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float pulse_time = 0.0;
uniform vec3 base_color : source_color = vec3(0.3, 0.95, 0.95);
uniform vec3 hot_color : source_color = vec3(0.85, 1.0, 1.0);
void fragment() {
	float wave = 0.5 + 0.5 * sin(COLOR.r * TAU - pulse_time);
	ALBEDO = mix(base_color, hot_color, wave) * (1.2 + 1.6 * wave);
}
"""

@export var base_count: int = 11
@export var count_per_level: int = 3

var _track: Node3D
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _pads: Array[Dictionary] = []
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _time: float = 0.0


func _ready() -> void:
	# Unshaded so the chevrons glow through the dusk, like the lane dashes;
	# the sweep animation lives in CHEVRON_SHADER above.
	var shader := Shader.new()
	shader.code = CHEVRON_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader


func setup(track: Node3D, player: Node3D, level: int) -> void:
	_track = track
	_player = player
	if _mesh:
		_mesh.queue_free()
	_pads.clear()

	_rng.seed = 7000 + level * 6011
	var count: int = base_count + (level - 1) * count_per_level
	var start_s := 60.0
	var end_s: float = track.arc_length - 60.0
	var spacing := (end_s - start_s) / float(count)
	var half: float = track.road_width * 0.5

	# All pads share one mesh, built in world space so they hug the curve.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var s := start_s + spacing * i + _rng.randf_range(0.0, spacing * 0.4)
		var lat := _rng.randf_range(-half + 1.6, half - 1.6)
		_pads.append({"s": s, "lat": lat, "used": false})
		_add_chevrons(st, s, lat)

	_mesh = MeshInstance3D.new()
	_mesh.mesh = st.commit()
	_mesh.material_override = _mat
	add_child(_mesh)


## Three ">>>" chevrons pointing downhill. COLOR.r carries each chevron's
## phase down the pad (0, 1/3, 2/3) for the shader's traveling wave.
func _add_chevrons(st: SurfaceTool, s: float, lat: float) -> void:
	for k in 3:
		st.set_color(Color(k / 3.0, 0.0, 0.0))
		var s0 := s - 1.6 + k * 1.1
		for side in [-1.0, 1.0]:
			_add_quad(st,
					_pt(s0, lat + side * 1.1),
					_pt(s0 + 0.4, lat + side * 1.1),
					_pt(s0 + 1.3, lat),
					_pt(s0 + 0.9, lat))


func _pt(s: float, lat: float) -> Vector3:
	var xf: Transform3D = _track.transform_at(s, lat)
	return xf.origin + xf.basis.y * 0.06


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


func _physics_process(delta: float) -> void:
	if _track == null or _player == null:
		return
	_time += delta
	# Slow sweep so pads read as interactive: one uniform update drives the
	# wave across every chevron of every pad. Wrapped to the wave's period so
	# the 32-bit uniform never grows large enough to cost sin() precision on
	# a long session.
	_mat.set_shader_parameter("pulse_time", fmod(_time * 3.0, TAU))

	if _player.run_state != _player.RunState.RUNNING:
		return
	for pad in _pads:
		if pad["used"]:
			continue
		if absf(pad["s"] - _player.s) < PAD_S_RANGE \
				and absf(pad["lat"] - _player.lateral) < PAD_LATERAL_RANGE \
				and _player.height < PAD_MAX_HEIGHT:
			pad["used"] = true
			# Longer than the player's 1.8s default: pads are the run's rhythm
			# now, so each hit should feel like a real surge, not a blip.
			_player.apply_boost(2.4)
			boosted.emit()
