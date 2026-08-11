extends Node3D
## Procedural dusk city backdrop: gradient sky + sun, a silhouette skyline
## with lit multimesh windows, soft billboarded cloud sprites, and a handful
## of animated birds. Everything is generated in code, no imported art.
##
## The visual content sits under `_follow_root`, which trails the player's
## X/Z (and a fraction of their Y) every frame so the skyline always reads
## as distant background regardless of how far down the hill the player is,
## with a little parallax drop for depth.

const BIRD_SCRIPT := preload("res://scripts/bird.gd")

@export var sky_top_color := Color(0.10, 0.08, 0.24)
@export var sky_horizon_color := Color(0.92, 0.55, 0.42)
@export var building_color := Color(0.07, 0.06, 0.11)
@export var window_color := Color(1.0, 0.85, 0.45)
@export var building_count := 26
@export var skyline_distance := 170.0
@export var skyline_span := 260.0
@export var cloud_count := 12
@export var bird_count := 7
@export var follow_y_factor := 0.6

var _rng := RandomNumberGenerator.new()
var _follow_root: Node3D
var _follow_target: Node3D


func _ready() -> void:
	_rng.seed = 1337

	_setup_environment()

	_follow_root = Node3D.new()
	_follow_root.name = "Backdrop"
	add_child(_follow_root)

	_build_skyline()
	_build_clouds()
	_spawn_birds()


## Called by Main once the player exists, so the backdrop tracks it.
func set_follow_target(target: Node3D) -> void:
	_follow_target = target
	_update_follow()


func _process(_delta: float) -> void:
	_update_follow()


func _update_follow() -> void:
	if _follow_target == null or _follow_root == null:
		return
	var t: Vector3 = _follow_target.global_position
	_follow_root.global_position = Vector3(t.x, t.y * follow_y_factor, t.z)


func _setup_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top_color
	sky_material.sky_horizon_color = sky_horizon_color
	sky_material.ground_bottom_color = sky_horizon_color
	sky_material.ground_horizon_color = sky_horizon_color

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-35, -35, 0)
	sun.light_color = Color(1.0, 0.87, 0.72)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _build_skyline() -> void:
	var root := Node3D.new()
	root.name = "Skyline"
	_follow_root.add_child(root)
	root.position = Vector3(0, 0, -skyline_distance)

	var building_mat := StandardMaterial3D.new()
	building_mat.albedo_color = building_color
	building_mat.roughness = 1.0

	var window_transforms: Array[Transform3D] = []
	var n: int = max(building_count, 2)

	for i in n:
		var x := -skyline_span * 0.5 + skyline_span * (float(i) / float(n - 1))
		x += _rng.randf_range(-3.0, 3.0)
		var height := _rng.randf_range(8.0, 34.0)
		var width := _rng.randf_range(6.0, 11.0)
		var depth := _rng.randf_range(6.0, 11.0)
		var z_jitter := _rng.randf_range(-30.0, 20.0)

		var building := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, height, depth)
		building.mesh = mesh
		building.material_override = building_mat
		building.position = Vector3(x, height * 0.5, z_jitter)
		root.add_child(building)

		var rows: int = max(int(height / 3.0), 1)
		var cols: int = max(int(width / 2.2), 1)
		var front_z := z_jitter + depth * 0.5 + 0.05
		for row in rows:
			for col in cols:
				if _rng.randf() > 0.4:
					continue
				var wx: float = x - width * 0.5 + (col + 0.5) * (width / cols)
				var wy: float = 1.5 + row * 3.0
				window_transforms.append(Transform3D(Basis(), Vector3(wx, wy, front_z)))

	if window_transforms.size() > 0:
		var window_mesh := BoxMesh.new()
		window_mesh.size = Vector3(0.6, 0.8, 0.06)

		var window_multimesh := MultiMesh.new()
		window_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		window_multimesh.mesh = window_mesh
		window_multimesh.instance_count = window_transforms.size()
		for idx in window_transforms.size():
			window_multimesh.set_instance_transform(idx, window_transforms[idx])

		var window_mat := StandardMaterial3D.new()
		window_mat.albedo_color = window_color
		window_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		window_mat.emission_enabled = true
		window_mat.emission = window_color
		window_mat.emission_energy_multiplier = 1.6

		var mm_instance := MultiMeshInstance3D.new()
		mm_instance.multimesh = window_multimesh
		mm_instance.material_override = window_mat
		root.add_child(mm_instance)


func _build_clouds() -> void:
	var root := Node3D.new()
	root.name = "Clouds"
	_follow_root.add_child(root)

	var cloud_texture := _make_cloud_texture()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = cloud_texture
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for i in cloud_count:
		var cloud := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		var size := _rng.randf_range(16.0, 34.0)
		mesh.size = Vector2(size, size * 0.55)
		cloud.mesh = mesh
		cloud.material_override = mat
		cloud.position = Vector3(
			_rng.randf_range(-140.0, 140.0),
			_rng.randf_range(38.0, 78.0),
			_rng.randf_range(-260.0, -70.0)
		)
		root.add_child(cloud)


func _make_cloud_texture() -> ImageTexture:
	var size := 64
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	for y in size:
		for x in size:
			var d: float = Vector2(x, y).distance_to(center) / (size * 0.5)
			var a: float = clamp(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _spawn_birds() -> void:
	var root := Node3D.new()
	root.name = "Birds"
	_follow_root.add_child(root)

	for i in bird_count:
		var bird := Node3D.new()
		bird.set_script(BIRD_SCRIPT)
		bird.position = Vector3(
			_rng.randf_range(-70.0, 70.0),
			_rng.randf_range(25.0, 50.0),
			_rng.randf_range(-150.0, -40.0)
		)
		bird.radius = _rng.randf_range(15.0, 45.0)
		bird.speed = _rng.randf_range(0.08, 0.2)
		root.add_child(bird)
