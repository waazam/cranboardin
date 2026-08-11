extends Node3D
class_name Skateboard
## The board -- deck, trucks, and four wheels. A separate entity from
## Character so it can be swapped, styled, or animated on its own (e.g.
## kickflips later would rotate just this node, not the rider).
##
## Call `update_roll(speed, delta)` each physics tick to spin the wheels
## in proportion to actual ground speed.

@export var deck_color := Color(0.1, 0.1, 0.12)
@export var wheel_color := Color(0.95, 0.9, 0.55)

# Proportioned to the rider (the ~1.65m mannequin in character.gd), matching
# real skateboard ratios: deck just under half the rider's height.
const WHEEL_RADIUS := 0.06
## Deck top sits at wheel + truck + deck thickness; Character stands on this.
const DECK_TOP_HEIGHT := WHEEL_RADIUS + 0.06 + 0.05

var _wheels: Array[MeshInstance3D] = []


func _ready() -> void:
	_build()


func _build() -> void:
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(0.26, 0.05, 0.85)
	deck.mesh = deck_mesh
	deck.position = Vector3(0, DECK_TOP_HEIGHT - 0.025, 0)
	deck.material_override = _flat_material(deck_color)
	add_child(deck)

	var truck_mat := _flat_material(Color(0.6, 0.6, 0.65))
	var wheel_mat := _flat_material(wheel_color)
	for z in [-0.27, 0.27]:
		var truck := MeshInstance3D.new()
		var truck_mesh := BoxMesh.new()
		truck_mesh.size = Vector3(0.18, 0.06, 0.08)
		truck.mesh = truck_mesh
		truck.position = Vector3(0, WHEEL_RADIUS + 0.03, z)
		truck.material_override = truck_mat
		add_child(truck)

		for x in [-0.10, 0.10]:
			var wheel := MeshInstance3D.new()
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = WHEEL_RADIUS
			wheel_mesh.bottom_radius = WHEEL_RADIUS
			wheel_mesh.height = 0.05
			wheel.mesh = wheel_mesh
			# Cylinder axis is Y; roll it onto its side so it spins about X.
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(x, WHEEL_RADIUS, z)
			wheel.material_override = wheel_mat
			add_child(wheel)
			_wheels.append(wheel)


## Spin the wheels to match ground speed (angular velocity = v / r).
func update_roll(speed: float, delta: float) -> void:
	var spin := speed / WHEEL_RADIUS * delta
	for wheel in _wheels:
		# Local Y is the axle axis after the sideways roll above.
		wheel.rotate_object_local(Vector3.UP, spin)


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat
