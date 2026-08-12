extends Node3D
class_name Character
## The rider: Godot's standard-animation-library mannequin (53-bone rig),
## driven by a tiny animation state machine. Player feeds it motion state
## each physics tick via update_motion(); crash/finish/reset are one-shot
## hooks. Still a separate entity from Skateboard, so board tricks and
## rider animation stay independent.
##
## Animation mapping:
##   grounded        -> Idle (loops; an upright, casual riding stance)
##   airborne        -> Jump_Start (one-shot; holds its final pose if the
##                      air time outlasts the clip -- safer than the "Jump"
##                      loop, whose full cycle we can't preview headlessly)
##   crash           -> Hit_Chest (locks the state machine until it ends)
##   finish          -> Dance (locked until reset)

const MODEL_SCENE := preload("res://Godot/AnimationLibrary_Godot_Standard.glb")

## Deck-top height the rider stands on; Player sets this from
## Skateboard.DECK_TOP_HEIGHT before adding the node.
@export var stand_height: float = 0.27
@export var model_scale: float = 0.9
## How far the rider is turned across the board, like a real skate stance:
## 90 = regular (chest toward the right of travel), -90 = goofy,
## 0 = squarely facing downhill. Values around 70-80 read as a rider
## whose body is sideways but slightly open toward where they're going.
@export var stance_angle_deg: float = 90.0

const DANGER_PINK := Color(1.0, 0.25, 0.55)

var _model: Node3D
var _anim: AnimationPlayer
var _lean_modifier: LeanModifier
var _current: StringName = &""
## While true (crash/finish/death anims), update_motion() is ignored.
var _locked: bool = false

## Last-hit warning: while on, the whole rider hard-blinks hot pink.
var _danger: bool = false
var _blink_time: float = 0.0
var _blink_pink: bool = false
var _mats: Array[BaseMaterial3D] = []
var _mat_colors: Array[Color] = []  # each mat's normal neon, parallel to _mats


func _ready() -> void:
	_model = MODEL_SCENE.instantiate() as Node3D
	# Slightly below deck-top: swinging the legs apart (stance_spread
	# below) arcs the feet upward a touch, so the model sinks by about the
	# same amount to keep the soles planted.
	_model.position.y = stand_height - 0.012
	# glTF models face +Z and the run heads toward -Z, so PI would face the
	# rider square downhill; subtracting the stance angle turns him across
	# the board (feet spread along the deck) like a real skater.
	_model.rotation.y = PI - deg_to_rad(stance_angle_deg)
	_model.scale = Vector3.ONE * model_scale
	add_child(_model)

	# The glTF ships fully rough, which goes matte-flat under the low pink
	# sun; a one-time material pass gives the clothing a slight sheen so the
	# dusk light actually models the rider, and recolors him into the game's
	# neon palette (cyan body panels, hot pink joints). The tuned materials
	# are kept so the danger blink can repaint them.
	_mats = apply_neon_materials(_model)
	for mat in _mats:
		_mat_colors.append(mat.albedo_color)

	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(_anim != null, "AnimationLibrary GLB is missing its AnimationPlayer")
	_anim.animation_finished.connect(_on_animation_finished)

	# Post-animation stance + spine lean (see lean_modifier.gd). The
	# travel-forward axis in the model's space depends on the stance
	# rotation applied above. The spread turns the Idle clip's narrow
	# standing pose into feet planted parallel along the deck.
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		_lean_modifier = LeanModifier.new()
		var model_yaw := PI - deg_to_rad(stance_angle_deg)
		_lean_modifier.axis = Vector3(sin(model_yaw), 0.0, -cos(model_yaw))
		_lean_modifier.stance_spread = deg_to_rad(10.0)
		_lean_modifier.stance_narrow = deg_to_rad(5.0)
		skeleton.add_child(_lean_modifier)

	_play(&"Idle", 0.0)


## Called by Player every physics tick with the post-move floor state.
func update_motion(grounded: bool) -> void:
	if _locked:
		return
	if grounded:
		_play(&"Idle", 0.25)
	elif _current != &"Jump_Start":
		_play(&"Jump_Start", 0.15)


func play_crash() -> void:
	_locked = true
	_current = &"Hit_Chest"
	_anim.play(&"Hit_Chest", 0.1)


func play_finish() -> void:
	_locked = true
	_current = &"Dance"
	_anim.play(&"Dance", 0.3)


func play_death() -> void:
	_locked = true
	_current = &"Death01"
	_anim.play(&"Death01", 0.2)


## Steering lean, blended into the spine bones (radians; + leans right).
func set_lean(lean: float) -> void:
	if _lean_modifier:
		_lean_modifier.lean = lean


func reset() -> void:
	_locked = false
	set_lean(0.0)
	set_danger(false)
	_play(&"Idle", 0.0)


## Duplicate each unique surface material once (surfaces that shared a
## material keep sharing the tuned copy) and soften it: roughness pulled
## down so the sun reads on cloth and skin, plus a faint sky-tinted rim so
## the rider's silhouette catches the dusk from behind. The mannequin's two
## surfaces get the neon treatment -- M_Main (body panels) goes neon cyan,
## M_Joints goes hot pink -- with a soft self-glow so the rider pops
## against the dusk like the rest of the game's neon. Overrides live on
## the given instance only. Static so the menu can dress its rider the
## same way.
static func apply_neon_materials(model: Node3D) -> Array[BaseMaterial3D]:
	var tuned := {}  # source material -> tuned copy
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var src := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if src == null:
				continue
			if not tuned.has(src):
				var mat := src.duplicate() as BaseMaterial3D
				mat.roughness = 0.55
				mat.rim_enabled = true
				mat.rim = 0.25
				mat.rim_tint = 0.7
				var neon := Color(0.36, 0.95, 0.98) if src.resource_name == "M_Main" \
						else Color(1.0, 0.29, 0.66)
				mat.albedo_color = neon
				mat.emission_enabled = true
				mat.emission = neon
				mat.emission_energy_multiplier = 0.35
				tuned[src] = mat
			mesh_instance.set_surface_override_material(surface, tuned[src])
	var mats: Array[BaseMaterial3D] = []
	mats.assign(tuned.values())
	return mats


## Last-hit warning toggle, driven by Player as health changes.
func set_danger(on: bool) -> void:
	if _danger == on:
		return
	_danger = on
	_blink_time = 0.0
	if not on:
		_paint(false)


func _process(delta: float) -> void:
	if not _danger:
		return
	_blink_time += delta
	var pink := fmod(_blink_time, 0.36) < 0.18
	if pink != _blink_pink:
		_paint(pink)


## Repaints every tuned material either hot pink (energy pushed so the
## blink blooms) or back to its normal neon.
func _paint(pink: bool) -> void:
	_blink_pink = pink
	for i in _mats.size():
		var col := DANGER_PINK if pink else _mat_colors[i]
		_mats[i].albedo_color = col
		_mats[i].emission = col
		_mats[i].emission_energy_multiplier = 1.2 if pink else 0.35


func _play(anim: StringName, blend: float) -> void:
	if _current == anim:
		return
	_current = anim
	_anim.play(anim, blend)


func _on_animation_finished(anim_name: StringName) -> void:
	# Crash reaction over -> hand control back to update_motion().
	if anim_name == &"Hit_Chest":
		_locked = false
