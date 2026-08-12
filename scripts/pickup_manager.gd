extends Node3D
## Cranberry bottle power-ups scattered along the road. Grabbing one
## restores health -- or overheals past max (up to Player.overheal_cap)
## if you're already topped up. Bottles bob, spin, and pulse (glow and a
## gentle swell) so they read as pickups against the muted world.

const PICKUP_S_RANGE := 1.1
const PICKUP_LATERAL_RANGE := 1.0
const PICKUP_MAX_HEIGHT := 1.6  # grabbable even mid-jump

@export var heal_amount: int = 30
@export var base_count: int = 9
@export var count_per_level: int = 2

var _track: Node3D
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _bottles: Array[Dictionary] = []
var _bottle_time: float = 0.0

## Shared bottle resources: every bottle on the road uses the same two
## materials and three meshes, and the pulse in _physics_process animates
## one material property to drive the glow on all of them at once.
var _juice_mat: StandardMaterial3D
var _cap_mat: StandardMaterial3D
var _body_mesh: CylinderMesh
var _neck_mesh: CylinderMesh
var _cap_mesh: CylinderMesh

signal collected(health: int)


func _ready() -> void:
	# Juice: crimson with a strong emissive core so the bottle blooms and
	# reads at speed against the muted road.
	_juice_mat = StandardMaterial3D.new()
	_juice_mat.albedo_color = Color(0.62, 0.12, 0.22)
	_juice_mat.roughness = 0.25
	_juice_mat.emission_enabled = true
	_juice_mat.emission = Color(0.9, 0.12, 0.28)
	_juice_mat.emission_energy_multiplier = 1.6

	# Cap: polished gold, catching the dusk sun.
	_cap_mat = StandardMaterial3D.new()
	_cap_mat.albedo_color = Color(0.78, 0.65, 0.35)
	_cap_mat.metallic = 0.9
	_cap_mat.roughness = 0.25

	_body_mesh = CylinderMesh.new()
	_body_mesh.top_radius = 0.14
	_body_mesh.bottom_radius = 0.16
	_body_mesh.height = 0.42

	_neck_mesh = CylinderMesh.new()
	_neck_mesh.top_radius = 0.055
	_neck_mesh.bottom_radius = 0.1
	_neck_mesh.height = 0.14

	_cap_mesh = CylinderMesh.new()
	_cap_mesh.top_radius = 0.06
	_cap_mesh.bottom_radius = 0.06
	_cap_mesh.height = 0.06


func setup(track: Node3D, player: Node3D, level: int) -> void:
	_track = track
	_player = player
	for b in _bottles:
		(b["node"] as Node3D).queue_free()
	_bottles.clear()

	_rng.seed = 9000 + level * 3271
	var count: int = base_count + (level - 1) * count_per_level
	var start_s := 120.0
	var end_s: float = track.arc_length - 60.0
	var spacing := (end_s - start_s) / float(count)
	var half: float = track.road_width * 0.5
	for i in count:
		var s := start_s + spacing * i + _rng.randf_range(0.0, spacing * 0.4)
		var lat := _rng.randf_range(-half + 1.2, half - 1.2)
		var node := _make_bottle()
		add_child(node)
		_bottles.append({"node": node, "s": s, "lat": lat, "phase": _rng.randf() * TAU})


func _physics_process(delta: float) -> void:
	if _track == null or _player == null:
		return
	_bottle_time += delta

	# Heartbeat pulse on the shared juice material: one property write per
	# tick drives the glow of every bottle on the road.
	_juice_mat.emission_energy_multiplier = 1.6 + sin(_bottle_time * 3.2) * 0.7

	var i := _bottles.size() - 1
	while i >= 0:
		var b := _bottles[i]
		var bs: float = b["s"]
		var blat: float = b["lat"]
		var node := b["node"] as Node3D

		var xf: Transform3D = _track.transform_at(bs, blat)
		var bob: float = 0.15 + sin(_bottle_time * 2.4 + b["phase"]) * 0.1
		node.position = xf.origin + xf.basis.y * bob
		node.rotation.y = _bottle_time * 1.8 + b["phase"]
		# Gentle swell on top of the bob (phase-offset per bottle, in step
		# with the glow pulse) so pickups breathe rather than sit static.
		node.scale = Vector3.ONE * (1.0 + sin(_bottle_time * 3.2 + b["phase"]) * 0.06)

		if _player.run_state == _player.RunState.RUNNING \
				and absf(bs - _player.s) < PICKUP_S_RANGE \
				and absf(blat - _player.lateral) < PICKUP_LATERAL_RANGE \
				and _player.height < PICKUP_MAX_HEIGHT:
			_player.heal(heal_amount)
			collected.emit(_player.health)
			node.queue_free()
			_bottles.remove_at(i)
		elif bs < _player.s - 10.0:
			node.queue_free()
			_bottles.remove_at(i)
		i -= 1


## A little cranberry-juice bottle: crimson body, short neck, gold cap.
## Built entirely from the shared meshes/materials created in _ready().
func _make_bottle() -> Node3D:
	var item := Node3D.new()

	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.position = Vector3(0, 0.21, 0)
	body.material_override = _juice_mat
	item.add_child(body)

	var neck := MeshInstance3D.new()
	neck.mesh = _neck_mesh
	neck.position = Vector3(0, 0.49, 0)
	neck.material_override = _juice_mat
	item.add_child(neck)

	var cap := MeshInstance3D.new()
	cap.mesh = _cap_mesh
	cap.position = Vector3(0, 0.59, 0)
	cap.material_override = _cap_mat
	item.add_child(cap)

	return item
