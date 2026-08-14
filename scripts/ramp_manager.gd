extends Node3D
## Neon pink launch ramps: tilted wedges on the road that fling a grounded
## player into a big assisted air (with the usual alternating trick).
## Same spline-space contact pattern as the boost pads; one-shot per pass.

signal ramped()

const RAMP_S_RANGE := 1.5
const RAMP_LATERAL_RANGE := 1.6
const RAMP_MAX_HEIGHT := 0.3
const LAUNCH_VELOCITY := 13.0

@export var base_count: int = 7
@export var count_per_level: int = 2

var _track: Node3D
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _ramps: Array[Dictionary] = []
var _container: Node3D
var _mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D
var _lip_mesh: BoxMesh
var _rail_mesh: BoxMesh


func _ready() -> void:
	# Neon pink deck, same family as the center-line dashes -- but shaded
	# now, with a metallic sheen so the low dusk sun glints off the kicker
	# face, and self-lit through emission so it never goes muddy in shadow.
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1.0, 0.35, 0.65)
	_mat.metallic = 0.6
	_mat.roughness = 0.35
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.35, 0.65)
	_mat.emission_energy_multiplier = 0.55
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Edge strips: unshaded HDR white-pink, so every ramp's outline burns
	# bright enough to bloom and reads clearly at speed. One material and
	# two BoxMeshes shared by every strip on every ramp.
	_edge_mat = StandardMaterial3D.new()
	_edge_mat.albedo_color = Color(2.0, 1.1, 1.6)
	_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lip_mesh = BoxMesh.new()
	_lip_mesh.size = Vector3(2.8, 0.16, 0.08)
	_rail_mesh = BoxMesh.new()
	# A hair longer than the 3.0 deck so the rail's end caps sit proud of the
	# deck's front/back faces instead of coplanar with them (which z-fights).
	_rail_mesh.size = Vector3(0.08, 0.16, 3.04)


func setup(track: Node3D, player: Node3D, level: int) -> void:
	_track = track
	_player = player
	if _container:
		_container.queue_free()
	_container = Node3D.new()
	add_child(_container)
	_ramps.clear()

	_rng.seed = 8000 + level * 7127
	var count: int = base_count + (level - 1) * count_per_level
	var start_s := 140.0
	var end_s: float = track.arc_length - 80.0
	var spacing := (end_s - start_s) / float(count)
	var half: float = track.road_width * 0.5
	for i in count:
		var s := start_s + spacing * i + _rng.randf_range(0.0, spacing * 0.5)
		var lat := _rng.randf_range(-half + 2.0, half - 2.0)
		_ramps.append({"s": s, "lat": lat, "used": false})
		_make_wedge(s, lat)


## A thin box tilted so its downhill edge rises off the road: reads as a
## kicker at pixel res without custom geometry.
func _make_wedge(s: float, lat: float) -> void:
	var xf: Transform3D = _track.transform_at(s, lat)
	var wedge := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.8, 0.12, 3.0)
	wedge.mesh = box
	wedge.material_override = _mat
	# Tilt about the road's right axis; -Z is downhill-forward, so this
	# lifts the forward edge into a kicker face.
	wedge.transform = Transform3D(
			xf.basis * Basis(Vector3(1, 0, 0), 0.16),
			xf.origin + xf.basis.y * 0.28)
	_container.add_child(wedge)

	# Thin emissive strips along the lip (the raised downhill edge at -Z)
	# and both side edges, parented to the wedge so they inherit its tilt.
	# Slightly taller than the deck (0.16 vs 0.12), and every strip sits a
	# touch proud of the deck's own faces -- coplanar faces between the two
	# materials would z-fight and shimmer at pixel res.
	var lip := MeshInstance3D.new()
	lip.mesh = _lip_mesh
	lip.material_override = _edge_mat
	lip.position = Vector3(0.0, 0.0, -1.48)  # front face 0.02 past the deck's
	wedge.add_child(lip)
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		rail.mesh = _rail_mesh
		rail.material_override = _edge_mat
		rail.position = Vector3(side * 1.38, 0.0, 0.0)  # outer face 0.02 proud
		wedge.add_child(rail)


func _physics_process(_delta: float) -> void:
	if _track == null or _player == null:
		return
	if _player.run_state != _player.RunState.RUNNING:
		return
	for ramp in _ramps:
		if ramp["used"]:
			continue
		if absf(ramp["s"] - _player.s) < RAMP_S_RANGE \
				and absf(ramp["lat"] - _player.lateral) < RAMP_LATERAL_RANGE \
				and _player.height < RAMP_MAX_HEIGHT:
			ramp["used"] = true
			_player.launch(LAUNCH_VELOCITY)
			ramped.emit()
