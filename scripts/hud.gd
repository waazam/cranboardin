extends CanvasLayer
## Code-built HUD: speed/time/level readout, a health bar, hill-progress
## bar, hit flash message, fading control hint, and an end panel used for
## both "level complete" and "game over". Connected to Player signals by
## Main.

var player  # untyped; assigned by Main

var speed_label: Label
var timer_label: Label
var level_label: Label
var hp_bar_bg: ColorRect
var hp_bar_fill: ColorRect
var progress_bg: ColorRect
var progress_fill: ColorRect
var message_label: Label
var hint_label: Label
var results_layer: Control
var results_label: Label

var elapsed_time: float = 0.0
var running: bool = true
var _message_timer: float = 0.0
var _hint_timer: float = 4.0


func _ready() -> void:
	_build_ui()


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

	message_label = _make_label("", 34, Color(1, 0.35, 0.3))
	message_label.visible = false
	message_label.position = Vector2(viewport_size.x * 0.5 - 110, viewport_size.y * 0.3)
	add_child(message_label)

	hint_label = _make_label("WASD steer / accelerate / brake   -   SPACE jump over zombies   -   R restart", 16, Color(1, 1, 1, 0.85))
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

	results_label = _make_label("", 26, Color(1, 1, 1))
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	results_label.size = Vector2(480, 260)
	results_label.position = Vector2((viewport_size.x - 480) * 0.5, (viewport_size.y - 260) * 0.5)
	results_layer.add_child(results_label)


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

	if _message_timer > 0.0:
		_message_timer -= delta
		message_label.modulate.a = clampf(_message_timer / 0.4, 0.0, 1.0)
		if _message_timer <= 0.0:
			message_label.visible = false

	if _hint_timer > 0.0:
		_hint_timer -= delta
		hint_label.modulate.a = clampf(_hint_timer / 1.0, 0.0, 1.0)
		if _hint_timer <= 0.0:
			hint_label.visible = false


func _on_player_damaged(health: int) -> void:
	if health > 0:
		_flash_message("ZOMBIE HIT!", Color(1, 0.35, 0.3))


func flash_pickup(health: int) -> void:
	if player and health > player.max_health:
		_flash_message("CRANBERRY OVERDRIVE!", Color(0.9, 0.45, 0.6))
	else:
		_flash_message("+HP!", Color(0.9, 0.45, 0.6))


func show_level_complete(level: int, time: float, top_speed: float) -> void:
	running = false
	results_label.text = "LEVEL %d COMPLETE!\n\nTime: %.1fs\nTop Speed: %d\n\nPress R for level %d" \
			% [level, time, int(top_speed * 3.6), level + 1]
	results_layer.visible = true


func show_game_over(level: int) -> void:
	running = false
	results_label.text = "GAME OVER\n\nThe horde got you on level %d.\n\nPress R to try again" % level
	results_layer.visible = true


func _flash_message(text: String, color: Color = Color(1, 0.35, 0.3)) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.visible = true
	message_label.modulate.a = 1.0
	_message_timer = 1.2


func reset(level: int) -> void:
	elapsed_time = 0.0
	running = true
	results_layer.visible = false
	message_label.visible = false
	_message_timer = 0.0
	_hint_timer = 4.0
	hint_label.visible = true
	hint_label.modulate.a = 1.0
	level_label.text = "Level %d" % level
