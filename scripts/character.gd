extends Node3D
class_name Character
## The rider: Godot's standard-animation-library mannequin (53-bone rig),
## driven by a tiny animation state machine. Player feeds it motion state
## each physics tick via update_motion(); crash/finish/reset are one-shot
## hooks. Still a separate entity from Skateboard, so board tricks and
## rider animation stay independent.
##
## Animation mapping:
##   grounded        -> Crouch_Idle (loops; reads as a skating tuck)
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

var _model: Node3D
var _anim: AnimationPlayer
var _lean_modifier: LeanModifier
var _current: StringName = &""
## While true (crash/finish/death anims), update_motion() is ignored.
var _locked: bool = false


func _ready() -> void:
	_model = MODEL_SCENE.instantiate() as Node3D
	_model.position.y = stand_height
	# glTF models face +Z and the run heads toward -Z, so PI would face the
	# rider square downhill; subtracting the stance angle turns him across
	# the board (feet spread along the deck) like a real skater.
	_model.rotation.y = PI - deg_to_rad(stance_angle_deg)
	_model.scale = Vector3.ONE * model_scale
	add_child(_model)

	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(_anim != null, "AnimationLibrary GLB is missing its AnimationPlayer")
	_anim.animation_finished.connect(_on_animation_finished)

	# Post-animation spine lean (see lean_modifier.gd). The travel-forward
	# axis in the model's space depends on the stance rotation applied above.
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		_lean_modifier = LeanModifier.new()
		var model_yaw := PI - deg_to_rad(stance_angle_deg)
		_lean_modifier.axis = Vector3(sin(model_yaw), 0.0, -cos(model_yaw))
		skeleton.add_child(_lean_modifier)

	_play(&"Crouch_Idle", 0.0)


## Called by Player every physics tick with the post-move floor state.
func update_motion(grounded: bool) -> void:
	if _locked:
		return
	if grounded:
		_play(&"Crouch_Idle", 0.25)
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
	_play(&"Crouch_Idle", 0.0)


func _play(anim: StringName, blend: float) -> void:
	if _current == anim:
		return
	_current = anim
	_anim.play(anim, blend)


func _on_animation_finished(anim_name: StringName) -> void:
	# Crash reaction over -> hand control back to update_motion().
	if anim_name == &"Hit_Chest":
		_locked = false
