extends Node3D
## Spawns and drives the zombie horde. A spawn plan is laid out along the
## track at level start; zombies only get instantiated once the player is
## within activation range (skinned mannequins are too heavy to keep a
## whole level's worth alive), and are freed once passed.
##
## Zombies live in the same spline space as the player (s, lateral) and
## shamble toward the player's lane -- dodging them is the core game, and
## they can be jumped over (hits only land when the player is low).
##
## Spawn types:
##   SIDE  -- starts just off the road edge and walks in across it.
##   AHEAD -- lurks on the road ahead and closes on the player's lateral.

signal zombie_passed(kind: String)  # "over" = cleared airborne, "near" = grazed

enum SpawnType { SIDE, AHEAD }

const MODEL_SCENE := preload("res://Godot/AnimationLibrary_Godot_Standard.glb")
const ACTIVATION_RANGE := 150.0
const DESPAWN_BEHIND := 14.0
const HIT_S_RANGE := 1.0
const HIT_LATERAL_RANGE := 0.95
const HIT_MAX_HEIGHT := 1.0
const NEAR_MISS_RANGE := 2.4

@export var damage_per_hit: int = 26
@export var base_count: int = 70
@export var count_per_level: int = 22

var _track: Node3D
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _spawns: Array[Dictionary] = []
var _next_spawn: int = 0
var _active: Array[Dictionary] = []
var _zombie_material: StandardMaterial3D


func _ready() -> void:
	_zombie_material = StandardMaterial3D.new()
	_zombie_material.albedo_color = Color(0.45, 0.56, 0.36)
	_zombie_material.roughness = 1.0


func setup(track: Node3D, player: Node3D, level: int) -> void:
	_track = track
	_player = player
	for z in _active:
		(z["node"] as Node3D).queue_free()
	_active.clear()
	_next_spawn = 0

	_rng.seed = 5000 + level * 4409
	_spawns.clear()
	var count: int = base_count + (level - 1) * count_per_level
	var start_s := 90.0
	var end_s: float = track.arc_length - 40.0
	var spacing := (end_s - start_s) / float(count)
	var half: float = track.road_width * 0.5
	for i in count:
		var spawn_s := start_s + spacing * i + _rng.randf_range(0.0, spacing * 0.5)
		var type := SpawnType.SIDE if _rng.randf() < 0.55 else SpawnType.AHEAD
		var lat: float
		if type == SpawnType.SIDE:
			lat = (half + 1.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
		else:
			lat = _rng.randf_range(-half + 1.5, half - 1.5)
		_spawns.append({
			"s": spawn_s,
			"lat": lat,
			"type": type,
			"shamble": _rng.randf_range(1.6, 2.3) + (level - 1) * 0.1,
		})


func _physics_process(delta: float) -> void:
	if _track == null or _player == null:
		return

	# Activate spawns entering range.
	while _next_spawn < _spawns.size() and _spawns[_next_spawn]["s"] < _player.s + ACTIVATION_RANGE:
		_activate(_spawns[_next_spawn])
		_next_spawn += 1

	var player_running: bool = _player.run_state == _player.RunState.RUNNING
	var half: float = _track.road_width * 0.5
	var i := _active.size() - 1
	while i >= 0:
		var z := _active[i]
		var zs: float = z["s"]
		var zlat: float = z["lat"]

		# Shamble toward the player's lane; drift slightly up-road too.
		var shamble: float = z["shamble"]
		zlat = move_toward(zlat, clampf(_player.lateral, -half + 0.4, half - 0.4), shamble * delta)
		if player_running and zs > _player.s:
			zs = maxf(zs - 1.2 * delta, _player.s)
		z["s"] = zs
		z["lat"] = zlat

		var xf: Transform3D = _track.transform_at(zs, zlat)
		var node := z["node"] as Node3D
		node.position = xf.origin
		# Face the player (horizontal yaw only; glTF models face +Z).
		var to_player: Vector3 = _player.global_position - xf.origin
		node.rotation.y = atan2(to_player.x, to_player.z)

		# Contact damage -- unless the player is airborne over them.
		if player_running \
				and absf(zs - _player.s) < HIT_S_RANGE \
				and absf(zlat - _player.lateral) < HIT_LATERAL_RANGE \
				and _player.height < HIT_MAX_HEIGHT:
			z["scored"] = true  # no style points off the zombie that got you
			_player.take_damage(damage_per_hit)

		# Style scoring, once per zombie, as the player clears it: jumped
		# clean over it, or squeaked past within near-miss range.
		if not z["scored"] and zs < _player.s - 0.6:
			z["scored"] = true
			if player_running:
				var lat_gap := absf(zlat - _player.lateral)
				if lat_gap < HIT_LATERAL_RANGE and _player.height >= HIT_MAX_HEIGHT:
					zombie_passed.emit("over")
				elif lat_gap < NEAR_MISS_RANGE:
					zombie_passed.emit("near")

		# Free zombies the player has passed.
		if zs < _player.s - DESPAWN_BEHIND:
			node.queue_free()
			_active.remove_at(i)
		i -= 1


func _activate(spawn: Dictionary) -> void:
	var node := Node3D.new()
	add_child(node)

	var model := MODEL_SCENE.instantiate() as Node3D
	model.scale = Vector3.ONE * 0.95
	node.add_child(model)

	# Sickly green tint over every mesh in the rig.
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		(mesh_instance as MeshInstance3D).material_override = _zombie_material

	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		anim.play(&"Walk")
		anim.speed_scale = _rng.randf_range(0.95, 1.25)

	_active.append({
		"node": node,
		"s": spawn["s"],
		"lat": spawn["lat"],
		"shamble": spawn["shamble"],
		"scored": false,
	})
