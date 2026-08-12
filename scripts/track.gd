extends Node3D
## Procedural curved downhill road.
##
## The centerline is generated as a heading that wanders via two summed
## sine curvatures (gentle S-bends, turn radius >= ~100m) while descending
## at a constant grade. The road ribbon, curbs, dashes, finish banner, and
## roadside scenery are all built along that curve with SurfaceTool /
## primitives -- no physics bodies. The player and zombies never collide
## with geometry; they live in "spline space" (distance s along the road,
## lateral offset) and query transform_at(s, lateral) for their world
## transform, which guarantees they follow the curve exactly.
##
## generate(level) can be called repeatedly; each level reseeds the curve
## and lengthens the run.

const SAMPLE_STEP := 4.0

@export var road_width: float = 14.0
@export var slope_angle_deg: float = 9.0
@export var base_length: float = 1350.0
@export var length_per_level: float = 220.0

var arc_length: float = 0.0
var start_position: Vector3 = Vector3.ZERO

var _points: PackedVector3Array = PackedVector3Array()
var _forwards: PackedVector3Array = PackedVector3Array()
var _geometry: Node3D
var _rng := RandomNumberGenerator.new()

# Shared scenery materials, rebuilt once per generate() so the hundreds of
# props along the road reuse a handful of materials instead of allocating
# one each (matters at these prop counts, and keeps draw batching happy).
var _pole_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _roof_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _slab_mats: Array[StandardMaterial3D] = []
var _billboard_mats: Array[StandardMaterial3D] = []


func generate(level: int) -> void:
	if _geometry:
		_geometry.queue_free()
	_geometry = Node3D.new()
	_geometry.name = "Geometry"
	add_child(_geometry)

	_rng.seed = 1000 + level * 7919
	arc_length = base_length + (level - 1) * length_per_level

	_build_shared_materials()
	_build_centerline()
	_build_road()
	_build_dashes()
	_build_finish_banner()
	_build_scenery()

	start_position = transform_at(0.0, 0.0).origin


## World transform at distance s down the road, offset laterally (+ = right).
## basis: X = right across the road, Y = road surface normal, -Z = downhill.
func transform_at(s: float, lateral: float) -> Transform3D:
	s = clampf(s, 0.0, arc_length)
	var idx: int = mini(int(s / SAMPLE_STEP), _points.size() - 2)
	var t := (s - idx * SAMPLE_STEP) / SAMPLE_STEP
	var pos := _points[idx].lerp(_points[idx + 1], t)
	var fwd := _forwards[idx].lerp(_forwards[idx + 1], t).normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var up := side.cross(fwd).normalized()
	return Transform3D(Basis(side, up, -fwd), pos + side * lateral)


## Builds the small pool of materials shared across scenery props. Called
## once per generate() so tints reseed along with the curve each level.
func _build_shared_materials() -> void:
	_pole_mat = _flat_mat(Color(0.2, 0.22, 0.25))

	# Streetlight head: warm pink sodium glow. Emission runs hot enough to
	# trip the bloom threshold so the heads read as haloed lamps at dusk.
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(1.0, 0.55, 0.75)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.4, 0.7)
	_lamp_mat.emission_energy_multiplier = 2.6

	# Rooftop clutter: near-black, reads as silhouette against the dusk sky.
	_roof_mat = _flat_mat(Color(0.11, 0.09, 0.17))

	# Antenna beacon: tiny hot red dot -- a cheap aircraft warning light.
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(1.0, 0.25, 0.3)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.15, 0.25)
	_beacon_mat.emission_energy_multiplier = 3.0

	# Building slab palette: all in the dark-plum family but nudged toward
	# indigo, wine, or teal so the canyon reads as many buildings, not one
	# continuous wall. Shared, so variation costs six materials total.
	_slab_mats.clear()
	var slab_tints: Array[Color] = [
		Color(0.20, 0.16, 0.32),  # house plum
		Color(0.16, 0.15, 0.34),  # dusty indigo
		Color(0.24, 0.14, 0.30),  # wine
		Color(0.15, 0.18, 0.30),  # slate teal
		Color(0.13, 0.11, 0.24),  # deep shadow
		Color(0.23, 0.18, 0.34),  # pale mauve
	]
	for tint in slab_tints:
		_slab_mats.append(_flat_mat(tint))

	# Rooftop billboard faces: one neon tint each, glowing softly -- kept
	# dimmer than the lamp heads so they sit lower in the bloom hierarchy.
	_billboard_mats.clear()
	var billboard_tints: Array[Color] = [
		Color(1.0, 0.4, 0.7),    # pink
		Color(0.35, 0.9, 0.95),  # cyan
		Color(1.0, 0.7, 0.35),   # amber
	]
	for tint in billboard_tints:
		var bb := StandardMaterial3D.new()
		bb.albedo_color = tint.darkened(0.55)
		bb.emission_enabled = true
		bb.emission = tint
		bb.emission_energy_multiplier = 1.3
		_billboard_mats.append(bb)


func _build_centerline() -> void:
	_points = PackedVector3Array()
	_forwards = PackedVector3Array()

	var slope := deg_to_rad(slope_angle_deg)
	var horiz := cos(slope)
	var drop := sin(slope)

	# Curvature (rad/m) = two summed sines: long lazy bends + shorter wiggle.
	var amp1 := _rng.randf_range(0.0030, 0.0045)
	var amp2 := _rng.randf_range(0.0015, 0.0030)
	var wl1 := _rng.randf_range(420.0, 640.0)
	var wl2 := _rng.randf_range(170.0, 260.0)
	var ph1 := _rng.randf_range(0.0, TAU)
	var ph2 := _rng.randf_range(0.0, TAU)

	var pos := Vector3.ZERO
	var heading := 0.0  # 0 = -Z
	var sample_count: int = int(arc_length / SAMPLE_STEP) + 2

	for i in sample_count:
		var s := i * SAMPLE_STEP
		var h_dir := Vector3(-sin(heading), 0.0, -cos(heading))
		var step_vec := h_dir * (SAMPLE_STEP * horiz) + Vector3(0.0, -SAMPLE_STEP * drop, 0.0)
		_points.append(pos)
		_forwards.append(step_vec.normalized())
		pos += step_vec
		var curvature := amp1 * sin(TAU * s / wl1 + ph1) + amp2 * sin(TAU * s / wl2 + ph2)
		heading += curvature * SAMPLE_STEP


func _build_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curb_st := SurfaceTool.new()
	curb_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ground_st := SurfaceTool.new()
	ground_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge_st := SurfaceTool.new()
	edge_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := road_width * 0.5
	for i in _points.size() - 1:
		var xf0 := _sample_frame(i)
		var xf1 := _sample_frame(i + 1)
		_add_strip_quad(st, xf0, xf1, -half, half, 0.0)
		# Curbs: slightly raised outer strips on both edges.
		_add_strip_quad(curb_st, xf0, xf1, -half - 0.55, -half, 0.13)
		_add_strip_quad(curb_st, xf0, xf1, half, half + 0.55, 0.13)
		# Embedded edge lighting: thin glowing strips just inside each curb,
		# echoing the neon center line so the road reads as a lit corridor.
		_add_strip_quad(edge_st, xf0, xf1, -half + 0.05, -half + 0.22, 0.06)
		_add_strip_quad(edge_st, xf0, xf1, half - 0.22, half - 0.05, 0.06)
		# Wide sidewalk/ground fill so the world doesn't fall away into
		# fog-colored void beyond the curbs (buildings need footing).
		_add_strip_quad(ground_st, xf0, xf1, -half - 45.0, -half - 0.55, 0.1)
		_add_strip_quad(ground_st, xf0, xf1, half + 0.55, half + 45.0, 0.1)

	var road := MeshInstance3D.new()
	road.mesh = st.commit()
	# Worn asphalt: tighter roughness plus a touch of metallic so the low
	# sun drags a faint sheen down the road, without reading as wet.
	var road_mat := _flat_mat(Color(0.15, 0.12, 0.21))
	road_mat.roughness = 0.55
	road_mat.metallic = 0.2
	road_mat.metallic_specular = 0.6
	road.material_override = road_mat
	_geometry.add_child(road)

	var curbs := MeshInstance3D.new()
	curbs.mesh = curb_st.commit()
	var curb_mat := _flat_mat(Color(0.2, 0.5, 0.5))
	curb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	curbs.material_override = curb_mat
	_geometry.add_child(curbs)

	# Curb edge strips: faint teal emission (a cool counterpart to the pink
	# center dashes), just bright enough for bloom to catch at speed.
	var edges := MeshInstance3D.new()
	edges.mesh = edge_st.commit()
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.1, 0.3, 0.32)
	edge_mat.emission_enabled = true
	edge_mat.emission = Color(0.25, 0.95, 0.9)
	edge_mat.emission_energy_multiplier = 1.1
	edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	edges.material_override = edge_mat
	_geometry.add_child(edges)

	var ground := MeshInstance3D.new()
	ground.mesh = ground_st.commit()
	ground.material_override = _flat_mat(Color(0.2, 0.16, 0.26))
	_geometry.add_child(ground)


## One quad of a ribbon between two consecutive cross-sections, between
## lateral offsets lat_a..lat_b, raised by `lift` along the road normal.
func _add_strip_quad(st: SurfaceTool, xf0: Transform3D, xf1: Transform3D,
		lat_a: float, lat_b: float, lift: float) -> void:
	var a0 := xf0.origin + xf0.basis.x * lat_a + xf0.basis.y * lift
	var b0 := xf0.origin + xf0.basis.x * lat_b + xf0.basis.y * lift
	var a1 := xf1.origin + xf1.basis.x * lat_a + xf1.basis.y * lift
	var b1 := xf1.origin + xf1.basis.x * lat_b + xf1.basis.y * lift
	var n0: Vector3 = xf0.basis.y
	var n1: Vector3 = xf1.basis.y
	st.set_normal(n0); st.add_vertex(a0)
	st.set_normal(n0); st.add_vertex(b0)
	st.set_normal(n1); st.add_vertex(b1)
	st.set_normal(n0); st.add_vertex(a0)
	st.set_normal(n1); st.add_vertex(b1)
	st.set_normal(n1); st.add_vertex(a1)


func _sample_frame(i: int) -> Transform3D:
	var fwd := _forwards[i]
	var side := fwd.cross(Vector3.UP).normalized()
	var up := side.cross(fwd).normalized()
	return Transform3D(Basis(side, up, -fwd), _points[i])


func _build_dashes() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := 6.0
	while s < arc_length - 10.0:
		var xf0 := transform_at(s, 0.0)
		var xf1 := transform_at(s + 2.6, 0.0)
		_add_strip_quad(st, xf0, xf1, -0.3, 0.3, 0.05)
		s += 12.0
	var dashes := MeshInstance3D.new()
	dashes.mesh = st.commit()
	# Neon center line: emission-driven so it glows the same regardless of
	# the pink dusk lighting (deliberately NOT unshaded -- Godot discards
	# EMISSION on unshaded materials, so the shaded path is what lets the
	# 1.6-energy pink actually cross the bloom threshold and haze like real
	# neon). Cull disabled so winding can't hide the strip.
	var dash_mat := StandardMaterial3D.new()
	dash_mat.albedo_color = Color(1.0, 0.35, 0.65)
	dash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dash_mat.emission_enabled = true
	dash_mat.emission = Color(1.0, 0.3, 0.6)
	dash_mat.emission_energy_multiplier = 1.6
	dashes.material_override = dash_mat
	_geometry.add_child(dashes)


func _build_finish_banner() -> void:
	var xf := transform_at(arc_length - 1.0, 0.0)
	var banner := Node3D.new()
	banner.name = "FinishBanner"
	banner.transform = xf
	_geometry.add_child(banner)

	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.3, 3.2, 0.3)
		post.mesh = mesh
		post.material_override = _flat_mat(Color(0.85, 0.3, 0.5))
		post.position = Vector3(side * (road_width * 0.5 - 0.3), 1.6, 0)
		banner.add_child(post)

	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(road_width - 0.4, 0.3, 0.3)
	bar.mesh = bar_mesh
	bar.material_override = _flat_mat(Color(0.3, 0.85, 0.85))
	bar.position = Vector3(0, 3.2, 0)
	banner.add_child(bar)


# --- Roadside scenery -------------------------------------------------------
# Placed via transform_at along the curve, then kept world-upright (only
# yawed to follow the road's heading), sunk slightly so bases never float.

func _build_scenery() -> void:
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	_geometry.add_child(scenery)

	var edge := road_width * 0.5

	# Streetlights: alternating sides.
	var s := 20.0
	var light_side := 1.0
	while s < arc_length - 15.0:
		_add_upright(scenery, s, light_side * (edge + 1.3), -0.05,
				_make_streetlight(-light_side))
		light_side = -light_side
		s += 26.0

	# Trees, bushes, and clutter on both sides.
	for sd in [-1.0, 1.0]:
		s = 10.0
		while s < arc_length - 10.0:
			var lat: float = sd * (edge + _rng.randf_range(2.0, 6.5))
			var roll := _rng.randf()
			var item: Node3D
			if roll < 0.4:
				item = _make_tree()
			elif roll < 0.65:
				item = _make_bush()
			elif roll < 0.85:
				item = _make_trash_can()
			else:
				item = _make_hydrant()
			_add_upright(scenery, s + _rng.randf_range(-3.0, 3.0), lat, -0.05, item)
			s += _rng.randf_range(9.0, 16.0)

	# City-canyon building slabs further out. Each facade sheet gets its own
	# warm/cool bias so some towers glow amber-office, others cold neon.
	var window_mats: Array[StandardMaterial3D] = []
	for i in 5:
		window_mats.append(_make_window_material(_rng.randf_range(0.2, 0.8)))
	for sd in [-1.0, 1.0]:
		s = 25.0
		while s < arc_length - 20.0:
			var w := _rng.randf_range(14.0, 26.0)
			_add_upright(scenery, s + w * 0.5,
					sd * (edge + _rng.randf_range(9.0, 15.0)), -0.8,
					_make_building_slab(sd, w, window_mats))
			s += w + _rng.randf_range(6.0, 18.0)

	# Manhole covers along the road.
	s = 30.0
	var mh_mat := _flat_mat(Color(0.1, 0.09, 0.15))
	while s < arc_length - 10.0:
		var xf := transform_at(s, _rng.randf_range(-edge * 0.6, edge * 0.6))
		var mh := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.45
		disc.bottom_radius = 0.45
		disc.height = 0.02
		mh.mesh = disc
		mh.material_override = mh_mat
		mh.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * 0.015)
		scenery.add_child(mh)
		s += _rng.randf_range(35.0, 55.0)


## Places `item` at (s, lateral), world-upright, yawed to the road heading.
func _add_upright(parent: Node3D, s: float, lateral: float, sink: float, item: Node3D) -> void:
	var xf := transform_at(s, lateral)
	var fwd: Vector3 = -xf.basis.z
	item.position = xf.origin + Vector3(0, sink, 0)
	item.rotation.y = atan2(-fwd.x, -fwd.z)
	parent.add_child(item)


func _make_streetlight(toward_road: float) -> Node3D:
	var item := Node3D.new()

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 4.2
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 2.1, 0)
	pole.material_override = _pole_mat
	item.add_child(pole)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(1.0, 0.08, 0.08)
	arm.mesh = arm_mesh
	arm.position = Vector3(toward_road * 0.5, 4.16, 0)
	arm.material_override = _pole_mat
	item.add_child(arm)

	# Emissive head only -- no OmniLight3D; bloom sells the glow for free.
	var lamp := MeshInstance3D.new()
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.32, 0.1, 0.16)
	lamp.mesh = lamp_mesh
	lamp.position = Vector3(toward_road * 0.95, 4.1, 0)
	lamp.material_override = _lamp_mat
	item.add_child(lamp)
	return item


func _make_tree() -> Node3D:
	var item := Node3D.new()
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.16
	var trunk_h := _rng.randf_range(1.2, 2.0)
	trunk_mesh.height = trunk_h
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0, trunk_h * 0.5, 0)
	trunk.material_override = _flat_mat(Color(0.35, 0.27, 0.2))
	item.add_child(trunk)

	var green := Color(0.12, 0.34 + _rng.randf_range(0.0, 0.08), 0.3)
	var radius := _rng.randf_range(0.8, 1.2)
	var y := trunk_h + radius * 0.6
	for layer in 2:
		var leaves := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = radius
		ball.height = radius * 1.8
		leaves.mesh = ball
		leaves.position = Vector3(_rng.randf_range(-0.2, 0.2), y, _rng.randf_range(-0.2, 0.2))
		leaves.material_override = _flat_mat(green.lightened(layer * 0.08))
		item.add_child(leaves)
		y += radius * 0.7
		radius *= 0.7
	return item


func _make_bush() -> Node3D:
	var item := Node3D.new()
	var bush := MeshInstance3D.new()
	var ball := SphereMesh.new()
	var size := _rng.randf_range(0.5, 0.9)
	ball.radius = size * 0.65
	ball.height = size
	bush.mesh = ball
	bush.position = Vector3(0, size * 0.42, 0)
	bush.material_override = _flat_mat(Color(0.14, 0.36, 0.3))
	item.add_child(bush)
	return item


func _make_trash_can() -> Node3D:
	var item := Node3D.new()
	var can := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.26
	cyl.bottom_radius = 0.22
	cyl.height = 0.65
	can.mesh = cyl
	can.position = Vector3(0, 0.325, 0)
	can.material_override = _flat_mat(Color(0.3, 0.28, 0.42))
	item.add_child(can)
	return item


func _make_hydrant() -> Node3D:
	var item := Node3D.new()
	var red := _flat_mat(Color(0.8, 0.25, 0.35))
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.11
	cyl.bottom_radius = 0.13
	cyl.height = 0.45
	body.mesh = cyl
	body.position = Vector3(0, 0.225, 0)
	body.material_override = red
	item.add_child(body)

	var cap := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.11
	dome.height = 0.16
	cap.mesh = dome
	cap.position = Vector3(0, 0.48, 0)
	cap.material_override = red
	item.add_child(cap)
	return item


func _make_building_slab(side: float, width: float,
		window_mats: Array[StandardMaterial3D]) -> Node3D:
	var h := _rng.randf_range(10.0, 26.0)
	var d := _rng.randf_range(8.0, 14.0)
	var item := Node3D.new()

	# Body tint comes from the shared palette so neighbours rarely match.
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(d, h, width)
	slab.mesh = box
	slab.position = Vector3(0, h * 0.5, 0)
	slab.material_override = _slab_mats[_rng.randi_range(0, _slab_mats.size() - 1)]
	item.add_child(slab)

	# Pixel-art window face toward the road.
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, h * 0.92)
	face.mesh = quad
	face.position = Vector3(-side * (d * 0.5 + 0.05), h * 0.5, 0)
	face.rotation.y = -side * PI * 0.5
	face.material_override = window_mats[_rng.randi_range(0, window_mats.size() - 1)]
	item.add_child(face)

	# Rooftop silhouettes so the skyline roofline isn't a flat slab edge.
	# (~15% of roofs stay bare -- variety includes the occasional clean top.)
	var roll := _rng.randf()
	if roll < 0.35:
		# Antenna mast with a hot little beacon on the tip.
		var mast_h := _rng.randf_range(1.6, 3.6)
		var mast_x := _rng.randf_range(-d * 0.3, d * 0.3)
		var mast_z := _rng.randf_range(-width * 0.35, width * 0.35)
		var mast := MeshInstance3D.new()
		var rod := CylinderMesh.new()
		rod.top_radius = 0.05
		rod.bottom_radius = 0.09
		rod.height = mast_h
		rod.radial_segments = 6
		mast.mesh = rod
		mast.position = Vector3(mast_x, h + mast_h * 0.5, mast_z)
		mast.material_override = _roof_mat
		item.add_child(mast)
		var beacon := MeshInstance3D.new()
		var dot := BoxMesh.new()
		dot.size = Vector3(0.16, 0.16, 0.16)
		beacon.mesh = dot
		beacon.position = Vector3(mast_x, h + mast_h + 0.08, mast_z)
		beacon.material_override = _beacon_mat
		item.add_child(beacon)
	elif roll < 0.65:
		# AC boxes / roof machinery: one to three squat blocks.
		for i in _rng.randi_range(1, 3):
			var ac := MeshInstance3D.new()
			var ac_mesh := BoxMesh.new()
			ac_mesh.size = Vector3(_rng.randf_range(1.0, 2.2),
					_rng.randf_range(0.8, 1.6), _rng.randf_range(1.0, 2.4))
			ac.mesh = ac_mesh
			ac.position = Vector3(_rng.randf_range(-d * 0.28, d * 0.28),
					h + ac_mesh.size.y * 0.5,
					_rng.randf_range(-width * 0.3, width * 0.3))
			ac.material_override = _roof_mat
			item.add_child(ac)
	elif roll < 0.85:
		# Billboard: dark slab frame plus a softly glowing neon face that
		# leans over the road-facing edge of the roof.
		var bb_w := minf(width * 0.6, _rng.randf_range(4.0, 8.0))
		var bb_h := _rng.randf_range(2.0, 3.4)
		var bb_z := _rng.randf_range(-width * 0.15, width * 0.15)
		var frame := MeshInstance3D.new()
		var frame_mesh := BoxMesh.new()
		frame_mesh.size = Vector3(0.25, bb_h, bb_w)
		frame.mesh = frame_mesh
		frame.position = Vector3(-side * d * 0.3, h + bb_h * 0.5 + 0.2, bb_z)
		frame.material_override = _roof_mat
		item.add_child(frame)
		var panel := MeshInstance3D.new()
		var panel_mesh := QuadMesh.new()
		panel_mesh.size = Vector2(bb_w * 0.9, bb_h * 0.8)
		panel.mesh = panel_mesh
		panel.position = frame.position + Vector3(-side * 0.14, 0, 0)
		panel.rotation.y = -side * PI * 0.5
		panel.material_override = _billboard_mats[_rng.randi_range(0, _billboard_mats.size() - 1)]
		item.add_child(panel)
	return item


## Pixel-art facade sheet. `warm_bias` [0..1] skews the lit rooms toward
## amber (1.0) or toward cyan/pink (0.0), giving each sheet its own mood.
func _make_window_material(warm_bias: float) -> StandardMaterial3D:
	var w := 20
	var h := 28
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var glow := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var facade := Color(0.17, 0.13, 0.28, 1.0)
	var glass := Color(0.28, 0.24, 0.42, 1.0)
	var warm: Array[Color] = [
		Color(1.0, 0.75, 0.4, 1.0),   # office amber
		Color(1.0, 0.55, 0.35, 1.0),  # tungsten
	]
	var cool: Array[Color] = [
		Color(0.4, 0.9, 0.95, 1.0),   # cyan
		Color(0.55, 0.5, 1.0, 1.0),   # violet
		Color(1.0, 0.4, 0.75, 1.0),   # pink
	]

	img.fill(facade)
	glow.fill(Color(0.0, 0.0, 0.0, 1.0))
	var y := 2
	while y < h - 2:
		var x := 2
		while x < w - 2:
			var col := glass
			var lit := Color(0.0, 0.0, 0.0, 1.0)
			if _rng.randf() < 0.3:
				# Lit room: tint pool chosen per the sheet's warm bias.
				var pool := warm if _rng.randf() < warm_bias else cool
				col = pool[_rng.randi_range(0, pool.size() - 1)]
				# Brightness lives in the emission texel: most rooms sit at
				# a cozy fraction of the material's energy, while a rare few
				# run full-value so the bloom pass picks them out.
				var level := 1.0 if _rng.randf() < 0.1 else _rng.randf_range(0.25, 0.45)
				lit = Color(col.r * level, col.g * level, col.b * level, 1.0)
			for dx in 2:
				for dy in 2:
					img.set_pixel(x + dx, y + dy, col)
					glow.set_pixel(x + dx, y + dy, lit)
			x += 4
		y += 4

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Shaded, so facades pick up the sun and fog like the rest of the world;
	# the lit rooms ride on the emission texture instead of albedo. Emission
	# color stays black (default) -- with the additive operator the texture
	# alone supplies the glow, so unlit texels stay perfectly dark.
	mat.roughness = 0.9
	mat.emission_enabled = true
	mat.emission_texture = ImageTexture.create_from_image(glow)
	mat.emission_energy_multiplier = 2.4
	return mat


func _flat_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	return mat
