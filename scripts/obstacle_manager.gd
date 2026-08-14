extends Node3D
## Hazard barriers: hip-height roadblocks in hot pink / phosphor black
## warning stripes, up on little legs. They never chase -- they're the
## fixed hurdles of the run. Steer around one, or jump it clean for style
## points; ride into it and it costs a hit, same as a zombie. Same
## spline-space contact pattern as the pads and ramps; seeded per level.

signal hurdled()

const BARRIER_S_RANGE := 1.0
## Half the striped bar's width, minus a hair so grazing an end post with
## your shoulder doesn't count as a crash.
const BARRIER_HALF_WIDTH := 1.8
## A hit only lands while the player is below the bar; a normal jump
## (apex ~1.64) clears it with room to spare.
const BARRIER_MAX_HEIGHT := 0.85

@export var base_count: int = 7
@export var count_per_level: int = 2

var _track: Node3D
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _barriers: Array[Dictionary] = []
var _container: Node3D
var _stripe_pink: StandardMaterial3D
var _stripe_dark: StandardMaterial3D
var _leg_mat: StandardMaterial3D
var _segment_mesh: BoxMesh
var _leg_mesh: BoxMesh
var _lamp_mesh: BoxMesh
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	# Warning stripes: emissive hot pink alternating with near-black, so the
	# barrier reads as "wall" through the dusk where the flat-on-the-road
	# pads read as "paint". One material + mesh pool shared by every barrier.
	_stripe_pink = StandardMaterial3D.new()
	_stripe_pink.albedo_color = Color(1.0, 0.35, 0.65)
	_stripe_pink.emission_enabled = true
	_stripe_pink.emission = Color(1.0, 0.3, 0.6)
	_stripe_pink.emission_energy_multiplier = 1.3

	_stripe_dark = StandardMaterial3D.new()
	_stripe_dark.albedo_color = Color(0.08, 0.05, 0.12)
	_stripe_dark.roughness = 0.7

	_leg_mat = StandardMaterial3D.new()
	_leg_mat.albedo_color = Color(0.2, 0.22, 0.25)  # streetlight-pole gray

	# Blinking-beacon caps on the end posts, HDR cyan so they bloom: the
	# far-off tell that a hurdle is coming before the stripes resolve.
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.7, 2.0, 2.0)
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_segment_mesh = BoxMesh.new()
	_segment_mesh.size = Vector3(0.9, 0.42, 0.18)
	_leg_mesh = BoxMesh.new()
	_leg_mesh.size = Vector3(0.12, 0.5, 0.12)
	_lamp_mesh = BoxMesh.new()
	_lamp_mesh.size = Vector3(0.16, 0.1, 0.16)


func setup(track: Node3D, player: Node3D, level: int) -> void:
	_track = track
	_player = player
	if _container:
		_container.queue_free()
	_container = Node3D.new()
	add_child(_container)
	_barriers.clear()

	_rng.seed = 9000 + level * 5039
	var count: int = base_count + (level - 1) * count_per_level
	var start_s := 110.0
	var end_s: float = track.arc_length - 70.0
	var spacing := (end_s - start_s) / float(count)
	var half: float = track.road_width * 0.5
	for i in count:
		var s := start_s + spacing * i + _rng.randf_range(0.0, spacing * 0.5)
		var lat := _rng.randf_range(-half + 2.2, half - 2.2)
		_barriers.append({"s": s, "lat": lat, "used": false})
		_make_barrier(s, lat)


## Four striped segments up on legs, end posts capped with beacons. Built
## from the shared mesh/material pool; only the transforms are per-barrier.
func _make_barrier(s: float, lat: float) -> void:
	var xf: Transform3D = _track.transform_at(s, lat)
	var root := Node3D.new()
	root.transform = xf
	_container.add_child(root)

	for i in 4:
		var seg := MeshInstance3D.new()
		seg.mesh = _segment_mesh
		seg.material_override = _stripe_pink if i % 2 == 0 else _stripe_dark
		seg.position = Vector3(-1.35 + 0.9 * i, 0.62, 0.0)
		root.add_child(seg)

	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.mesh = _leg_mesh
		leg.material_override = _leg_mat
		leg.position = Vector3(side * 1.6, 0.25, 0.0)
		root.add_child(leg)

		var lamp := MeshInstance3D.new()
		lamp.mesh = _lamp_mesh
		lamp.material_override = _lamp_mat
		lamp.position = Vector3(side * 1.6, 0.88, 0.0)
		root.add_child(lamp)


func _physics_process(_delta: float) -> void:
	if _track == null or _player == null:
		return
	if _player.run_state != _player.RunState.RUNNING:
		return
	for barrier in _barriers:
		if barrier["used"]:
			continue
		var s_gap: float = barrier["s"] - _player.s
		var lat_gap: float = absf(barrier["lat"] - _player.lateral)

		# Riding into the bar costs a hit (take_damage handles the
		# invulnerability window; either way this barrier is spent, so a
		# blink-through never also scores as a hurdle).
		if absf(s_gap) < BARRIER_S_RANGE and lat_gap < BARRIER_HALF_WIDTH \
				and _player.height < BARRIER_MAX_HEIGHT:
			barrier["used"] = true
			_player.take_damage(1)
			continue

		# Cleared it: the player is past the bar, was inside its span, and
		# never touched it -- the only way that happens is over the top.
		if s_gap < -BARRIER_S_RANGE:
			barrier["used"] = true
			if lat_gap < BARRIER_HALF_WIDTH:
				hurdled.emit()
