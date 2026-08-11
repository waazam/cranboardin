extends Area3D
class_name Obstacle
## A single track obstacle. CONE/RAIL/CRATE are hazards (crash on touch);
## RAMP is a boost pad (auto-jump on touch). Detection is trigger-based
## (Area3D), not physical collision, so the player never gets physically
## snagged on scenery -- only the scripted response below fires.

enum ObstacleType { CONE, RAIL, CRATE, RAMP }

@export var type: ObstacleType = ObstacleType.CONE

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
var mesh_instance: MeshInstance3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	match type:
		ObstacleType.CONE:
			_setup_cone()
		ObstacleType.RAIL:
			_setup_rail()
		ObstacleType.CRATE:
			_setup_crate()
		ObstacleType.RAMP:
			_setup_ramp()


func _setup_cone() -> void:
	add_to_group("hazard")
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.38
	mesh.height = 0.75
	mesh_instance.mesh = mesh
	_place(Vector3(0.8, 0.75, 0.8))
	_apply_color(Color(0.95, 0.45, 0.08))


func _setup_rail() -> void:
	add_to_group("hazard")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.6, 0.5, 0.35)
	mesh_instance.mesh = mesh
	_place(Vector3(2.6, 0.5, 0.6))
	_apply_color(Color(0.82, 0.1, 0.14))


func _setup_crate() -> void:
	add_to_group("hazard")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.85, 0.85, 0.85)
	mesh_instance.mesh = mesh
	_place(Vector3(0.85, 0.85, 0.85))
	_apply_color(Color(0.55, 0.37, 0.2))


func _setup_ramp() -> void:
	add_to_group("boost")
	var mesh := PrismMesh.new()
	mesh.size = Vector3(1.8, 0.85, 2.4)
	mesh.left_to_right = 0.0
	mesh_instance.mesh = mesh
	_place(Vector3(1.8, 0.85, 2.4))
	_apply_color(Color(0.2, 0.55, 0.92))


## Positions the mesh + collision shape so the obstacle sits flush on the
## ground (local origin = ground contact point) and sizes the trigger box.
func _place(size: Vector3) -> void:
	mesh_instance.position.y = size.y * 0.5
	var shape := BoxShape3D.new()
	shape.size = size
	collision_shape.shape = shape
	collision_shape.position.y = size.y * 0.5


func _apply_color(color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mesh_instance.material_override = mat


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if type == ObstacleType.RAMP:
		if body.has_method("apply_boost"):
			body.apply_boost()
	else:
		if body.has_method("register_crash"):
			body.register_crash()
