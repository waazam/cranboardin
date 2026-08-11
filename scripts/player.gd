extends CharacterBody3D
## Spline-space skater controller. The player's gameplay state is
## (s, lateral, height): distance down the road, offset across it, and
## height above the surface. Each tick that state is mapped to a world
## transform through Track.transform_at, so the player follows the curved
## road exactly -- no physics solves, no wall collisions to tune.
##
## Speed still ramps from base_speed to max_speed with progress down the
## hill; WASD steers/accelerates/brakes and Space jumps (with coyote time
## and jump buffering). Zombies call take_damage(); at zero health the
## run ends (Death01 + died signal). Reaching the end of the road emits
## finished.

signal damaged(health: int)
signal died()
signal jumped()
signal tricked(trick_name: String)
signal finished(time: float, top_speed: float)

enum RunState { RUNNING, DEAD, FINISHED }

# --- Tuning ---------------------------------------------------------------
@export var base_speed: float = 7.0
@export var max_speed: float = 27.0
@export var accel_boost: float = 6.0
@export var brake_strength: float = 7.0
@export var speed_response: float = 18.0
@export var steer_speed: float = 9.0
@export var steer_response: float = 30.0
@export var jump_velocity: float = 8.5
@export var gravity: float = 22.0
@export var max_health: int = 100
@export var overheal_cap: int = 150
@export var hit_speed_multiplier: float = 0.45
@export var invulnerable_duration: float = 1.3
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12

# --- Spline-space state -----------------------------------------------------
var s: float = 0.0
var lateral: float = 0.0
var height: float = 0.0
var _vertical_velocity: float = 0.0

var current_speed: float = 0.0
var health: int = 100
var top_speed: float = 0.0
var elapsed: float = 0.0
var run_state: RunState = RunState.RUNNING

var _track: Node3D
## Duck-typed HUD ref (set by Main); provides get_touch_steer() and
## consume_touch_jump() on mobile, null-safe on desktop.
var touch_controls = null
var _invulnerable_timer: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _lateral_velocity: float = 0.0
var _lean_amount: float = 0.0

## Air tricks alternate per jump: kickflip (board-only roll, handled by
## Skateboard) then 360 spin (whole rig yaws, handled here).
var _trick_index: int = 0
var _spin_duration: float = 0.7
var _spin_time_left: float = 0.0

## Visual rig: `visuals` is the tuck/blink pivot; board and rider are
## separate entities beneath it (skateboard.gd / character.gd).
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
	_track = track
	reset_run()


func reset_run() -> void:
	s = 0.0
	lateral = 0.0
	height = 0.0
	_vertical_velocity = 0.0
	current_speed = base_speed
	health = max_health
	top_speed = base_speed
	elapsed = 0.0
	run_state = RunState.RUNNING
	_invulnerable_timer = 0.0
	_lateral_velocity = 0.0
	_lean_amount = 0.0
	visuals.visible = true
	visuals.rotation = Vector3.ZERO
	skateboard.rotation = Vector3.ZERO
	skateboard.finish_trick()
	skateboard.set_carve(0.0)
	_trick_index = 0
	_spin_time_left = 0.0
	character.reset()
	_apply_transform()


func get_progress() -> float:
	if _track == null or _track.arc_length <= 0.0:
		return 0.0
	return clampf(s / _track.arc_length, 0.0, 1.0)


func get_speed_ratio() -> float:
	return clampf(current_speed / max_speed, 0.0, 1.0)


var _jump_held_prev: bool = false


## Polled (not event-driven) so it works identically inside the pixelation
## SubViewport, where input events don't reliably propagate.
func _poll_jump_input() -> void:
	var jump_held := Input.is_physical_key_pressed(KEY_SPACE)
	if jump_held and not _jump_held_prev:
		_jump_buffer_timer = jump_buffer_time
	_jump_held_prev = jump_held
	if touch_controls and touch_controls.consume_touch_jump():
		_jump_buffer_timer = jump_buffer_time


func _physics_process(delta: float) -> void:
	if _track == null:
		return
	if run_state != RunState.RUNNING:
		# Dead: frozen. Finished: glide to a stop past the line.
		if run_state == RunState.FINISHED and current_speed > 0.1:
			current_speed = move_toward(current_speed, 0.0, 9.0 * delta)
			s = minf(s + current_speed * delta, _track.arc_length)
			_apply_transform()
		return

	elapsed += delta
	_update_invulnerability(delta)
	_poll_jump_input()

	var grounded := height <= 0.001
	_coyote_timer = coyote_time if grounded else _coyote_timer - delta
	_jump_buffer_timer -= delta

	var steer_input := _steer_axis()
	_update_speed(delta)
	_lateral_velocity = move_toward(_lateral_velocity, steer_input * steer_speed, steer_response * delta)

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_vertical_velocity = jump_velocity
		height = maxf(height, 0.002)
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		grounded = false
		_start_trick()
		jumped.emit()
	elif not grounded:
		_vertical_velocity -= gravity * delta
	else:
		_vertical_velocity = 0.0
		height = 0.0

	height = maxf(height + _vertical_velocity * delta, 0.0)
	s += current_speed * delta
	lateral = clampf(lateral + _lateral_velocity * delta,
			-_track.road_width * 0.5 + 0.7, _track.road_width * 0.5 - 0.7)

	_apply_transform()
	_update_lean(steer_input, delta)
	_update_trick(delta, height <= 0.001)
	skateboard.update_roll(current_speed, delta)
	character.update_motion(height <= 0.001)

	if s >= _track.arc_length:
		_finish()


func _apply_transform() -> void:
	var xf: Transform3D = _track.transform_at(s, lateral)
	global_transform = Transform3D(xf.basis, xf.origin + xf.basis.y * height)


func _steer_axis() -> float:
	var axis := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		axis -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		axis += 1.0
	if touch_controls:
		axis += touch_controls.get_touch_steer()
	return clampf(axis, -1.0, 1.0)


func _update_speed(delta: float) -> void:
	# One accelerate/brake axis merging keyboard and the touch d-pad.
	var accel_axis := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		accel_axis += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		accel_axis -= 1.0
	if touch_controls:
		accel_axis += touch_controls.get_touch_accel()
	accel_axis = clampf(accel_axis, -1.0, 1.0)

	var target_speed: float = lerp(base_speed, max_speed, get_progress())
	target_speed += accel_boost * maxf(accel_axis, 0.0)
	target_speed -= brake_strength * maxf(-accel_axis, 0.0)
	target_speed = clampf(target_speed, base_speed * 0.5, max_speed + accel_boost)
	current_speed = move_toward(current_speed, target_speed, speed_response * delta)
	current_speed = maxf(current_speed, 1.0)
	top_speed = maxf(top_speed, current_speed)


func _update_invulnerability(delta: float) -> void:
	if _invulnerable_timer > 0.0:
		_invulnerable_timer -= delta
		visuals.visible = fmod(_invulnerable_timer, 0.16) > 0.08
	else:
		visuals.visible = true


## Steering lean: the board rolls into the carve and the rider's spine
## bends into it (via LeanModifier); the rig itself only pitches into a
## speed tuck.
func _update_lean(steer_input: float, delta: float) -> void:
	_lean_amount = lerpf(_lean_amount, steer_input, 10.0 * delta)
	skateboard.set_carve(-_lean_amount * 0.22)
	character.set_lean(_lean_amount * 0.45)
	var target_pitch := -0.1 - get_speed_ratio() * 0.15
	visuals.rotation.x = lerp_angle(visuals.rotation.x, target_pitch, 6.0 * delta)


func _start_trick() -> void:
	_trick_index += 1
	if _trick_index % 2 == 1:
		skateboard.do_kickflip(0.5)
		tricked.emit("KICKFLIP!")
	else:
		_spin_time_left = _spin_duration
		tricked.emit("360 SPIN!")


## Runs the 360 spin and cancels tricks cleanly on landing.
func _update_trick(delta: float, grounded: bool) -> void:
	if grounded:
		if _spin_time_left > 0.0:
			_spin_time_left = 0.0
			visuals.rotation.y = 0.0
		skateboard.finish_trick()
		return
	if _spin_time_left > 0.0:
		_spin_time_left = maxf(_spin_time_left - delta, 0.0)
		visuals.rotation.y = TAU * (1.0 - _spin_time_left / _spin_duration) if _spin_time_left > 0.0 else 0.0


## Called by cranberry bottle pickups. Heals to max; if already at or
## above max, overheals up to overheal_cap.
func heal(amount: int) -> void:
	if run_state != RunState.RUNNING:
		return
	health = mini(health + amount, overheal_cap)


## Called by zombies on contact.
func take_damage(amount: int) -> void:
	if run_state != RunState.RUNNING or _invulnerable_timer > 0.0:
		return
	health = maxi(health - amount, 0)
	current_speed = maxf(base_speed * 0.6, current_speed * hit_speed_multiplier)
	_lateral_velocity *= 0.2
	_invulnerable_timer = invulnerable_duration
	if health <= 0:
		_die()
	else:
		character.play_crash()
		damaged.emit(health)


func _die() -> void:
	run_state = RunState.DEAD
	visuals.visible = true
	character.set_lean(0.0)
	character.play_death()
	damaged.emit(0)
	died.emit()


func _finish() -> void:
	run_state = RunState.FINISHED
	character.set_lean(0.0)
	character.play_finish()
	finished.emit(elapsed, top_speed)
