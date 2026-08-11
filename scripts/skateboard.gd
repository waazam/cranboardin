extends Node3D
class_name Skateboard
## The board -- deck, trucks, and four wheels. A separate entity from
## Character so it can be swapped, styled, or animated on its own (e.g.
## kickflips later would rotate just this node, not the rider).
##
## Call `update_roll(speed, delta)` each physics tick to spin the wheels
## in proportion to actual ground speed.

@export var deck_color := Color(0.1, 0.1, 0.12)
@export var wheel_color := Color(0.88, 0.86, 0.78)

# Proportioned to the rider (the ~1.65m mannequin in character.gd), matching
# real skateboard ratios: deck just under half the rider's height.
const WHEEL_RADIUS := 0.06
## Deck top sits at wheel + truck + deck thickness; Character stands on this.
const DECK_TOP_HEIGHT := WHEEL_RADIUS + 0.06 + 0.05

var _wheels: Array[MeshInstance3D] = []

## Carve roll set by Player each tick; combined with any active kickflip.
var _carve: float = 0.0
var _flip_duration: float = 0.5
var _flip_time_left: float = 0.0


func _ready() -> void:
	_build()


func set_carve(angle: float) -> void:
	_carve = angle


## Kickflip: the board alone rolls a full 360 about its long axis.
func do_kickflip(duration: float = 0.5) -> void:
	_flip_duration = duration
	_flip_time_left = duration


func finish_trick() -> void:
	_flip_time_left = 0.0


func _physics_process(delta: float) -> void:
	var flip_angle := 0.0
	if _flip_time_left > 0.0:
		_flip_time_left = maxf(_flip_time_left - delta, 0.0)
		if _flip_time_left > 0.0:
			flip_angle = TAU * (1.0 - _flip_time_left / _flip_duration)
	rotation.z = _carve + flip_angle


func _build() -> void:
	var deck_mat := _flat_material(deck_color)
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(0.26, 0.05, 0.85)
	deck.mesh = deck_mesh
	deck.position = Vector3(0, DECK_TOP_HEIGHT - 0.025, 0)
	deck.material_override = deck_mat
	add_child(deck)

	# Kicktails: short upward-angled nose/tail sections.
	for z_dir in [-1.0, 1.0]:
		var tail := MeshInstance3D.new()
		var tail_mesh := BoxMesh.new()
		tail_mesh.size = Vector3(0.24, 0.045, 0.16)
		tail.mesh = tail_mesh
		tail.position = Vector3(0, DECK_TOP_HEIGHT - 0.01, z_dir * 0.49)
		tail.rotation.x = -z_dir * 0.42
		tail.material_override = deck_mat
		add_child(tail)

	# Grip tape: near-black thin sheet on top of the deck.
	var grip := MeshInstance3D.new()
	var grip_mesh := BoxMesh.new()
	grip_mesh.size = Vector3(0.24, 0.006, 0.8)
	grip.mesh = grip_mesh
	grip.position = Vector3(0, DECK_TOP_HEIGHT + 0.004, 0)
	var grip_mat := _flat_material(Color(0.05, 0.05, 0.06))
	grip_mat.roughness = 1.0
	grip.material_override = grip_mat
	add_child(grip)

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
