extends Node3D
## Assembles the scene: hands the Track's geometry to the Player, points the
## camera and background at the Player, wires HUD signals, and handles the
## global restart key.

@onready var background = $Background
@onready var track = $Track
@onready var player = $Player
@onready var camera_rig = $CameraRig
@onready var hud = $HUD


func _ready() -> void:
	player.setup(track)
	camera_rig.target = player
	camera_rig.snap_to_target()
	background.set_follow_target(player)
	hud.player = player

	player.crashed.connect(hud._on_player_crashed)
	player.finished.connect(hud._on_player_finished)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		_restart()


func _restart() -> void:
	track.regenerate_obstacles()
	player.reset_run()
	camera_rig.snap_to_target()
	hud.reset()
