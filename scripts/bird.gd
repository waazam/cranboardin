extends Node3D
## A small ambient background bird: two thin angled "wing" boxes that flap,
## looping lazily around its spawn point. Purely decorative, no collision.

@export var radius: float = 30.0
@export var speed: float = 0.14

var _t: float = 0.0
var _phase: float = 0.0
var _center: Vector3
var _wings: Array[MeshInstance3D] = []


func _ready() -> void:
	_phase = randf() * TAU
	_center = position
	_build_visual()


func _build_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.26, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.9, 0.05, 0.22)
		wing.mesh = mesh
		wing.material_override = mat
		wing.position = Vector3(side * 0.42, 0, 0)
		add_child(wing)
		_wings.append(wing)


func _process(delta: float) -> void:
	_t += delta * speed
	var angle: float = _t + _phase
	position = _center + Vector3(cos(angle) * radius, sin(angle * 2.3) * 1.5, sin(angle) * radius * 0.4)

	var flap: float = sin(_t * 16.0) * 0.4
	for i in _wings.size():
		var side: float = -1.0 if i == 0 else 1.0
		_wings[i].rotation.z = side * (-0.55 + flap)
