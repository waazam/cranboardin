extends SkeletonModifier3D
class_name LeanModifier
## Post-animation pose fixes for the rider, applied AFTER the
## AnimationPlayer has posed the skeleton (the sanctioned hook, so these
## blend on top of whatever clip is playing instead of fighting it):
##   - skate stance: the thighs spread apart along the deck and the feet
##     counter-rotate flat, turning the clip's narrow standing pose into
##     feet planted parallel across the board
##   - steering lean: the spine rolls into turns (plus a counter-rotation
##     on the neck so the head stays level-ish)

const SPINE_BONES: Array[String] = ["DEF-spine.001", "DEF-spine.002", "DEF-spine.003"]
const NECK_BONE := "DEF-neck"

## Total lean angle in radians (split across the spine chain).
var lean: float = 0.0
## Travel-forward axis in skeleton space (set by Character from its stance).
var axis: Vector3 = Vector3(1, 0, 0)
## Half-angle in radians each leg swings outward along the travel axis.
var stance_spread: float = 0.0


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return

	if stance_spread > 0.0005:
		# Legs swing apart in the vertical plane that contains the travel
		# axis: rotation about the model-forward axis (perpendicular to
		# travel), opposite signs per side. Feet counter-rotate so the
		# soles stay flat on the deck.
		var spread_axis := axis.normalized().cross(Vector3.UP)
		for side: Array in [["L", 1.0], ["R", -1.0]]:
			_roll_bone(sk, "DEF-thigh.%s" % side[0], spread_axis, stance_spread * side[1])
			_roll_bone(sk, "DEF-foot.%s" % side[0], spread_axis, -stance_spread * side[1])

	if absf(lean) >= 0.0005:
		var per := lean / SPINE_BONES.size()
		for bone_name in SPINE_BONES:
			_roll_bone(sk, bone_name, axis, per)
		_roll_bone(sk, NECK_BONE, axis, -lean * 0.4)


func _roll_bone(sk: Skeleton3D, bone_name: String, rot_axis: Vector3, angle: float) -> void:
	var b := sk.find_bone(bone_name)
	if b < 0:
		return
	var pose := sk.get_bone_global_pose(b)
	var rot := Quaternion(rot_axis.normalized(), angle)
	sk.set_bone_global_pose(b, Transform3D(Basis(rot) * pose.basis, pose.origin))
