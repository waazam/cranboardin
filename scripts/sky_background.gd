extends Node3D
## Pixel-art city backdrop: two parallax layers of procedurally drawn
## skyline strips (Image -> ImageTexture with NEAREST filtering, so the
## chunky pixels stay crisp), blocky pixel clouds, animated birds, and a
## sparse starfield, against a procedural gradient sky.
##
## Everything sits under `_follow_root`, which tracks the player's X/Z
## exactly and the player's Y through a slow smoothing filter -- so the
## backdrop rides down the hill with the run (buildings stay planted just
## behind the road) but doesn't jitter when the player jumps.

const BIRD_SCRIPT := preload("res://scripts/bird.gd")

@export var sky_top_color := Color(0.18, 0.08, 0.32)
@export var sky_horizon_color := Color(0.95, 0.42, 0.48)
@export var building_color := Color(0.16, 0.12, 0.28)
@export var window_color := Color(1.0, 0.55, 0.75)  # pink, palette-strict
## Distance from the road to the near skyline layer. Kept well beyond the
## roadside building slabs (which line the road out to ~40m and fade into
## fog past ~150m) so the backdrop never slices through them.
@export var skyline_distance := 190.0
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
	_build_stars()
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

	# Yaw the backdrop toward the player's heading (smoothed), so the city
	# always sits ahead even as the road curves.
	var fwd: Vector3 = -_follow_target.global_basis.z
	var target_yaw := atan2(-fwd.x, -fwd.z)
	_follow_root.rotation.y = lerp_angle(_follow_root.rotation.y, target_yaw,
			1.0 - exp(-1.2 * delta))


func _setup_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top_color
	sky_material.sky_horizon_color = sky_horizon_color
	# A slightly lazier sky curve lets the warm horizon band climb a little
	# higher before the plum zenith takes over -- a richer sunset gradient
	# than the default tight strip.
	sky_material.sky_curve = 0.09
	# Below the horizon: dark plum, so the world isn't floating on glow; the
	# horizon edge itself glows a warm ember so the band reads hot right at
	# the skyline.
	sky_material.ground_bottom_color = Color(0.14, 0.09, 0.2)
	sky_material.ground_horizon_color = Color(0.58, 0.26, 0.32)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.25
	# ACES with a raised white point: keeps the neon punchy without the
	# highlights clipping to flat white the way Filmic did.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.2

	# HDR glow so every emissive surface (neon windows, boost pads, trail,
	# score popups) actually blooms. SOFTLIGHT keeps it a halo rather than a
	# white-out; the threshold sits just under 1.0 so only genuinely hot
	# pixels contribute.
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.9
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	# Mid-size blur levels only: tight halos around neon, no screen-wide fog.
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.4)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.2)
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)

	# Gentle SSAO grounds the props against the road -- cheap in Forward+,
	# but skipped on the web build (the GL Compatibility renderer ignores it
	# anyway, and the flat billboard look doesn't miss it).
	if not OS.has_feature("web"):
		env.ssao_enabled = true
		env.ssao_radius = 1.0
		env.ssao_intensity = 1.2
		env.ssao_detail = 0.3

	# Depth fog glues road, scenery, and skyline into one atmosphere;
	# tinted pink-purple for the neon dusk.
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.32, 0.52)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.1
	env.fog_aerial_perspective = 0.5

	# Push saturation + a whisper of contrast for the lurid retro look
	# (ACES flattens a touch versus Filmic, so the grade compensates).
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.04

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Low dusk sun -- warmed toward amber and pushed a bit harder so lit
	# faces clearly separate from shadowed ones.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, -30, 0)
	sun.light_color = Color(1.0, 0.64, 0.52)
	sun.light_energy = 0.9
	# Shadow maps redraw the whole scene per split -- the single biggest GL
	# cost on the web build, and at 1/4-res pixelation with billboard sprites
	# they barely read. Web skips them.
	sun.shadow_enabled = not OS.has_feature("web")
	sun.shadow_blur = 1.8
	sun.shadow_opacity = 0.7
	# Two splits are plenty at this draw distance and cheaper than the
	# default four; shadows fade out well before the fog swallows things.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 130.0
	add_child(sun)

	# Very dim cool-blue fill from the opposite side, no shadows: lifts the
	# pitch-black faces away from the sun into a soft night-sky blue instead.
	# Kept faint enough that its disc in the procedural sky reads as nothing
	# more than a ghost of moonrise. Specular off so it can't add a second
	# highlight.
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-48, 150, 0)
	fill.light_color = Color(0.45, 0.58, 1.0)
	fill.light_energy = 0.15
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)


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
			skyline_distance + 170.0, 2.7)
	var far_color := building_color.lerp(sky_horizon_color, 0.2)
	var far_windows := window_color.lerp(far_color, 0.6)
	_add_skyline_layer(root, far_color, far_windows, 0.72,
			skyline_distance + 85.0, 2.1)
	_add_skyline_layer(root, building_color, window_color.lerp(building_color, 0.4), 1.0,
			skyline_distance, 1.6)


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
	# Neon window variants: warm, cyan, pink (blended toward this layer's
	# already-hazed base so far layers stay atmospheric).
	var window_variants: Array[Color] = [
		windows,
		windows.lerp(Color(0.4, 0.9, 0.95), 0.6),
		windows.lerp(Color(1.0, 0.4, 0.75), 0.6),
	]

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

		# Lit windows: 2x2 pixel blocks on a regular grid; dusk city, so a
		# decent scattering of lit neon windows.
		var wy := h - bh + 3
		while wy < h - 3:
			var wx := x + 2
			while wx < x_end - 3:
				if _rng.randf() < 0.18:
					var wcol := window_variants[_rng.randi_range(0, 2)]
					for dx in 2:
						for dy in 2:
							img.set_pixel(wx + dx, wy + dy, wcol)
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


# --- Stars -----------------------------------------------------------------

## Sparse starfield on a dome high above the horizon: one MultiMesh of tiny
## unshaded quads (a single draw call), each a couple of device pixels after
## the viewport's pixel shrink. Stars fade in with elevation so none pop out of
## the warm horizon band, and the dome rides `_follow_root` like the skyline
## so it never parallaxes against the sky gradient.
const STAR_COUNT := 140
## Dome radius: beyond the farthest skyline strip (~360m) but inside the
## camera's 600m far plane.
const STAR_DOME_RADIUS := 430.0

func _build_stars() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true  # per-star tint/alpha from instance color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Way past the fog falloff; fog would just gray them out.
	mat.disable_fog = true
	# Transparent objects sort by their instance origin, and this MultiMesh's
	# origin is `_follow_root` -- the player's own position -- so despite being
	# the farthest thing in the scene it would sort as the *nearest* and draw
	# over the clouds, neon trail, and popups. Force it to the very back of
	# the transparent pass instead.
	mat.render_priority = -1
	mesh.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = STAR_COUNT

	# Faint dusk-star tints: lavender-white base with cyan and pink
	# scattered through, echoing the strict neon palette.
	var tints: Array[Color] = [
		Color(0.94, 0.9, 1.0),
		Color(0.94, 0.9, 1.0),
		Color(0.75, 0.95, 1.0),
		Color(1.0, 0.8, 0.92),
	]

	for i in STAR_COUNT:
		# Random dome position, biased low: elevation squared toward the
		# horizon would clump stars in the fade band, so sample linearly
		# between "just above the warm band" and "not quite overhead".
		var azimuth: float = _rng.randf_range(0.0, TAU)
		var elevation: float = _rng.randf_range(deg_to_rad(9.0), deg_to_rad(72.0))
		var dir := Vector3(
			cos(elevation) * sin(azimuth),
			sin(elevation),
			cos(elevation) * cos(azimuth)
		)
		var pos := dir * STAR_DOME_RADIUS

		# Face the quad back toward the dome center (the player): -Z looks
		# outward along `dir`, leaving the quad's +Z normal pointing inward.
		var t := Transform3D.IDENTITY.looking_at(dir, Vector3.UP)
		t.origin = pos
		mm.set_instance_transform(i, t)

		# Fade in across ~9..24 degrees of elevation, so stars emerge out of
		# the sunset glow instead of sitting on top of it; brightness also
		# varies per star so the field doesn't read as a uniform stipple.
		var horizon_fade: float = smoothstep(deg_to_rad(9.0), deg_to_rad(24.0), elevation)
		var brightness: float = _rng.randf_range(0.35, 1.0)
		var col: Color = tints[_rng.randi_range(0, tints.size() - 1)]
		col.a = horizon_fade * brightness * 0.85
		mm.set_instance_color(i, col)

	var stars := MultiMeshInstance3D.new()
	stars.name = "Stars"
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_follow_root.add_child(stars)


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
		var width: float = _rng.randf_range(22.0, 44.0)
		mesh.size = Vector2(width, width * 0.5)
		cloud.mesh = mesh
		var mat := materials[i % materials.size()]
		mat.disable_fog = true
		cloud.material_override = mat
		# High and far, clear of the roadside building corridor.
		cloud.position = Vector3(
			_rng.randf_range(-200.0, 200.0),
			_rng.randf_range(40.0, 80.0),
			_rng.randf_range(-230.0, -130.0)
		)
		root.add_child(cloud)


func _make_cloud_texture() -> ImageTexture:
	var w := 48
	var h := 24
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var body := Color(0.95, 0.8, 0.88)  # dusk-lit pink-tinged clouds

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
	# The skyline sits far beyond the fog falloff; its haze is baked into
	# the layer colors instead, so exempt it from environment fog.
	mat.disable_fog = true
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
			_rng.randf_range(32.0, 52.0),
			_rng.randf_range(-140.0, -80.0)
		)
		bird.radius = _rng.randf_range(12.0, 35.0)
		bird.speed = _rng.randf_range(0.08, 0.2)
		root.add_child(bird)
