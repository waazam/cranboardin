extends CanvasLayer
## Code-built HUD: speed/time/level readout, a health bar, hill-progress
## bar, hit flash message, fading control hint, and an end panel used for
## both "level complete" and "game over". Connected to Player signals by
## Main.
##
## On mobile (Android/iOS, native or web) it also builds translucent
## touch buttons -- a steer/accelerate/brake d-pad plus a jump button --
## and the end panels respond to a tap instead of the R key. Desktop
## keeps keyboard controls and never sees the buttons.

signal restart_requested()

## Force the touch buttons on (useful for testing or touch laptops).
@export var force_touch_controls: bool = false

var player  # untyped; assigned by Main

var _btn_left: TouchScreenButton
var _btn_right: TouchScreenButton
var _btn_up: TouchScreenButton
var _btn_down: TouchScreenButton
var _btn_jump: TouchScreenButton
var _jump_queued: bool = false

var speed_label: Label
var timer_label: Label
var level_label: Label
var score_label: Label
var combo_label: Label
var _score_flash: float = 0.0
var hp_bar_bg: ColorRect
var hp_bar_fill: ColorRect
var progress_bg: ColorRect
var progress_fill: ColorRect
var hint_label: Label
var results_layer: Control
var results_label: Label

var elapsed_time: float = 0.0
var running: bool = true
var _hint_timer: float = 4.0


func _ready() -> void:
	_build_ui()
	if is_mobile() or force_touch_controls:
		_build_touch_controls()


static func is_mobile() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") \
			or OS.has_feature("android") or OS.has_feature("ios")


func _build_ui() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	var stats_box := VBoxContainer.new()
	stats_box.position = Vector2(20, 16)
	stats_box.add_theme_constant_override("separation", 4)
	add_child(stats_box)

	speed_label = _make_label("Speed: 0", 22, Color(1, 1, 1))
	stats_box.add_child(speed_label)
	timer_label = _make_label("Time: 0.0", 18, Color(0.9, 0.9, 0.9))
	stats_box.add_child(timer_label)
	level_label = _make_label("Level 1", 18, Color(0.5, 0.92, 0.95))
	stats_box.add_child(level_label)

	# Score readout top-right; combo multiplier beneath it in accent pink.
	score_label = _make_label("Score: 0", 22, Color(1, 1, 1))
	score_label.size = Vector2(220, 30)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.position = Vector2(viewport_size.x - 240, 16)
	add_child(score_label)

	combo_label = _make_label("", 18, Color(1.0, 0.42, 0.7))
	combo_label.size = Vector2(220, 26)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_label.position = Vector2(viewport_size.x - 240, 46)
	combo_label.visible = false
	add_child(combo_label)

	var hp_caption := _make_label("HP", 13, Color(1, 1, 1, 0.8))
	hp_caption.position = Vector2(20, 102)
	add_child(hp_caption)

	hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0, 0, 0, 0.45)
	hp_bar_bg.size = Vector2(180, 14)
	hp_bar_bg.position = Vector2(48, 104)
	add_child(hp_bar_bg)

	hp_bar_fill = ColorRect.new()
	hp_bar_fill.color = Color(0.45, 0.75, 0.4)
	hp_bar_fill.size = Vector2(180, 14)
	hp_bar_bg.add_child(hp_bar_fill)

	var bar_width := 320.0
	var bar_height := 16.0
	progress_bg = ColorRect.new()
	progress_bg.color = Color(0, 0, 0, 0.45)
	progress_bg.size = Vector2(bar_width, bar_height)
	progress_bg.position = Vector2((viewport_size.x - bar_width) * 0.5, 22)
	add_child(progress_bg)

	progress_fill = ColorRect.new()
	progress_fill.color = Color(1.0, 0.4, 0.7)
	progress_fill.size = Vector2(0, bar_height)
	progress_bg.add_child(progress_fill)

	var progress_caption := _make_label("HILL PROGRESS", 12, Color(1, 1, 1, 0.8))
	progress_caption.position = Vector2((viewport_size.x - bar_width) * 0.5, 4)
	add_child(progress_caption)

	var hint_text := "WASD steer / accelerate / brake   -   SPACE jump over zombies   -   R restart"
	if is_mobile() or force_touch_controls:
		hint_text = "Use the arrows   -   JUMP over zombies"
	hint_label = _make_label(hint_text, 16, Color(1, 1, 1, 0.85))
	hint_label.position = Vector2(viewport_size.x * 0.5 - 300, viewport_size.y - 40)
	add_child(hint_label)

	results_layer = Control.new()
	results_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_layer.visible = false
	add_child(results_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_layer.add_child(dim)
	# End panels restart on tap/click (the mobile equivalent of R).
	dim.gui_input.connect(_on_results_input)

	results_label = _make_label("", 26, Color(1, 1, 1))
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	results_label.size = Vector2(480, 260)
	results_label.position = Vector2((viewport_size.x - 480) * 0.5, (viewport_size.y - 260) * 0.5)
	results_layer.add_child(results_label)


func _on_results_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed)
	if tapped and results_layer.visible:
		# Hide first: mobile browsers synthesize a mouse event after the
		# touch event, and this guard keeps the pair from firing twice.
		results_layer.visible = false
		restart_requested.emit()


# --- Touch controls (mobile only) -------------------------------------------

func _build_touch_controls() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	# D-pad (plus layout) bottom-left: up/down = accelerate/brake,
	# left/right = steer. Jump stays big on the bottom-right.
	var cell := 108.0
	var margin := 24.0
	var col0 := margin
	var col1 := margin + cell
	var col2 := margin + cell * 2.0
	var row_bottom := viewport_size.y - margin - cell
	var row_mid := row_bottom - cell
	var row_top := row_mid - cell

	_btn_up = _make_touch_button(_make_button_texture("up", cell), Vector2(col1, row_top))
	_btn_left = _make_touch_button(_make_button_texture("left", cell), Vector2(col0, row_mid))
	_btn_right = _make_touch_button(_make_button_texture("right", cell), Vector2(col2, row_mid))
	_btn_down = _make_touch_button(_make_button_texture("down", cell), Vector2(col1, row_bottom))

	var jump_size := 150.0
	_btn_jump = _make_touch_button(_make_button_texture("jump", jump_size),
			Vector2(viewport_size.x - jump_size - 30.0, viewport_size.y - jump_size - 30.0))
	_btn_jump.pressed.connect(func() -> void: _jump_queued = true)


func _make_touch_button(texture: ImageTexture, pos: Vector2) -> TouchScreenButton:
	var btn := TouchScreenButton.new()
	btn.texture_normal = texture
	btn.position = pos
	# Sliding a thumb across the steer buttons should switch them.
	btn.passby_press = true
	add_child(btn)
	return btn


## Steering from the touch buttons: -1, 0, or 1.
func get_touch_steer() -> float:
	if _btn_left == null:
		return 0.0
	var steer := 0.0
	if _btn_left.is_pressed():
		steer -= 1.0
	if _btn_right.is_pressed():
		steer += 1.0
	return steer


## Accelerate/brake from the touch buttons: 1, 0, or -1.
func get_touch_accel() -> float:
	if _btn_up == null:
		return 0.0
	var accel := 0.0
	if _btn_up.is_pressed():
		accel += 1.0
	if _btn_down.is_pressed():
		accel -= 1.0
	return accel


## Edge-triggered jump request from the touch button.
func consume_touch_jump() -> bool:
	var queued := _jump_queued
	_jump_queued = false
	return queued


## A translucent circle with an arrow glyph.
func _make_button_texture(kind: String, size_px: float = 144.0) -> ImageTexture:
	var s := int(size_px)
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var center := s * 0.5
	var accent := Color(1.0, 0.55, 0.75)

	for px in s:
		for py in s:
			var d := Vector2(px - center, py - center).length() / center
			if d > 1.0:
				continue
			var col := Color(1, 1, 1, 0.16)
			if d > 0.86:
				col = Color(accent.r, accent.g, accent.b, 0.55)
			var fx := px / float(s)
			var fy := py / float(s)
			if _in_arrow(kind, fx, fy):
				col = Color(accent.r, accent.g, accent.b, 0.9)
			img.set_pixel(px, py, col)

	return ImageTexture.create_from_image(img)


func _in_arrow(kind: String, fx: float, fy: float) -> bool:
	match kind:
		"left":
			return fx >= 0.32 and fx <= 0.64 and absf(fy - 0.5) <= (fx - 0.32) * 0.62
		"right":
			return fx >= 0.36 and fx <= 0.68 and absf(fy - 0.5) <= (0.68 - fx) * 0.62
		"up", "jump":
			return fy >= 0.32 and fy <= 0.64 and absf(fx - 0.5) <= (fy - 0.32) * 0.62
		"down":
			return fy >= 0.36 and fy <= 0.68 and absf(fx - 0.5) <= (0.68 - fy) * 0.62
	return false


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _process(delta: float) -> void:
	if running:
		elapsed_time += delta

	if player:
		speed_label.text = "Speed: %d" % int(player.current_speed * 3.6)
		progress_fill.size.x = progress_bg.size.x * player.get_progress()
		var hp_ratio: float = float(player.health) / float(player.max_health)
		hp_bar_fill.size.x = hp_bar_bg.size.x * minf(hp_ratio, 1.0)
		if hp_ratio > 1.0:
			# Overhealed on cranberry juice: the bar goes full cranberry.
			hp_bar_fill.color = Color(0.62, 0.12, 0.28)
		else:
			hp_bar_fill.color = Color(0.45, 0.75, 0.4).lerp(Color(0.85, 0.3, 0.25), 1.0 - hp_ratio)

	timer_label.text = "Time: %.1f" % elapsed_time

	# Brief pink flash on the score label whenever points land.
	if _score_flash > 0.0:
		_score_flash -= delta
		score_label.add_theme_color_override("font_color",
				Color(1.0, 0.42, 0.7) if _score_flash > 0.0 else Color(1, 1, 1))

	if _hint_timer > 0.0:
		_hint_timer -= delta
		hint_label.modulate.a = clampf(_hint_timer / 1.0, 0.0, 1.0)
		if _hint_timer <= 0.0:
			hint_label.visible = false


## Called by Main whenever the score or combo changes; flash on gains.
func set_score(total: int, mult: int, flash: bool) -> void:
	score_label.text = "Score: %d" % total
	combo_label.visible = mult > 1
	combo_label.text = "COMBO x%d" % mult
	if flash:
		_score_flash = 0.25


func show_level_complete(level: int, time: float, top_speed: float, score: int) -> void:
	running = false
	results_label.text = "LEVEL %d COMPLETE!\n\nTime: %.1fs\nTop Speed: %d\nScore: %d\n\nPress R for level %d" \
			% [level, time, int(top_speed * 3.6), score, level + 1]
	results_layer.visible = true


func show_game_over(level: int, score: int) -> void:
	running = false
	results_label.text = "GAME OVER\n\nThe horde got you on level %d.\nScore: %d\n\nPress R to try again" \
			% [level, score]
	results_layer.visible = true


func reset(level: int) -> void:
	elapsed_time = 0.0
	running = true
	results_layer.visible = false
	_hint_timer = 4.0
	hint_label.visible = true
	hint_label.modulate.a = 1.0
	level_label.text = "Level %d" % level
