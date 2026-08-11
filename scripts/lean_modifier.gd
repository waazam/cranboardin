extends SkeletonModifier3D
class_name LeanModifier
## Rolls the rider's spine into turns by rotating the three spine bones
## (plus a counter-rotation on the neck, so the head stays level-ish)
## about the travel axis, AFTER the AnimationPlayer has posed the
## skeleton -- this is the sanctioned post-animation hook, so the lean
## blends on top of whatever clip is playing instead of fighting it.

const SPINE_BONES: Array[String] = ["DEF-spine.001", "DEF-spine.002", "DEF-spine.003"]
const NECK_BONE := "DEF-neck"

## Total lean angle in radians (split across the spine chain).
var lean: float = 0.0
## Travel-forward axis in skeleton space (set by Character from its stance).
var axis: Vector3 = Vector3(1, 0, 0)


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var sk := get_skeleton()
	if sk == null or absf(lean) < 0.0005:
		return
	var per := lean / SPINE_BONES.size()
	for bone_name in SPINE_BONES:
		_roll_bone(sk, bone_name, per)
	_roll_bone(sk, NECK_BONE, -lean * 0.4)


func _roll_bone(sk: Skeleton3D, bone_name: String, angle: float) -> void:
	var b := sk.find_bone(bone_name)
	if b < 0:
		return
	var pose := sk.get_bone_global_pose(b)
	var rot := Quaternion(axis.normalized(), angle)
	sk.set_bone_global_pose(b, Transform3D(Basis(rot) * pose.basis, pose.origin))
