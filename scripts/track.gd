extends Node3D
## Builds the downhill course: a single long tilted ramp (StaticBody3D),
## side boundary walls, a finish banner, and a fair, lane-based scattering
## of obstacles. Everything is generated in code -- no imported meshes.
##
## Local convention: the ramp's own local space runs from z=0 (top/start)
## to z=-track_length (bottom/finish), with local y=0 being the ramp's top
## surface. Obstacles are placed in that local space, then converted to
## world space through ramp_body's transform so the slope tilt is applied
## automatically.

const OBSTACLE_SCENE := preload("res://scenes/obstacle.tscn")

@export var track_length: float = 380.0
@export var track_width: float = 14.0
@export var slope_angle_deg: float = 13.0
@export var obstacle_count: int = 42
@export var lane_count: int = 3

var ramp_thickness: float = 2.0
var overrun: float = 25.0

## Public data consumed by Player.setup().
var forward_tangent: Vector3
var start_position: Vector3

var ramp_body: StaticBody3D
var obstacles_root: Node3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build_ramp()
	_build_boundaries()
	_build_finish_banner()
	_spawn_obstacles()


func regenerate_obstacles() -> void:
	_spawn_obstacles()


func _build_ramp() -> void:
	var slope_rad := deg_to_rad(slope_angle_deg)
	forward_tangent = Vector3(0.0, -sin(slope_rad), -cos(slope_rad))

	ramp_body = StaticBody3D.new()
	ramp_body.name = "Ramp"
	ramp_body.rotation.x = -slope_rad
	add_child(ramp_body)
	ramp_body.add_to_group("ground")

	var total_length := track_length + overrun
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(track_width, ramp_thickness, total_length)
	mesh_instance.mesh = box
	mesh_instance.position = Vector3(0, -ramp_thickness * 0.5, -total_length * 0.5)
	mesh_instance.material_override = _flat_mat(Color(0.17, 0.17, 0.19))
	ramp_body.add_child(mesh_instance)

	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	coll.shape = shape
	coll.position = mesh_instance.position
	ramp_body.add_child(coll)

	start_position = ramp_body.global_transform * Vector3(0, 0.05, 0)

	_add_center_dashes(total_length)


func _add_center_dashes(total_length: float) -> void:
	var dash_mat := _flat_mat(Color(0.9, 0.85, 0.3))
	var z := -4.0
	while z > -total_length + 4.0:
		var dash := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.35, 0.03, 3.0)
		dash.mesh = mesh
		dash.material_override = dash_mat
		dash.position = Vector3(0, 0.02, z)
		ramp_body.add_child(dash)
		z -= 10.0


func _build_boundaries() -> void:
	var total_length := track_length + overrun
	var wall_start_z := 2.0
	var wall_end_z := -total_length
	var wall_length := wall_start_z - wall_end_z
	var wall_center_z := (wall_start_z + wall_end_z) * 0.5

	for side in [-1.0, 1.0]:
		var wall := StaticBody3D.new()
		wall.name = "Boundary%s" % ("Left" if side < 0 else "Right")
		ramp_body.add_child(wall)

		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.6, 1.6, wall_length)
		mesh.mesh = box
		mesh.material_override = _flat_mat(Color(0.85, 0.85, 0.88))
		mesh.position = Vector3(side * (track_width * 0.5 + 0.3), 0.8, wall_center_z)
		wall.add_child(mesh)

		var coll := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		coll.shape = shape
		coll.position = mesh.position
		wall.add_child(coll)


func _build_finish_banner() -> void:
	var banner := Node3D.new()
	banner.name = "FinishBanner"
	ramp_body.add_child(banner)
	var z := -track_length

	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.3, 3.0, 0.3)
		post.mesh = mesh
		post.material_override = _flat_mat(Color(0.9, 0.1, 0.12))
		post.position = Vector3(side * (track_width * 0.5 - 0.2), 1.5, z)
		banner.add_child(post)

	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(track_width - 0.2, 0.3, 0.3)
	bar.mesh = bar_mesh
	bar.material_override = _flat_mat(Color(0.95, 0.85, 0.1))
	bar.position = Vector3(0, 3.0, z)
	banner.add_child(bar)


func _spawn_obstacles() -> void:
	if obstacles_root:
		obstacles_root.queue_free()
	obstacles_root = Node3D.new()
	obstacles_root.name = "Obstacles"
	add_child(obstacles_root)

	_rng.randomize()

	var start_buffer := 20.0
	var end_buffer := 20.0
	var usable_length := track_length - start_buffer - end_buffer
	if usable_length <= 0.0 or obstacle_count <= 0:
		return
	var spacing := usable_length / float(obstacle_count)

	var lane_width := track_width / float(lane_count)
	var lane_offsets: Array[float] = []
	for i in lane_count:
		lane_offsets.append(-track_width * 0.5 + lane_width * (i + 0.5))

	for i in obstacle_count:
		var z_center := -start_buffer - spacing * i - _rng.randf_range(0.0, spacing * 0.6)
		var lanes: Array[float] = lane_offsets.duplicate()
		lanes.shuffle()
		var occupied_count: int = 1 if _rng.randf() < 0.55 else 2
		occupied_count = min(occupied_count, lane_count - 1)

		for j in occupied_count:
			var obstacle: Area3D = OBSTACLE_SCENE.instantiate()
			obstacle.type = _random_type()
			obstacles_root.add_child(obstacle)
			var jitter_x := _rng.randf_range(-lane_width * 0.15, lane_width * 0.15)
			var jitter_z := _rng.randf_range(-1.0, 1.0)
			var local_point := Vector3(lanes[j] + jitter_x, 0.0, z_center + jitter_z)
			obstacle.global_position = ramp_body.global_transform * local_point
			obstacle.global_rotation = ramp_body.global_rotation


func _random_type() -> Obstacle.ObstacleType:
	var roll := _rng.randf()
	if roll < 0.15:
		return Obstacle.ObstacleType.RAMP
	elif roll < 0.45:
		return Obstacle.ObstacleType.CONE
	elif roll < 0.75:
		return Obstacle.ObstacleType.RAIL
	else:
		return Obstacle.ObstacleType.CRATE


func _flat_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	return mat
