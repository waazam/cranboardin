extends Node3D
## Smoothed third-person chase camera. Trails behind/above the target
## along the target's own heading (which turns with the curved road) and
## looks ahead down the path. FOV widens with speed.

@export var follow_distance := 8.0
@export var follow_height := 4.2
@export var look_ahead := 9.0
@export var look_height := 1.2
@export var follow_smoothing := 6.0
@export var base_fov := 70.0
@export var max_fov := 86.0

var target  # assigned by Main; left untyped for duck-typed property access
var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	add_child(camera)
	camera.fov = base_fov
	camera.current = true
	camera.near = 0.1
	camera.far = 600.0


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var t := clampf(follow_smoothing * delta, 0.0, 1.0)
	global_position = global_position.lerp(_desired_position(), t)
	look_at(_look_target(), Vector3.UP)

	var speed_ratio: float = clampf(target.current_speed / maxf(target.max_speed, 0.01), 0.0, 1.0)
	camera.fov = lerp(base_fov, max_fov, speed_ratio)


func snap_to_target() -> void:
	if target == null:
		return
	global_position = _desired_position()
	look_at(_look_target(), Vector3.UP)


func _forward() -> Vector3:
	var fwd: Vector3 = -target.global_basis.z
	return fwd.normalized()


func _desired_position() -> Vector3:
	return target.global_position - _forward() * follow_distance + Vector3.UP * follow_height


func _look_target() -> Vector3:
	return target.global_position + _forward() * look_ahead + Vector3.UP * look_height
