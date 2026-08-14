extends Node3D
## Main menu: an empty neon street corner at dusk -- glowing road, lone
## streetlight, city backdrop -- with its own dreamy synth theme. Any
## key / click / tap starts the game.

const GAME_SCENE := "res://scenes/main.tscn"
const SAVE_PATH := "user://save.cfg"  # written by main.gd

@onready var viewport_frame: SubViewportContainer = $ViewportFrame
@onready var world: Node3D = $ViewportFrame/SubViewport/World

## Strict palette: hot pink, cyan, teal, electric purple, phosphor black.
const NEON_PINK := Color(1.0, 0.29, 0.66)
const NEON_CYAN := Color(0.36, 0.95, 0.98)
const NEON_TEAL := Color(0.28, 0.88, 0.75)
const NEON_PURPLE := Color(0.72, 0.4, 1.0)
const CRT_BLACK := Color(0.05, 0.02, 0.09)

var _music: AudioStreamPlayer
var _font: SystemFont
var _prompt: Label
var _prompt_time: float = 0.0
var _starting: bool = false
var _fade_layer: CanvasLayer


func _ready() -> void:
	# Same adaptive pixelation as the game: target a fixed internal
	# resolution (a bit chunkier than gameplay) whatever the screen.
	_update_pixelation()
	get_viewport().size_changed.connect(_update_pixelation)

	# A still postcard: freeze the backdrop (stops the circling birds)
	# once it has built itself.
	$ViewportFrame/SubViewport/Background.process_mode = Node.PROCESS_MODE_DISABLED

	# Load the game scene in the background while the menu idles, so
	# pressing start swaps worlds without a visible hitch.
	ResourceLoader.load_threaded_request(GAME_SCENE)

	_build_stage()
	_build_camera()
	_build_ui()
	_build_crt_overlay()
	_start_music()


static func _is_mobile() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") \
			or OS.has_feature("android") or OS.has_feature("ios")


## ~216 visible pixel rows on desktop, ~170 on mobile.
func _update_pixelation() -> void:
	var rows := 170.0 if _is_mobile() else 216.0
	viewport_frame.stretch_shrink = clampi(
			roundi(get_viewport().get_visible_rect().size.y / rows), 2, 10)


func _process(delta: float) -> void:
	# Hard on/off arcade blink -- no fade, like a cabinet attract screen.
	_prompt_time += delta
	_prompt.visible = fmod(_prompt_time, 0.9) < 0.55


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		_start_game()


## Fade the screen and music down, then swap to the preloaded game scene:
## a dip to black instead of a hard cut, so entering the run feels like
## rolling into the world rather than switching screens.
func _start_game() -> void:
	if _starting:
		return
	_starting = true

	var fade := ColorRect.new()
	fade.color = Color(CRT_BLACK, 0.0)
	fade.size = get_viewport().get_visible_rect().size
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 30  # above the UI and the vignette
	_fade_layer.add_child(fade)
	add_child(_fade_layer)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(fade, "color:a", 1.0, 0.4)
	tween.tween_property(_music, "volume_db", -40.0, 0.4)
	tween.chain().tween_callback(_swap_to_game)


## Swap once the screen is black: put up the LOADING card, make sure it has
## actually been presented, then do the heavy work (finishing the threaded
## load and building the level in the game's _ready). While that blocks --
## noticeably on the web build -- the presented frame is the loading card,
## not a blank canvas. The game scene then fades in from the same black.
func _swap_to_game() -> void:
	var loading := Label.new()
	loading.text = "LOADING..."
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading.add_theme_font_override("font", _font)
	loading.add_theme_font_size_override("font_size", 40)
	loading.add_theme_color_override("font_color", Color(1, 1, 1))
	loading.add_theme_color_override("font_shadow_color", NEON_PINK)
	loading.add_theme_constant_override("shadow_offset_x", 4)
	loading.add_theme_constant_override("shadow_offset_y", 4)
	_fade_layer.add_child(loading)

	# Two frames so the card is drawn and presented before we block.
	await get_tree().process_frame
	await get_tree().process_frame

	var packed := ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
	var tree := get_tree()
	var game := packed.instantiate()
	tree.root.add_child(game)  # level generation happens here, card on screen
	tree.current_scene = game
	queue_free()  # drop the menu (and this card) now the game is ready


# --- Stage ------------------------------------------------------------------
# A little neon street corner: a road strip with the game's glowing center
# dashes and teal edge lines running diagonally past the camera, and a
# streetlight leaning in over it.

## Road heading in radians -- shared by the strip, its markings, and the
## board so everything lines up along the same diagonal.
const ROAD_YAW := -0.55

func _build_stage() -> void:
	# Dark purple ground plane.
	var ground := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(60.0, 1.0, 60.0)
	ground.mesh = slab
	ground.position = Vector3(0, -0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.13, 0.23)
	mat.roughness = 0.9
	ground.material_override = mat
	world.add_child(ground)

	_build_road()

	# Streetlight leaning over the road from the left, matching the track's
	# design: dark pole, arm, hot pink sodium head that blooms.
	world.add_child(_make_streetlight(Vector3(-2.1, 0, -1.3)))


## The road: a dark asphalt strip on the ROAD_YAW diagonal, with the
## game's pink center dashes and teal edge glow lines.
func _build_road() -> void:
	var road_root := Node3D.new()
	road_root.rotation.y = ROAD_YAW
	road_root.position = Vector3(0.4, 0, -0.2)
	world.add_child(road_root)

	var asphalt := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(4.6, 0.06, 44.0)
	asphalt.mesh = strip
	asphalt.position = Vector3(0, 0.03, 0)
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.15, 0.12, 0.21)
	road_mat.roughness = 0.55
	road_mat.metallic = 0.2
	asphalt.material_override = road_mat
	road_root.add_child(asphalt)

	var dash_mat := StandardMaterial3D.new()
	dash_mat.albedo_color = Color(1.0, 0.35, 0.65)
	dash_mat.emission_enabled = true
	dash_mat.emission = Color(1.0, 0.3, 0.6)
	dash_mat.emission_energy_multiplier = 1.6
	var z := -20.0
	while z < 20.0:
		var dash := MeshInstance3D.new()
		var dash_mesh := BoxMesh.new()
		dash_mesh.size = Vector3(0.5, 0.02, 1.9)
		dash.mesh = dash_mesh
		dash.position = Vector3(0, 0.07, z)
		dash.material_override = dash_mat
		road_root.add_child(dash)
		z += 4.5

	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.1, 0.3, 0.32)
	edge_mat.emission_enabled = true
	edge_mat.emission = Color(0.25, 0.95, 0.9)
	edge_mat.emission_energy_multiplier = 1.1
	for x in [-2.15, 2.15]:
		var edge := MeshInstance3D.new()
		var edge_mesh := BoxMesh.new()
		edge_mesh.size = Vector3(0.14, 0.02, 44.0)
		edge.mesh = edge_mesh
		edge.position = Vector3(x, 0.07, 0)
		edge.material_override = edge_mat
		road_root.add_child(edge)


func _make_streetlight(pos: Vector3) -> Node3D:
	var item := Node3D.new()
	item.position = pos
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.2, 0.22, 0.25)

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
	arm.position = Vector3(0.5, 4.16, 0)
	arm.material_override = pole_mat
	item.add_child(arm)

	var lamp := MeshInstance3D.new()
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.32, 0.1, 0.16)
	lamp.mesh = lamp_mesh
	lamp.position = Vector3(0.95, 4.1, 0)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.55, 0.75)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.4, 0.7)
	lamp_mat.emission_energy_multiplier = 2.6
	lamp.material_override = lamp_mat
	item.add_child(lamp)
	return item


func _build_camera() -> void:
	# Fixed shot: the menu is a still postcard of the street corner.
	var camera := Camera3D.new()
	camera.fov = 55.0
	camera.position = Vector3(0.0, 1.35, 3.1)
	world.add_child(camera)
	camera.look_at(Vector3(0.55, 0.9, -1.0), Vector3.UP)
	camera.current = true


# --- UI ---------------------------------------------------------------------

## Bitmap-ish text: a monospace system face with every smoothing feature
## switched off, so glyph edges land on hard pixel boundaries.
##
## The web export has no access to system fonts, so none of these names
## resolve there -- hence the explicit theme-font fallback, which keeps the
## menu legible and merely loses the crisp aliased edges.
func _retro_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Press Start 2P", "Consolas", "Courier New", "monospace",
	])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.hinting = TextServer.HINTING_NONE
	font.multichannel_signed_distance_field = false
	var fallbacks: Array[Font] = []
	if ThemeDB.fallback_font:
		fallbacks.append(ThemeDB.fallback_font)
	font.fallbacks = fallbacks
	return font


func _make_label(parent: Node, text: String, size: int, color: Color, pos: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.position = pos
	parent.add_child(label)
	return label


## Sixty-four-bit console vibes: a big chunky title with each letter in its
## own bright color (the classic fourth-gen logo treatment) over the open
## dusk scene, and only the essentials beneath it -- tagline, hi-score,
## blinking PRESS START. No cabinet bezel, no corner chrome.
func _build_ui() -> void:
	_font = _retro_font()
	var ui := CanvasLayer.new()
	add_child(ui)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	var top := viewport_size.y * 0.24
	# Same treatment as the LOADING card: white type over a hot pink
	# drop shadow.
	var title := _make_label(ui, "CRANBOARDIN", 76, Color(1, 1, 1), Vector2(58, top))
	title.add_theme_color_override("font_shadow_color", NEON_PINK)
	title.add_theme_constant_override("shadow_offset_x", 7)
	title.add_theme_constant_override("shadow_offset_y", 7)

	# Persistent best from past sessions, zero-padded arcade style.
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK and int(cfg.get_value("best", "score", 0)) > 0:
		_make_label(ui, "HI-SCORE %06d   LV %02d" % [
					int(cfg.get_value("best", "score", 0)),
					int(cfg.get_value("best", "level", 1)),
				], 18, NEON_PURPLE, Vector2(62, top + 120))

	_prompt = _make_label(ui, ">> PRESS START <<", 26, Color(1, 1, 1), Vector2(62, top + 168))
	_prompt.add_theme_color_override("font_shadow_color", NEON_PINK)
	_prompt.add_theme_constant_override("shadow_offset_x", 3)
	_prompt.add_theme_constant_override("shadow_offset_y", 3)

	_build_scoring_card(ui, top + 212.0)


## Arcade-manual scoring table under the start prompt: how every point in
## the game is earned, straight from main.gd's SCORE_* values, plus the
## combo rule. Teal move names, white points, monospace-aligned columns,
## all on a translucent black plate so the rows stay legible over the
## glowing road behind them.
func _build_scoring_card(ui: CanvasLayer, y: float) -> void:
	var rows: Array = [
		["LAND A TRICK", "150"],
		["JUMP OVER AN ENEMY", "200"],
		["SLIP UNDER A DRONE", "150"],
		["HURDLE A BARRIER", "100"],
		["NEAR MISS", "75"],
		["SMASH WHILE BOOSTING", "125"],
		["BOOST PAD / MEGA PAD", "50/125"],
		["HIT A RAMP", "75"],
		["FINISH THE RUN", "500"],
	]
	var card_height := 34.0 + rows.size() * 20.0 + 8.0 + 20.0 + 22.0
	# On a window too short for the full table, keep the postcard clean
	# rather than running the rows off the bottom edge.
	if get_viewport().get_visible_rect().size.y - y < card_height:
		return

	var plate := ColorRect.new()
	plate.color = Color(CRT_BLACK, 0.6)
	plate.position = Vector2(50.0, y - 10.0)
	plate.size = Vector2(420.0, card_height)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(plate)

	_make_label(ui, "HOW TO SCORE", 20, NEON_CYAN, Vector2(62, y))
	y += 34.0
	for row: Array in rows:
		_make_label(ui, row[0], 14, NEON_TEAL, Vector2(62, y))
		_make_label(ui, row[1], 14, Color(1, 1, 1), Vector2(388, y))
		y += 20.0
	y += 8.0
	_make_label(ui, "CHAIN MOVES TO BUILD A x5 COMBO", 14, NEON_PURPLE, Vector2(62, y))


## A whisper of screen dressing instead of the old CRT scanline comb: just
## a soft corner vignette, like a console-era TV without the mask.
func _build_crt_overlay() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode blend_mix;

uniform float vignette_alpha = 0.4;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float a = smoothstep(0.4, 0.9, length(d) * 1.28) * vignette_alpha;
	COLOR = vec4(vec3(0.02, 0.0, 0.05), a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader

	var overlay := ColorRect.new()
	overlay.material = mat
	overlay.color = Color(1, 1, 1)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.position = Vector2.ZERO
	overlay.size = get_viewport().get_visible_rect().size

	var layer := CanvasLayer.new()
	layer.layer = 10  # above the UI layer
	layer.add_child(overlay)
	add_child(layer)


func _start_music() -> void:
	var stream := load("res://audio/menu_music.wav") as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = -9.0
	_music.autoplay = true
	add_child(_music)
	_music.play()
