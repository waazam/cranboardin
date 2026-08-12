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
signal zombie_smashed()  # bowled through while boosting

enum SpawnType { SIDE, AHEAD }

const MODEL_SCENE := preload("res://Godot/AnimationLibrary_Godot_Standard.glb")
const ACTIVATION_RANGE := 150.0
const DESPAWN_BEHIND := 14.0
const HIT_S_RANGE := 1.0
const HIT_LATERAL_RANGE := 0.95
const HIT_MAX_HEIGHT := 1.0
const NEAR_MISS_RANGE := 2.4

@export var damage_per_hit: int = 34  # three hits without healing ends the run
@export var base_count: int = 78
@export var count_per_level: int = 24

var _track: Node3D
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _spawns: Array[Dictionary] = []
var _next_spawn: int = 0
var _active: Array[Dictionary] = []
## Zombies mid-launch after a boost smash: {node, vel, spin, t}.
var _smashed: Array[Dictionary] = []
## Small shared palettes rather than per-instance materials: however big the
## horde gets, the renderer only ever sees a handful of material states.
var _zombie_materials: Array[StandardMaterial3D] = []
var _runner_materials: Array[StandardMaterial3D] = []
## Eye dots: one tiny shared mesh + one shared material per zombie class.
var _eye_mesh: SphereMesh
var _eye_material: StandardMaterial3D
var _runner_eye_material: StandardMaterial3D


func _ready() -> void:
	# Shamblers: sickly greens with a bruised purple thrown in, so the horde
	# has per-zombie variety while every tint stays a shared material.
	for tint: Color in [
		Color(0.45, 0.56, 0.36),  # classic sickly green
		Color(0.36, 0.5, 0.42),   # colder, mossier green
		Color(0.44, 0.36, 0.5),   # bruised purple
	]:
		_zombie_materials.append(_corpse_material(tint))

	# Runners: rusty reds so they read as danger at a distance.
	for tint: Color in [
		Color(0.62, 0.28, 0.2),   # rust
		Color(0.54, 0.2, 0.28),   # dried-blood maroon
	]:
		_runner_materials.append(_corpse_material(tint))

	# Eyes: a low-poly pinhead sphere, unshaded and hot so it blooms.
	# Shamblers get a sickly ghoul-green stare; runners burn hot orange.
	_eye_mesh = SphereMesh.new()
	_eye_mesh.radius = 0.028
	_eye_mesh.height = 0.056
	_eye_mesh.radial_segments = 6
	_eye_mesh.rings = 3
	_eye_material = _eye_glow(Color(0.65, 1.0, 0.4))
	_runner_eye_material = _eye_glow(Color(1.0, 0.4, 0.14))


## Dead-flesh material with a dusk backlight baked in: a touch of rim so the
## silhouette catches the pink sky from behind, slightly-below-full roughness
## so the sun still models the body, and a whisper of self-emission so the
## horde never goes pitch black between the street lamps.
func _corpse_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.9
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.rim_tint = 0.5
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.12
	return mat


## Hot emissive dot for the eyes. Deliberately shaded, not unshaded --
## Godot discards EMISSION on unshaded materials, and it's the 3.0-energy
## emission that makes the dots burn bright enough to catch the glow pass.
func _eye_glow(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	return mat


func setup(track: Node3D, player: Node3D, level: int) -> void:
	_track = track
	_player = player
	for z in _active:
		(z["node"] as Node3D).queue_free()
	_active.clear()
	for sm in _smashed:
		(sm["node"] as Node3D).queue_free()
	_smashed.clear()
	_next_spawn = 0

	# Placement is fully random over the run (sorted afterwards for the
	# activation cursor): clumps and dead stretches emerge naturally, and
	# ~30% of rolls drop a tight pack of 2-4 -- a mini-horde to jump,
	# thread, or bowl through on a boost.
	_rng.seed = 5000 + level * 4409
	_spawns.clear()
	var count: int = base_count + (level - 1) * count_per_level
	var start_s := 70.0
	var end_s: float = track.arc_length - 40.0
	var half: float = track.road_width * 0.5
	var placed := 0
	while placed < count:
		var pack: int = 1 if _rng.randf() < 0.7 else _rng.randi_range(2, 4)
		pack = mini(pack, count - placed)
		var center := _rng.randf_range(start_s, end_s)
		for i in pack:
			var spawn_s := clampf(center + _rng.randf_range(-6.0, 6.0), start_s, end_s)
			var type := SpawnType.SIDE if _rng.randf() < 0.45 else SpawnType.AHEAD
			var lat: float
			if type == SpawnType.SIDE:
				lat = (half + 1.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
			else:
				lat = _rng.randf_range(-half + 1.5, half - 1.5)
			# Runners: rare fast sprinters, more common on later levels.
			var runner: bool = _rng.randf() < minf(0.10 + 0.03 * (level - 1), 0.3)
			_spawns.append({
				"s": spawn_s,
				"lat": lat,
				"type": type,
				"runner": runner,
				"shamble": _rng.randf_range(3.2, 4.0) + (level - 1) * 0.1 if runner \
						else _rng.randf_range(1.9, 2.7) + (level - 1) * 0.12,
				"close": 3.5 if runner else 1.5,
			})
			placed += 1
	_spawns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["s"] < b["s"])


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
			zs = maxf(zs - z["close"] * delta, _player.s)
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
			if _player.is_boosting():
				# Boosting bowls straight through: launch it, no damage.
				_launch(z, xf)
				_active.remove_at(i)
				zombie_smashed.emit()
				i -= 1
				continue
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

	_update_smashed(delta)


## Ragdoll-ish arc for smashed zombies: up, aside, and down-road, spinning.
func _launch(z: Dictionary, xf: Transform3D) -> void:
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	_smashed.append({
		"node": z["node"],
		"vel": xf.basis.y * 7.0 + xf.basis.x * side * 4.0 \
				- xf.basis.z * _player.current_speed * 0.5,
		"spin": Vector3(_rng.randf_range(4.0, 9.0), _rng.randf_range(-6.0, 6.0), 0.0),
		"t": 0.0,
	})


func _update_smashed(delta: float) -> void:
	var j := _smashed.size() - 1
	while j >= 0:
		var sm := _smashed[j]
		sm["t"] += delta
		sm["vel"] += Vector3.DOWN * 20.0 * delta
		var node := sm["node"] as Node3D
		node.position += sm["vel"] * delta
		node.rotation += sm["spin"] * delta
		if sm["t"] > 1.3:
			node.queue_free()
			_smashed.remove_at(j)
		j -= 1


func _activate(spawn: Dictionary) -> void:
	var node := Node3D.new()
	add_child(node)

	var model := MODEL_SCENE.instantiate() as Node3D
	model.scale = Vector3.ONE * 0.95
	node.add_child(model)

	# Tint every mesh in the rig from the shared palette: sickly greens and
	# purples for shamblers, rusty reds for runners.
	var is_runner: bool = spawn.get("runner", false)
	var palette := _runner_materials if is_runner else _zombie_materials
	var mat: StandardMaterial3D = palette[_rng.randi_range(0, palette.size() - 1)]
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		(mesh_instance as MeshInstance3D).material_override = mat

	# Glowing eye dots at face height. Pinned to the body rather than the
	# head bone -- at pixel scale the walk bob is too small to give the trick
	# away, and it keeps the cost to two tiny shared-mesh instances. The
	# model faces +Z and the zombie yaws toward the player, so the dots
	# always stare down the road at you.
	var eye_mat := _runner_eye_material if is_runner else _eye_material
	for x in [-0.05, 0.05]:
		var eye := MeshInstance3D.new()
		eye.mesh = _eye_mesh
		eye.material_override = eye_mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = Vector3(x, 1.58, 0.09)
		model.add_child(eye)

	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		if is_runner and anim.has_animation(&"Run"):
			anim.play(&"Run")
			anim.speed_scale = _rng.randf_range(1.0, 1.2)
		else:
			anim.play(&"Walk")
			anim.speed_scale = _rng.randf_range(1.2, 1.5) if is_runner \
					else _rng.randf_range(0.95, 1.25)

	_active.append({
		"node": node,
		"s": spawn["s"],
		"lat": spawn["lat"],
		"shamble": spawn["shamble"],
		"close": spawn.get("close", 1.5),
		"scored": false,
	})
