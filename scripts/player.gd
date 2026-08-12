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
signal trick_landed(trick_name: String)
signal finished(time: float, top_speed: float)

enum RunState { RUNNING, DEAD, FINISHED }

# --- Tuning ---------------------------------------------------------------
@export var base_speed: float = 9.0
@export var max_speed: float = 34.0
@export var accel_boost: float = 8.0
@export var brake_strength: float = 7.0
@export var speed_response: float = 22.0
@export var steer_speed: float = 10.5
@export var steer_response: float = 34.0
@export var jump_velocity: float = 8.5
@export var gravity: float = 22.0
# Health is whole hits: three and the run ends. Bottles restore one.
@export var max_health: int = 3
@export var overheal_cap: int = 3
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
var health: int = 3
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
## Pending trick name; cleared on landing (scores) or on a hit (voids).
var _active_trick: String = ""
## Boost pads grant a short window of extra target speed.
var _boost_timer: float = 0.0

## Visual rig: `visuals` is the tuck/blink pivot; board and rider are
## separate entities beneath it (skateboard.gd / character.gd).
var visuals: Node3D
var skateboard: Skateboard
var character: Character

## Wheel dust (continuous, thickens with speed) and impact sparks
## (one-shot burst fired by Main on smashes and boost pads). Both are
## additive unshaded quads in the neon palette -- cheap at low res.
var _dust: GPUParticles3D
var _sparks: GPUParticles3D


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

	_build_particles()


## Builds the two wheel emitters. World-space particles (local_coords off)
## so puffs/sparks stay planted on the road and streak behind the board.
## Counts stay tiny -- the whole scene renders at half res anyway.
func _build_particles() -> void:
	# One shared additive material; each emitter tints via process-material
	# color (vertex color), so no per-emitter material copies.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	# Shared fade: full brightness at birth, gone by end of life. Additive
	# blend scales by alpha, so this reads as a clean burn-out.
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade

	# Dust: low plume kicked up and back off the rear wheels, board-glow
	# pink so it reads as neon spray rather than dirt.
	_dust = GPUParticles3D.new()
	_dust.name = "WheelDust"
	_dust.amount = 20
	_dust.lifetime = 0.5
	_dust.local_coords = false
	_dust.amount_ratio = 0.0  # driven by speed each tick
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust.position = Vector3(0.0, 0.06, 0.45)  # just behind the rear truck
	var dust_pm := ParticleProcessMaterial.new()
	dust_pm.direction = Vector3(0.0, 0.55, 1.0)  # up and backwards
	dust_pm.spread = 24.0
	dust_pm.initial_velocity_min = 1.2
	dust_pm.initial_velocity_max = 2.6
	dust_pm.gravity = Vector3(0.0, -3.0, 0.0)
	dust_pm.scale_min = 0.5
	dust_pm.scale_max = 1.0
	dust_pm.color = Color(1.0, 0.29, 0.66)  # matches the deck underglow
	dust_pm.color_ramp = fade_tex
	_dust.process_material = dust_pm
	var dust_mesh := QuadMesh.new()
	dust_mesh.size = Vector2(0.13, 0.13)
	dust_mesh.material = mat
	_dust.draw_pass_1 = dust_mesh
	add_child(_dust)

	# Sparks: a single hard one-shot spray, cyan-white for contrast with
	# the pink dust. Main restarts it on smashes and boost pads.
	_sparks = GPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.amount = 14
	_sparks.lifetime = 0.35
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.emitting = false
	_sparks.local_coords = false
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.position = Vector3(0.0, 0.15, 0.0)
	var spark_pm := ParticleProcessMaterial.new()
	spark_pm.direction = Vector3(0.0, 1.0, 0.35)
	spark_pm.spread = 55.0
	spark_pm.initial_velocity_min = 4.0
	spark_pm.initial_velocity_max = 7.0
	spark_pm.gravity = Vector3(0.0, -14.0, 0.0)
	spark_pm.scale_min = 0.4
	spark_pm.scale_max = 0.8
	spark_pm.color = Color(0.55, 1.0, 1.0)  # trail-tier cyan, pushed hot
	spark_pm.color_ramp = fade_tex
	_sparks.process_material = spark_pm
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.09, 0.09)
	spark_mesh.material = mat
	_sparks.draw_pass_1 = spark_mesh
	add_child(_sparks)


## Fired by Main on zombie smashes and boost pads: one cyan spray off the
## wheels. restart() re-triggers the one-shot even mid-burst.
func burst_sparks() -> void:
	if run_state != RunState.RUNNING:
		return
	_sparks.restart()


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
	_active_trick = ""
	_boost_timer = 0.0
	character.reset()
	_dust.restart()  # clear puffs left hanging at the previous crash site
	_dust.amount_ratio = 0.0
	_sparks.emitting = false
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
		# Dust tapers with the glide and cuts out entirely on a death.
		_dust.amount_ratio = get_speed_ratio() if run_state == RunState.FINISHED else 0.0
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
	# Wheels only kick up dust on the road; the plume thickens with speed.
	_dust.amount_ratio = get_speed_ratio() if height <= 0.001 else 0.0
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

	_boost_timer = maxf(_boost_timer - delta, 0.0)
	var pad_bonus := 14.0 if _boost_timer > 0.0 else 0.0

	var target_speed: float = lerp(base_speed, max_speed, get_progress())
	target_speed += accel_boost * maxf(accel_axis, 0.0)
	target_speed -= brake_strength * maxf(-accel_axis, 0.0)
	target_speed += pad_bonus
	target_speed = clampf(target_speed, base_speed * 0.5, max_speed + accel_boost + pad_bonus)
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
	# Kept shallow so the upright riding stance stays upright at speed.
	var target_pitch := -0.04 - get_speed_ratio() * 0.06
	visuals.rotation.x = lerp_angle(visuals.rotation.x, target_pitch, 6.0 * delta)


func _start_trick() -> void:
	_trick_index += 1
	if _trick_index % 2 == 1:
		skateboard.do_kickflip(0.5)
		_active_trick = "KICKFLIP"
		tricked.emit("KICKFLIP!")
	else:
		_spin_time_left = _spin_duration
		_active_trick = "360 SPIN"
		tricked.emit("360 SPIN!")


## Runs the 360 spin and cancels tricks cleanly on landing.
func _update_trick(delta: float, grounded: bool) -> void:
	if grounded:
		if _spin_time_left > 0.0:
			_spin_time_left = 0.0
			visuals.rotation.y = 0.0
		skateboard.finish_trick()
		if _active_trick != "":
			trick_landed.emit(_active_trick)
			_active_trick = ""
		return
	if _spin_time_left > 0.0:
		_spin_time_left = maxf(_spin_time_left - delta, 0.0)
		visuals.rotation.y = TAU * (1.0 - _spin_time_left / _spin_duration) if _spin_time_left > 0.0 else 0.0


## Called by boost pads: a short burst of extra target speed.
func apply_boost(duration: float = 1.8) -> void:
	if run_state == RunState.RUNNING:
		_boost_timer = maxf(_boost_timer, duration)


## Called by launch ramps: a big assisted jump with the usual trick.
func launch(vv: float) -> void:
	if run_state != RunState.RUNNING:
		return
	_vertical_velocity = vv
	height = maxf(height, 0.002)
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_start_trick()
	jumped.emit()


## Smashing a zombie mid-boost stretches the boost window a little, so a
## lined-up horde can chain into a rampage.
func extend_boost(amount: float) -> void:
	if _boost_timer > 0.0:
		_boost_timer = minf(_boost_timer + amount, 4.0)


func is_boosting() -> bool:
	return _boost_timer > 0.0


## Called by cranberry bottle pickups: restores hits up to the cap.
func heal(amount: int) -> void:
	if run_state != RunState.RUNNING:
		return
	health = mini(health + amount, overheal_cap)
	character.set_danger(health == 1)


## Called by zombies on contact.
func take_damage(amount: int) -> void:
	if run_state != RunState.RUNNING or _invulnerable_timer > 0.0:
		return
	health = maxi(health - amount, 0)
	current_speed = maxf(base_speed * 0.6, current_speed * hit_speed_multiplier)
	_lateral_velocity *= 0.2
	_invulnerable_timer = invulnerable_duration
	_active_trick = ""  # a hit voids the pending trick score
	_boost_timer = 0.0
	if health <= 0:
		_die()
	else:
		character.set_danger(health == 1)
		character.play_crash()
		damaged.emit(health)


func _die() -> void:
	run_state = RunState.DEAD
	visuals.visible = true
	character.set_lean(0.0)
	character.set_danger(false)
	character.play_death()
	damaged.emit(0)
	died.emit()


func _finish() -> void:
	run_state = RunState.FINISHED
	_boost_timer = 0.0  # _update_speed stops running; don't freeze the FOV kick on
	character.set_lean(0.0)
	character.play_finish()
	finished.emit(elapsed, top_speed)
