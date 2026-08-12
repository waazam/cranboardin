extends Node3D
## A small ambient background bird: two thin angled "wing" boxes that flap,
## looping lazily around its spawn point. Purely decorative, no collision.

@export var radius: float = 30.0
@export var speed: float = 0.14

## Shared across every bird (built lazily by the first one): a dark
## plum-slate for body and wings, and a second, faintly dusk-lit shade for
## the wing tips so the silhouette has a hint of form against the sky
## instead of reading as flat black.
static var _wing_mat: StandardMaterial3D
static var _tip_mat: StandardMaterial3D

var _t: float = 0.0
var _phase: float = 0.0
var _center: Vector3
var _wings: Array[MeshInstance3D] = []


func _ready() -> void:
	_phase = randf() * TAU
	_center = position
	_build_visual()


func _build_visual() -> void:
	if _wing_mat == null:
		_wing_mat = StandardMaterial3D.new()
		_wing_mat.albedo_color = Color(0.2, 0.19, 0.27)
		_wing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tip_mat = StandardMaterial3D.new()
		_tip_mat.albedo_color = Color(0.34, 0.26, 0.36)
		_tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# A stub of a body between the wings, so the flap has something to
	# hinge from visually.
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.3, 0.08, 0.3)
	body.mesh = body_mesh
	body.material_override = _wing_mat
	add_child(body)

	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.9, 0.05, 0.22)
		wing.mesh = mesh
		wing.material_override = _wing_mat
		wing.position = Vector3(side * 0.42, 0, 0)
		add_child(wing)
		_wings.append(wing)

		# Outer third of each wing in the lighter tip shade; a child of
		# the wing, so it flaps with it. Slightly bigger than the wing on
		# every axis so it wraps the tip proud of the wing's own faces --
		# coplanar faces between the two materials would z-fight.
		var tip := MeshInstance3D.new()
		var tip_mesh := BoxMesh.new()
		tip_mesh.size = Vector3(0.32, 0.06, 0.24)
		tip.mesh = tip_mesh
		tip.material_override = _tip_mat
		tip.position = Vector3(side * 0.3, 0, 0)
		wing.add_child(tip)


func _process(delta: float) -> void:
	_t += delta * speed
	var angle: float = _t + _phase
	position = _center + Vector3(cos(angle) * radius, sin(angle * 2.3) * 1.5, sin(angle) * radius * 0.4)

	var flap: float = sin(_t * 16.0) * 0.4
	for i in _wings.size():
		var side: float = -1.0 if i == 0 else 1.0
		_wings[i].rotation.z = side * (-0.55 + flap)
