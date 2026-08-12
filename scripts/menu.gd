extends Node3D
## Main menu: the rider stands in the neon dusk (Idle anim), sunglasses
## bone-attached to his head, palm resting on his upright board, with the
## procedural city backdrop behind him and its own dreamy synth theme.
## Any key / click / tap starts the game.

const MODEL_SCENE := preload("res://Godot/AnimationLibrary_Godot_Standard.glb")
const GAME_SCENE := "res://scenes/main.tscn"
const SAVE_PATH := "user://save.cfg"  # written by main.gd

@onready var viewport_frame: SubViewportContainer = $ViewportFrame
@onready var world: Node3D = $ViewportFrame/SubViewport/World

## Arcade palette: hot magenta, cyan, marquee gold, CRT phosphor black.
const NEON_PINK := Color(1.0, 0.29, 0.66)
const NEON_CYAN := Color(0.36, 0.95, 0.98)
const NEON_GOLD := Color(1.0, 0.78, 0.32)
const CRT_BLACK := Color(0.05, 0.02, 0.09)

var _music: AudioStreamPlayer
var _font: SystemFont
var _prompt: Label
var _prompt_time: float = 0.0
var _starting: bool = false


func _ready() -> void:
	if _is_mobile():
		viewport_frame.stretch_shrink = 6

	_build_stage()
	_build_character()
	_build_camera()
	_build_ui()
	_build_crt_overlay()
	_start_music()


static func _is_mobile() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") \
			or OS.has_feature("android") or OS.has_feature("ios")


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


func _start_game() -> void:
	if _starting:
		return
	_starting = true
	get_tree().change_scene_to_file(GAME_SCENE)


# --- Stage ------------------------------------------------------------------

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


func _build_character() -> void:
	var model := MODEL_SCENE.instantiate() as Node3D
	model.scale = Vector3.ONE * 0.9
	# glTF models face +Z; camera sits at +Z, so he faces the viewer.
	model.position = Vector3(0.95, 0, 0)
	world.add_child(model)

	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		anim.play(&"Idle")

	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		_attach_sunglasses(skeleton)

	_place_board()


## Sunglasses: a dark visor bar riding the head bone, so it follows the
## Idle animation's sway.
func _attach_sunglasses(skeleton: Skeleton3D) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "DEF-head"
	skeleton.add_child(attachment)

	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.17, 0.045, 0.02)
	visor.mesh = visor_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.05)
	mat.roughness = 0.15
	visor.mesh = visor_mesh
	visor.material_override = mat
	# Offset guessed from the head bone origin; verified via screenshot.
	visor.position = Vector3(0, 0.08, 0.1)
	attachment.add_child(visor)

	for side in [-1.0, 1.0]:
		var temple := MeshInstance3D.new()
		var temple_mesh := BoxMesh.new()
		temple_mesh.size = Vector3(0.01, 0.012, 0.09)
		temple.mesh = temple_mesh
		temple.material_override = mat
		temple.position = Vector3(side * 0.083, 0.08, 0.055)
		attachment.add_child(temple)


## The board stands upright beside him, tail on the ground, nose under
## his right palm, angled so its profile reads to the camera.
func _place_board() -> void:
	var board := Skateboard.new()
	# Its gameplay _physics_process would stomp the pose every frame.
	board.set_physics_process(false)
	board.position = Vector3(0.42, 0.425, 0.15)
	board.basis = Basis(Vector3.UP, -1.1) * Basis(Vector3.RIGHT, -PI * 0.5)
	world.add_child(board)


func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.fov = 55.0
	camera.position = Vector3(0.0, 1.35, 3.1)
	world.add_child(camera)
	camera.look_at(Vector3(0.55, 1.0, 0.0), Vector3.UP)
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


func _build_ui() -> void:
	_font = _retro_font()
	var ui := CanvasLayer.new()
	add_child(ui)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	_build_bezel(ui, viewport_size)

	# Cabinet header, split to the two top corners.
	_make_label(ui, "CRANBOARD CO.", 14, NEON_CYAN * Color(1, 1, 1, 0.75), Vector2(34, 26))
	_make_label(ui, "CREDIT 01", 14, NEON_GOLD, Vector2(viewport_size.x - 132, 26))

	var top := viewport_size.y * 0.24

	# Title, printed four times: a hard black drop shadow for arcade weight,
	# then cyan/magenta fringes peeking out either side of the core --
	# cheap chromatic aberration, the way a misconverged CRT does it.
	var title_pos := Vector2(58, top)
	_make_label(ui, "CRANBOARDIN", 76, CRT_BLACK, title_pos + Vector2(7, 7))
	_make_label(ui, "CRANBOARDIN", 76, NEON_CYAN, title_pos + Vector2(-4, 0))
	_make_label(ui, "CRANBOARDIN", 76, NEON_PINK, title_pos + Vector2(4, 0))
	_make_label(ui, "CRANBOARDIN", 76, Color(1.0, 0.86, 0.95), title_pos)

	_make_label(ui, "SKATE . DODGE . SURVIVE", 22, NEON_CYAN, Vector2(62, top + 96))

	# Persistent best from past sessions, zero-padded arcade style.
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK and int(cfg.get_value("best", "score", 0)) > 0:
		_make_label(ui, "HI-SCORE %06d   LV %02d" % [
					int(cfg.get_value("best", "score", 0)),
					int(cfg.get_value("best", "level", 1)),
				], 18, NEON_GOLD, Vector2(62, top + 140))

	_prompt = _make_label(ui, ">> PRESS START <<", 26, Color(1, 1, 1), Vector2(62, top + 184))
	_prompt.add_theme_color_override("font_shadow_color", NEON_PINK)
	_prompt.add_theme_constant_override("shadow_offset_x", 3)
	_prompt.add_theme_constant_override("shadow_offset_y", 3)

	var hint := "TAP SCREEN" if _is_mobile() else "ANY KEY OR CLICK"
	_make_label(ui, hint, 14, Color(1, 1, 1, 0.5), Vector2(62, top + 222))

	_make_label(ui, "(C) 1989 CRANBOARD CO.", 14, Color(1, 1, 1, 0.4),
			Vector2(34, viewport_size.y - 44))

	# Version stamp, bottom-right, barely-there.
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	if ver != "":
		_make_label(ui, "V" + ver, 14, Color(1, 1, 1, 0.4),
				Vector2(viewport_size.x - 132, viewport_size.y - 44))


## Double neon rule around the screen edge -- the cabinet bezel.
func _build_bezel(ui: CanvasLayer, viewport_size: Vector2) -> void:
	# inset px, border px, colour -- outer magenta rule, inner cyan hairline.
	var rules: Array[Array] = [
		[14.0, 3, Color(NEON_PINK, 0.85)],
		[22.0, 2, Color(NEON_CYAN, 0.55)],
	]
	for rule in rules:
		var inset: float = rule[0]
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.set_border_width_all(rule[1])
		box.border_color = rule[2]
		box.set_corner_radius_all(0)
		var panel := Panel.new()
		panel.add_theme_stylebox_override("panel", box)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = Vector2(inset, inset)
		panel.size = viewport_size - Vector2(inset, inset) * 2.0
		ui.add_child(panel)


## Full-screen CRT pass over everything: scanline comb, corner vignette,
## a slow rolling refresh band, and a faint mains flicker.
func _build_crt_overlay() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode blend_mix;

uniform float line_count = 216.0;
uniform float scan_alpha = 0.28;
uniform float grille_alpha = 0.10;
uniform float vignette_alpha = 0.55;
uniform float flicker_alpha = 0.02;

void fragment() {
	// Every other chunky row gets dimmed -- the scanline comb.
	float a = step(0.5, fract(UV.y * line_count)) * scan_alpha;

	// Aperture grille: faint vertical stripes, one per rendered column,
	// crossing the scanlines into a visible pixel mask.
	a = max(a, step(0.5, fract(UV.x * line_count * 1.78)) * grille_alpha);

	// Round off the corners like a glass tube.
	vec2 d = UV - vec2(0.5);
	a = max(a, smoothstep(0.34, 0.82, length(d) * 1.28) * vignette_alpha);

	// Mains hum, always dimming a touch, never brightening.
	a += (0.5 + 0.5 * sin(TIME * 7.0)) * flicker_alpha;

	// Refresh band drifting up the tube, the one thing that lightens.
	vec3 tint = vec3(0.02, 0.0, 0.05);
	float band = smoothstep(0.90, 1.0, fract(UV.y - TIME * 0.06));
	tint = mix(tint, vec3(0.55, 0.85, 1.0), band);
	a = max(a, band * 0.07);

	COLOR = vec4(tint, clamp(a, 0.0, 1.0));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	# One scanline per rendered pixel row, so the comb lines up with the
	# 3D viewport's own pixelation (1/4 desktop, 1/6 mobile).
	mat.set_shader_parameter("line_count", viewport_size.y / float(viewport_frame.stretch_shrink))

	var overlay := ColorRect.new()
	overlay.material = mat
	overlay.color = Color(1, 1, 1)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.position = Vector2.ZERO
	overlay.size = viewport_size

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
