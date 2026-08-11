extends CharacterBody3D
## Third-person skater controller.
##
## Forward/downhill motion is speed-driven (not emergent slope physics) so the
## "gains speed toward the bottom" pacing can be tuned precisely: current_speed
## ramps from base_speed to max_speed as a function of progress down the hill.
## WASD steers/accelerates/brakes; Space jumps (with coyote time + jump buffering).

signal crashed(count: int)
signal boosted()
signal finished(time: float, top_speed: float, crashes: int)

# --- Tuning ---------------------------------------------------------------
@export var base_speed: float = 6.0
@export var max_speed: float = 26.0
@export var accel_boost: float = 4.0        # extra target speed while holding W
@export var brake_strength: float = 7.0     # target speed reduction while holding S
@export var speed_response: float = 12.0    # how fast current_speed chases target_speed
@export var steer_speed: float = 9.0        # lateral units/sec at full A/D
@export var steer_response: float = 30.0
@export var jump_velocity: float = 8.5
@export var boost_velocity: float = 11.0
@export var gravity: float = 22.0
@export var crash_speed_multiplier: float = 0.4
@export var invulnerable_duration: float = 1.0
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12

# --- Track reference data (assigned by Track via setup()) -----------------
var forward_tangent: Vector3 = Vector3(0, -0.25, -0.97)
var track_length: float = 400.0
var track_half_width: float = 6.0
var start_position: Vector3 = Vector3.ZERO

# --- Runtime state ----------------------------------------------------------
var current_speed: float = 0.0
var crash_count: int = 0
var top_speed: float = 0.0
var elapsed: float = 0.0
var run_finished: bool = false

var _invulnerable_timer: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _lateral_velocity: float = 0.0

## Visual rig: `visuals` is the lean/blink pivot; the board and rider are
## two separate entities beneath it (see skateboard.gd / character.gd).
var visuals: Node3D
var skateboard: Skateboard
var character: Character


func _ready() -> void:
	add_to_group("player")
	visuals = Node3D.new()
	visuals.name = "Visuals"
	add_child(visuals)

	skateboard = Skateboard.new()
	skateboard.name = "Skateboard"
	visuals.add_child(skateboard)

	character = Character.new()
	character.name = "Character"
	character.stand_height = Skateboard.DECK_TOP_HEIGHT
	visuals.add_child(character)


func setup(track: Node3D) -> void:
	forward_tangent = track.forward_tangent
	track_length = track.track_length
	track_half_width = track.track_width * 0.5 - 0.6
	start_position = track.start_position
	reset_run()


func reset_run() -> void:
	global_position = start_position
	velocity = Vector3.ZERO
	current_speed = base_speed
	crash_count = 0
	top_speed = base_speed
	elapsed = 0.0
	run_finished = false
	_invulnerable_timer = 0.0
	_lateral_velocity = 0.0
	visuals.visible = true
	visuals.rotation = Vector3.ZERO
	character.reset()


func get_progress() -> float:
	var end_z := forward_tangent.z * track_length
	if is_zero_approx(end_z):
		return 0.0
	return clamp(global_position.z / end_z, 0.0, 1.0)


func get_speed_ratio() -> float:
	return clamp(current_speed / max_speed, 0.0, 1.0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		_jump_buffer_timer = jump_buffer_time


func _physics_process(delta: float) -> void:
	if run_finished:
		velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		move_and_slide()
		return

	elapsed += delta
	_update_invulnerability(delta)

	var grounded := is_on_floor()
	_coyote_timer = coyote_time if grounded else _coyote_timer - delta
	_jump_buffer_timer -= delta

	var steer_input := _steer_axis()
	_update_speed(delta)
	_lateral_velocity = move_toward(_lateral_velocity, steer_input * steer_speed, steer_response * delta)

	var wants_jump := _jump_buffer_timer > 0.0 and _coyote_timer > 0.0
	if wants_jump:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
	elif grounded:
		var tangent_velocity := forward_tangent * current_speed
		velocity.y = tangent_velocity.y
		velocity.z = tangent_velocity.z
	else:
		velocity.y -= gravity * delta
		velocity.z = forward_tangent.z * current_speed

	velocity.x = _lateral_velocity

	move_and_slide()
	global_position.x = clamp(global_position.x, -track_half_width, track_half_width)

	_update_lean(steer_input, delta)
	skateboard.update_roll(current_speed, delta)
	character.update_motion(is_on_floor())

	if get_progress() >= 1.0:
		_finish()


func _steer_axis() -> float:
	var axis := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		axis -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		axis += 1.0
	return axis


func _update_speed(_delta: float) -> void:
	var target_speed: float = lerp(base_speed, max_speed, get_progress())
	if Input.is_physical_key_pressed(KEY_W):
		target_speed += accel_boost
	if Input.is_physical_key_pressed(KEY_S):
		target_speed -= brake_strength
	target_speed = clamp(target_speed, base_speed * 0.5, max_speed + accel_boost)
	current_speed = move_toward(current_speed, target_speed, speed_response * _delta)
	current_speed = max(current_speed, 1.0)
	top_speed = max(top_speed, current_speed)


func _update_invulnerability(delta: float) -> void:
	if _invulnerable_timer > 0.0:
		_invulnerable_timer -= delta
		visuals.visible = fmod(_invulnerable_timer, 0.16) > 0.08
	else:
		visuals.visible = true


func _update_lean(steer_input: float, delta: float) -> void:
	var target_roll := -steer_input * 0.35
	var target_pitch := -0.12 - get_speed_ratio() * 0.18
	visuals.rotation.z = lerp_angle(visuals.rotation.z, target_roll, 10.0 * delta)
	visuals.rotation.x = lerp_angle(visuals.rotation.x, target_pitch, 6.0 * delta)


## Called by hazard obstacles (Area3D) when the player enters them.
func register_crash() -> void:
	if run_finished or _invulnerable_timer > 0.0:
		return
	crash_count += 1
	current_speed = max(base_speed * 0.6, current_speed * crash_speed_multiplier)
	_lateral_velocity *= 0.2
	_invulnerable_timer = invulnerable_duration
	character.play_crash()
	crashed.emit(crash_count)


## Called by boost-ramp obstacles (Area3D) when the player enters them.
func apply_boost() -> void:
	if run_finished:
		return
	velocity.y = boost_velocity
	_coyote_timer = 0.0
	boosted.emit()


func _finish() -> void:
	run_finished = true
	character.play_finish()
	finished.emit(elapsed, top_speed, crash_count)
