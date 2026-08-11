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
	_build_scenery()
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


# --- Roadside scenery -------------------------------------------------------
# Decorative only (no collision). Items are positioned in the ramp's local
# space so they follow the slope, then counter-rotated by the slope angle so
# poles/trees/buildings stand plumb-vertical like real streetside objects on
# a hill, sunk slightly so their bases never float above the surface.

func _build_scenery() -> void:
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	ramp_body.add_child(scenery)

	var srng := RandomNumberGenerator.new()
	srng.seed = 90210  # fixed seed: scenery stays put across restarts

	var edge := track_width * 0.5
	var slope_rad := deg_to_rad(slope_angle_deg)

	# Streetlights: alternating sides, evenly spaced, arm reaching over the road.
	var z := -14.0
	var light_side := 1.0
	while z > -track_length:
		_add_streetlight(scenery, Vector3(light_side * (edge + 1.2), -0.05, z), -light_side, slope_rad)
		light_side = -light_side
		z -= 28.0

	# Trees, bushes, and street clutter scattered along both sides.
	for s in [-1.0, 1.0]:
		z = -8.0
		while z > -track_length - 10.0:
			var pos := Vector3(s * (edge + srng.randf_range(1.8, 6.0)), -0.05, z + srng.randf_range(-4.0, 4.0))
			var roll := srng.randf()
			if roll < 0.4:
				_add_tree(scenery, pos, slope_rad, srng)
			elif roll < 0.65:
				_add_bush(scenery, pos, slope_rad, srng)
			elif roll < 0.85:
				_add_trash_can(scenery, pos, slope_rad)
			else:
				_add_hydrant(scenery, pos, slope_rad)
			z -= srng.randf_range(7.0, 14.0)

	# City-canyon building slabs further out, with pixel-art window faces
	# toward the road.
	var window_mats: Array[StandardMaterial3D] = []
	for i in 3:
		window_mats.append(_make_window_material(srng))
	for s in [-1.0, 1.0]:
		z = -20.0
		while z > -track_length + 10.0:
			var w := srng.randf_range(14.0, 26.0)
			_add_building_slab(scenery, s, z, w, slope_rad, srng, window_mats)
			z -= w + srng.randf_range(6.0, 18.0)

	# Manhole covers down the road surface.
	z = -30.0
	var mh_mat := _flat_mat(Color(0.09, 0.09, 0.1))
	while z > -track_length:
		var mh := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.45
		disc.bottom_radius = 0.45
		disc.height = 0.02
		mh.mesh = disc
		mh.material_override = mh_mat
		mh.position = Vector3(srng.randf_range(-edge * 0.6, edge * 0.6), 0.015, z)
		scenery.add_child(mh)
		z -= srng.randf_range(35.0, 55.0)


func _add_streetlight(parent: Node3D, pos: Vector3, toward_road: float, slope_rad: float) -> void:
	var item := Node3D.new()
	item.position = pos
	item.rotation.x = slope_rad
	parent.add_child(item)

	var pole_mat := _flat_mat(Color(0.2, 0.22, 0.25))
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 4.2
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 2.1, 0)
	pole.material_override = pole_mat
	item.add_child(pole)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(1.0, 0.08, 0.08)
	arm.mesh = arm_mesh
	arm.position = Vector3(toward_road * 0.5, 4.16, 0)
	arm.material_override = pole_mat
	item.add_child(arm)

	var lamp := MeshInstance3D.new()
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.32, 0.1, 0.16)
	lamp.mesh = lamp_mesh
	lamp.position = Vector3(toward_road * 0.95, 4.1, 0)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.9, 0.6)
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.85, 0.5)
	lamp_mat.emission_energy_multiplier = 2.0
	lamp.material_override = lamp_mat
	item.add_child(lamp)


func _add_tree(parent: Node3D, pos: Vector3, slope_rad: float, srng: RandomNumberGenerator) -> void:
	var item := Node3D.new()
	item.position = pos
	item.rotation.x = slope_rad
	parent.add_child(item)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.16
	var trunk_h := srng.randf_range(1.2, 2.0)
	trunk_mesh.height = trunk_h
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0, trunk_h * 0.5, 0)
	trunk.material_override = _flat_mat(Color(0.32, 0.22, 0.13))
	item.add_child(trunk)

	# Blocky stacked-cube foliage to match the pixel-art vibe.
	var green := Color(0.13, 0.35 + srng.randf_range(0.0, 0.12), 0.16)
	var size := srng.randf_range(1.4, 2.0)
	var y := trunk_h + size * 0.35
	for layer in 2:
		var leaves := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * size
		leaves.mesh = box
		leaves.position = Vector3(0, y, 0)
		leaves.material_override = _flat_mat(green.lightened(layer * 0.12))
		item.add_child(leaves)
		y += size * 0.55
		size *= 0.65


func _add_bush(parent: Node3D, pos: Vector3, slope_rad: float, srng: RandomNumberGenerator) -> void:
	var item := Node3D.new()
	item.position = pos
	item.rotation.x = slope_rad
	parent.add_child(item)

	var bush := MeshInstance3D.new()
	var box := BoxMesh.new()
	var size := srng.randf_range(0.5, 0.9)
	box.size = Vector3(size * 1.3, size, size * 1.3)
	bush.mesh = box
	bush.position = Vector3(0, size * 0.45, 0)
	bush.material_override = _flat_mat(Color(0.16, 0.4, 0.18))
	item.add_child(bush)


func _add_trash_can(parent: Node3D, pos: Vector3, slope_rad: float) -> void:
	var item := Node3D.new()
	item.position = pos
	item.rotation.x = slope_rad
	parent.add_child(item)

	var can := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.26
	cyl.bottom_radius = 0.22
	cyl.height = 0.65
	can.mesh = cyl
	can.position = Vector3(0, 0.325, 0)
	can.material_override = _flat_mat(Color(0.3, 0.32, 0.34))
	item.add_child(can)


func _add_hydrant(parent: Node3D, pos: Vector3, slope_rad: float) -> void:
	var item := Node3D.new()
	item.position = pos
	item.rotation.x = slope_rad
	parent.add_child(item)

	var red := _flat_mat(Color(0.75, 0.12, 0.1))
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.11
	cyl.bottom_radius = 0.13
	cyl.height = 0.45
	body.mesh = cyl
	body.position = Vector3(0, 0.225, 0)
	body.material_override = red
	item.add_child(body)

	var cap := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.11
	dome.height = 0.16
	cap.mesh = dome
	cap.position = Vector3(0, 0.48, 0)
	cap.material_override = red
	item.add_child(cap)


func _add_building_slab(parent: Node3D, side: float, z: float, width: float,
		slope_rad: float, srng: RandomNumberGenerator,
		window_mats: Array[StandardMaterial3D]) -> void:
	var h := srng.randf_range(10.0, 26.0)
	var d := srng.randf_range(8.0, 14.0)
	var x := side * (track_width * 0.5 + srng.randf_range(9.0, 15.0))

	var item := Node3D.new()
	# Sunk so the base never floats off the slope under the counter-rotation.
	item.position = Vector3(x, -0.8, z - width * 0.5)
	item.rotation.x = slope_rad
	parent.add_child(item)

	var shade := srng.randf_range(-0.015, 0.03)
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(d, h, width)
	slab.mesh = box
	slab.position = Vector3(0, h * 0.5, 0)
	slab.material_override = _flat_mat(Color(0.1 + shade, 0.09 + shade, 0.14 + shade))
	item.add_child(slab)

	# Pixel-art window face toward the road.
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, h * 0.92)
	face.mesh = quad
	face.position = Vector3(-side * (d * 0.5 + 0.05), h * 0.5, 0)
	face.rotation.y = -side * PI * 0.5
	face.material_override = window_mats[srng.randi_range(0, window_mats.size() - 1)]
	item.add_child(face)


func _make_window_material(srng: RandomNumberGenerator) -> StandardMaterial3D:
	var w := 20
	var h := 28
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var facade := Color(0.08, 0.07, 0.12, 1.0)
	var lit := Color(1.0, 0.85, 0.45, 1.0)
	var dark := Color(0.13, 0.12, 0.18, 1.0)

	img.fill(facade)
	var y := 2
	while y < h - 2:
		var x := 2
		while x < w - 2:
			var col := lit if srng.randf() < 0.35 else dark
			for dx in 2:
				for dy in 2:
					img.set_pixel(x + dx, y + dy, col)
			x += 4
		y += 4

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


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
