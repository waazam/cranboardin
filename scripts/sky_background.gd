extends Node3D
## Pixel-art city backdrop: two parallax layers of procedurally drawn
## skyline strips (Image -> ImageTexture with NEAREST filtering, so the
## chunky pixels stay crisp), blocky pixel clouds, and animated birds,
## against a procedural gradient sky.
##
## Everything sits under `_follow_root`, which tracks the player's X/Z
## exactly and the player's Y through a slow smoothing filter -- so the
## backdrop rides down the hill with the run (buildings stay planted just
## behind the road) but doesn't jitter when the player jumps.

const BIRD_SCRIPT := preload("res://scripts/bird.gd")

@export var sky_top_color := Color(0.47, 0.60, 0.74)
@export var sky_horizon_color := Color(0.84, 0.83, 0.79)
@export var building_color := Color(0.36, 0.40, 0.47)
@export var window_color := Color(0.88, 0.84, 0.72)
## Distance from the road to the near skyline layer.
@export var skyline_distance := 60.0
@export var cloud_count := 18
@export var bird_count := 10
## Time constant (1/s) for the backdrop's vertical follow; low = floaty.
@export var follow_y_smoothing := 2.0

var _rng := RandomNumberGenerator.new()
var _follow_root: Node3D
var _follow_target: Node3D
var _y_smooth: float = 0.0


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
	_y_smooth = target.global_position.y
	_update_follow(0.0)


func _process(delta: float) -> void:
	_update_follow(delta)


func _update_follow(delta: float) -> void:
	if _follow_target == null or _follow_root == null:
		return
	var t: Vector3 = _follow_target.global_position
	_y_smooth = lerpf(_y_smooth, t.y, 1.0 - exp(-follow_y_smoothing * delta))
	_follow_root.global_position = Vector3(t.x, _y_smooth, t.z)


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
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# Depth fog is what visually glues road, scenery, and skyline into one
	# atmosphere; aerial perspective shifts far fog toward the sky color.
	env.fog_enabled = true
	env.fog_light_color = Color(0.80, 0.82, 0.85)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.1
	env.fog_aerial_perspective = 0.5

	# Gentle global desaturation calms the palette without flattening it.
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42, -30, 0)
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.shadow_blur = 1.8
	sun.shadow_opacity = 0.65
	add_child(sun)


# --- Skyline ---------------------------------------------------------------

func _build_skyline() -> void:
	var root := Node3D.new()
	root.name = "Skyline"
	_follow_root.add_child(root)

	# Three parallax layers, mildly hazed toward the horizon color the
	# further back they sit -- kept subtle, because the environment fog
	# already does the heavy atmospheric lifting; over-hazing here washed
	# the silhouettes out entirely and left the lit windows floating in
	# the sky. Windows are dimmed toward their layer's silhouette so they
	# read as facade texture, not lights.
	var farthest_color := building_color.lerp(sky_horizon_color, 0.35)
	var farthest_windows := window_color.lerp(farthest_color, 0.7)
	_add_skyline_layer(root, farthest_color, farthest_windows, 0.6,
			skyline_distance + 55.0, 0.85)
	var far_color := building_color.lerp(sky_horizon_color, 0.2)
	var far_windows := window_color.lerp(far_color, 0.6)
	_add_skyline_layer(root, far_color, far_windows, 0.72,
			skyline_distance + 28.0, 0.66)
	_add_skyline_layer(root, building_color, window_color.lerp(building_color, 0.4), 1.0,
			skyline_distance, 0.5)


func _add_skyline_layer(root: Node3D, silhouette: Color, windows: Color,
		max_height_ratio: float, distance: float, meters_per_pixel: float) -> void:
	var tex := _make_skyline_texture(silhouette, windows, max_height_ratio)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	var world_w: float = tex.get_width() * meters_per_pixel
	var world_h: float = tex.get_height() * meters_per_pixel
	mesh.size = Vector2(world_w, world_h)
	quad.mesh = mesh
	# Building bases sit 1m below road level so they read as planted.
	quad.position = Vector3(0, world_h * 0.5 - 1.0, -distance)
	quad.material_override = _pixel_material(tex)
	root.add_child(quad)


func _make_skyline_texture(silhouette: Color, windows: Color,
		max_height_ratio: float) -> ImageTexture:
	var w := 480
	var h := 96
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var max_h: int = int(h * max_height_ratio)

	var x := 0
	while x < w:
		var bw: int = _rng.randi_range(14, 34)
		var bh: int = _rng.randi_range(20, max_h)
		var x_end: int = min(x + bw, w)
		# Slight per-building shade variation keeps the strip from being flat.
		var shade: float = _rng.randf_range(-0.02, 0.04)
		var col := Color(silhouette.r + shade, silhouette.g + shade,
				silhouette.b + shade, 1.0)

		for px in range(x, x_end):
			for py in range(h - bh, h):
				img.set_pixel(px, py, col)

		# Lit windows: 2x2 pixel blocks on a regular grid, sparsely on
		# (daytime -- most windows just read as glass, not lamps).
		var wy := h - bh + 3
		while wy < h - 3:
			var wx := x + 2
			while wx < x_end - 3:
				if _rng.randf() < 0.08:
					for dx in 2:
						for dy in 2:
							img.set_pixel(wx + dx, wy + dy, windows)
				wx += 4
			wy += 5

		# Occasional rooftop antenna.
		if _rng.randf() < 0.3 and bh < max_h - 6:
			var ax: int = clampi(x + _rng.randi_range(2, bw - 2), 0, w - 1)
			var a_top: int = h - bh - _rng.randi_range(3, 6)
			for ay in range(a_top, h - bh):
				img.set_pixel(ax, ay, col)

		x += bw + _rng.randi_range(-3, 2)

	return ImageTexture.create_from_image(img)


# --- Clouds ----------------------------------------------------------------

func _build_clouds() -> void:
	var root := Node3D.new()
	root.name = "Clouds"
	_follow_root.add_child(root)

	# A few texture variants shared across all cloud quads. Unlike the
	# skyline strips, clouds use smooth alpha + linear filtering so they
	# read as soft haze rather than hard-edged sprites.
	var materials: Array[StandardMaterial3D] = []
	for i in 3:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _make_cloud_texture()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		materials.append(mat)

	for i in cloud_count:
		var cloud := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		var width: float = _rng.randf_range(10.0, 22.0)
		mesh.size = Vector2(width, width * 0.5)
		cloud.mesh = mesh
		cloud.material_override = materials[i % materials.size()]
		cloud.position = Vector3(
			_rng.randf_range(-110.0, 110.0),
			_rng.randf_range(22.0, 46.0),
			_rng.randf_range(-100.0, -55.0)
		)
		root.add_child(cloud)


func _make_cloud_texture() -> ImageTexture:
	var w := 48
	var h := 24
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var body := Color(0.96, 0.96, 0.97)

	# A cloud is overlapping soft ellipse blobs; alpha falls off smoothly
	# from each blob's center, and overlaps take the strongest falloff.
	var blob_count: int = _rng.randi_range(4, 6)
	var blobs: Array[Vector4] = []
	for b in blob_count:
		blobs.append(Vector4(
			_rng.randf_range(10.0, w - 10.0),
			_rng.randf_range(6.0, h - 6.0),
			_rng.randf_range(6.0, 12.0),
			_rng.randf_range(3.5, 6.0)
		))

	for px in w:
		for py in h:
			var a := 0.0
			for blob in blobs:
				var dx := (px - blob.x) / blob.z
				var dy := (py - blob.y) / blob.w
				var falloff: float = clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0)
				a = maxf(a, pow(falloff, 1.6))
			img.set_pixel(px, py, Color(body.r, body.g, body.b, a * 0.85))

	return ImageTexture.create_from_image(img)


# --- Shared material for pixel-art quads ------------------------------------

func _pixel_material(tex: ImageTexture) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# NEAREST filtering + alpha scissor = crisp, chunky pixel edges.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# --- Birds -----------------------------------------------------------------

func _spawn_birds() -> void:
	var root := Node3D.new()
	root.name = "Birds"
	_follow_root.add_child(root)

	for i in bird_count:
		var bird := Node3D.new()
		bird.set_script(BIRD_SCRIPT)
		bird.position = Vector3(
			_rng.randf_range(-60.0, 60.0),
			_rng.randf_range(18.0, 38.0),
			_rng.randf_range(-90.0, -45.0)
		)
		bird.radius = _rng.randf_range(12.0, 35.0)
		bird.speed = _rng.randf_range(0.08, 0.2)
		root.add_child(bird)
