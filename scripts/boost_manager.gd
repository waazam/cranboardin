extends Node3D
## Neon boost pads laid flat on the road: cyan ">>>" chevrons that pulse
## and fling the player forward for a moment when ridden over (airborne
## players sail past them). One-shot per pass; placement is seeded per
## level like every other spawner.

signal boosted()

const PAD_S_RANGE := 1.6
const PAD_LATERAL_RANGE := 1.4
const PAD_MAX_HEIGHT := 0.35

@export var base_count: int = 7
@export var count_per_level: int = 2

var _track: Node3D
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _pads: Array[Dictionary] = []
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _time: float = 0.0


func _ready() -> void:
	# Unshaded so the chevrons glow through the dusk, like the lane dashes.
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.3, 0.95, 0.95)
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


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


## Three ">>>" chevrons pointing downhill.
func _add_chevrons(st: SurfaceTool, s: float, lat: float) -> void:
	for k in 3:
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
	# Slow cyan pulse so pads read as interactive.
	_mat.albedo_color = Color(0.3, 0.95, 0.95).lerp(Color(0.75, 1.0, 1.0),
			0.5 + 0.5 * sin(_time * 4.0))

	if _player.run_state != _player.RunState.RUNNING:
		return
	for pad in _pads:
		if pad["used"]:
			continue
		if absf(pad["s"] - _player.s) < PAD_S_RANGE \
				and absf(pad["lat"] - _player.lateral) < PAD_LATERAL_RANGE \
				and _player.height < PAD_MAX_HEIGHT:
			pad["used"] = true
			_player.apply_boost()
			boosted.emit()
