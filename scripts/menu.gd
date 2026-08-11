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

var _music: AudioStreamPlayer
var _prompt: Label
var _prompt_time: float = 0.0
var _starting: bool = false


func _ready() -> void:
	if _is_mobile():
		viewport_frame.stretch_shrink = 5

	_build_stage()
	_build_character()
	_build_camera()
	_build_ui()
	_start_music()


static func _is_mobile() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") \
			or OS.has_feature("android") or OS.has_feature("ios")


func _process(delta: float) -> void:
	# Blinking start prompt.
	_prompt_time += delta
	_prompt.visible = fmod(_prompt_time, 1.2) < 0.8


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

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	var title := Label.new()
	title.text = "CRANBOARDIN"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1.0, 0.42, 0.7))
	title.add_theme_color_override("font_shadow_color", Color(0.25, 0.85, 0.9, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.position = Vector2(60, viewport_size.y * 0.24)
	ui.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "skate. dodge. survive."
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.92, 0.95))
	subtitle.position = Vector2(64, viewport_size.y * 0.24 + 88)
	ui.add_child(subtitle)

	# Persistent best from past sessions, in the warm window-neon gold.
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK and int(cfg.get_value("best", "score", 0)) > 0:
		var best := Label.new()
		best.text = "best score: %d  -  reached level %d" \
				% [int(cfg.get_value("best", "score", 0)), int(cfg.get_value("best", "level", 1))]
		best.add_theme_font_size_override("font_size", 16)
		best.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
		best.position = Vector2(64, viewport_size.y * 0.24 + 126)
		ui.add_child(best)

	_prompt = Label.new()
	_prompt.text = "tap or press any key to skate"
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_prompt.position = Vector2(64, viewport_size.y * 0.24 + 162)
	ui.add_child(_prompt)


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
