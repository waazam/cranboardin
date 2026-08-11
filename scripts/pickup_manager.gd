extends Node3D
## Cranberry bottle power-ups scattered along the road. Grabbing one
## restores health -- or overheals past max (up to Player.overheal_cap)
## if you're already topped up. Bottles bob and spin so they read as
## pickups against the muted world.

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

signal collected(health: int)


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
func _make_bottle() -> Node3D:
	var item := Node3D.new()

	var juice_mat := StandardMaterial3D.new()
	juice_mat.albedo_color = Color(0.62, 0.12, 0.22)
	juice_mat.roughness = 0.3
	juice_mat.emission_enabled = true
	juice_mat.emission = Color(0.55, 0.08, 0.18)
	juice_mat.emission_energy_multiplier = 0.6

	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.14
	body_mesh.bottom_radius = 0.16
	body_mesh.height = 0.42
	body.mesh = body_mesh
	body.position = Vector3(0, 0.21, 0)
	body.material_override = juice_mat
	item.add_child(body)

	var neck := MeshInstance3D.new()
	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.055
	neck_mesh.bottom_radius = 0.1
	neck_mesh.height = 0.14
	neck.mesh = neck_mesh
	neck.position = Vector3(0, 0.49, 0)
	neck.material_override = juice_mat
	item.add_child(neck)

	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.06
	cap_mesh.bottom_radius = 0.06
	cap_mesh.height = 0.06
	cap.mesh = cap_mesh
	cap.position = Vector3(0, 0.59, 0)
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.78, 0.65, 0.35)
	cap_mat.roughness = 0.4
	cap.material_override = cap_mat
	item.add_child(cap)

	return item
