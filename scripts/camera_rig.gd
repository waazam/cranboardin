extends Node3D
## Smoothed third-person chase camera. Trails behind/above `target` (the
## Player) and looks slightly ahead/down the hill so incoming obstacles are
## readable. FOV widens with speed as a cheap sense-of-velocity cue.

@export var follow_offset := Vector3(0, 4.5, 8.0)
@export var look_offset := Vector3(0, 1.4, -8.0)
@export var follow_smoothing := 6.0
@export var base_fov := 70.0
@export var max_fov := 88.0

var target  # assigned by Main; left untyped for duck-typed property access
var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	add_child(camera)
	camera.fov = base_fov
	camera.current = true
	camera.near = 0.1
	camera.far = 500.0


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var desired_pos: Vector3 = target.global_position + follow_offset
	var t: float = clamp(follow_smoothing * delta, 0.0, 1.0)
	global_position = global_position.lerp(desired_pos, t)
	look_at(target.global_position + look_offset, Vector3.UP)

	var speed_ratio: float = clamp(target.current_speed / max(target.max_speed, 0.01), 0.0, 1.0)
	camera.fov = lerp(base_fov, max_fov, speed_ratio)


func snap_to_target() -> void:
	if target == null:
		return
	global_position = target.global_position + follow_offset
	look_at(target.global_position + look_offset, Vector3.UP)
