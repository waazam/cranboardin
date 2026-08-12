extends Node3D
## Neon stream trail behind the board, rebuilt every frame from a short
## history of board positions (ImmediateMesh triangle strip, additive
## unshaded, vertex-colored).
##
## The head holds the score-tier color (cyan -> teal -> pink -> magenta
## -> violet) and the ribbon unwinds into a scrolling neon gradient behind
## it; width and brightness swell with the combo multiplier. Breaking the
## combo (a hit, or letting the window lapse) makes the stream sputter
## grey and dissolve fast before it regrows in color. Main pushes state
## via set_state() / break_combo() alongside its HUD updates.

const LIFETIME := 0.7
const MIN_STEP := 0.15
const MAX_POINTS := 90
const BREAK_TIME := 0.5
const BREAK_GREY := Color(0.45, 0.45, 0.52)

## Score thresholds -> head colors, lerped between neighbours so the
## stream shifts hue continuously as the score climbs.
const TIER_SCORES := [0.0, 1000.0, 3000.0, 6000.0, 10000.0]
const TIER_COLORS := [
	Color(0.3, 0.95, 0.95),   # cyan
	Color(0.25, 0.9, 0.75),   # teal
	Color(1.0, 0.42, 0.7),    # pink
	Color(0.95, 0.25, 0.85),  # hot magenta
	Color(0.75, 0.35, 1.0),   # electric violet (deliberately never white)
]

var _player: Node3D
var _mesh: ImmediateMesh
var _points: Array[Dictionary] = []  # {pos, right, age}; front = oldest
var _score: int = 0
var _mult: int = 1
var _break_timer: float = 0.0
var _time: float = 0.0  # drives the slow hue shimmer along the ribbon


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	# Additive so the stream glows over the dark road like the other neon.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	# Vertex colors are stored 0..1, so push the ribbon into HDR through the
	# material's albedo multiplier instead. Kept moderate: enough to trip the
	# bloom threshold, but low enough that the rainbow hues stay saturated
	# instead of additive-blending out to flat white.
	mat.albedo_color = Color(1.25, 1.25, 1.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)


func setup(player: Node3D) -> void:
	_player = player
	_points.clear()
	_break_timer = 0.0
	_mesh.clear_surfaces()


## Mirrors the HUD updates from Main.
func set_state(score: int, mult: int) -> void:
	_score = score
	_mult = mult


## A hit or a lapsed combo window: sputter grey and dissolve.
func break_combo() -> void:
	_break_timer = BREAK_TIME


func _head_color() -> Color:
	if _break_timer > 0.0:
		return BREAK_GREY
	var s := float(_score)
	for i in TIER_SCORES.size() - 1:
		if s < TIER_SCORES[i + 1]:
			var t: float = (s - TIER_SCORES[i]) / (TIER_SCORES[i + 1] - TIER_SCORES[i])
			return TIER_COLORS[i].lerp(TIER_COLORS[i + 1], t)
	return TIER_COLORS[-1]


func _physics_process(delta: float) -> void:
	if _player == null:
		return

	_time += delta
	_break_timer = maxf(_break_timer - delta, 0.0)

	# Age points out; a broken combo dissolves the stream 4x faster.
	var decay := 4.0 if _break_timer > 0.0 else 1.0
	for p in _points:
		p["age"] += delta * decay
	while not _points.is_empty() and _points[0]["age"] > LIFETIME:
		_points.pop_front()

	# Emit from just above the deck while the run is live (jump arcs and
	# all -- the ribbon following the air looks right).
	if _player.run_state == _player.RunState.RUNNING:
		var pos: Vector3 = _player.global_position + _player.global_basis.y * 0.08
		if _points.is_empty() or _points[-1]["pos"].distance_to(pos) > MIN_STEP:
			_points.append({"pos": pos, "right": _player.global_basis.x, "age": 0.0})
			if _points.size() > MAX_POINTS:
				_points.pop_front()

	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return

	var head := _head_color()
	var width := 0.22 + 0.08 * (_mult - 1)
	var head_alpha := 0.5 + 0.08 * _mult

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _points:
		# Taper and fade toward the tail, eased (smoothstep) so the head
		# holds its width and the tail feathers out instead of cutting off.
		var t: float = 1.0 - p["age"] / LIFETIME
		var fade: float = t * t * (3.0 - 2.0 * t)
		# Neon gradient down the ribbon: the hue ping-pongs across the
		# palette's arc of the wheel (cyan -> blue -> purple -> magenta ->
		# pink, never green/yellow/orange) while slowly scrolling with
		# time. Saturation is floored so no stretch of the ribbon ever
		# washes out to white; grey (broken combo) stays grey.
		var col := head
		if _break_timer <= 0.0:
			var cycle := fposmod((1.0 - t) * 0.85 + _time * 0.25, 1.0)
			var hue := lerpf(0.45, 0.95, absf(2.0 * cycle - 1.0))
			var sat := maxf(lerpf(head.s, 0.9, 1.0 - t), 0.75)
			col = Color.from_hsv(hue, sat, 1.0)
		col.a = head_alpha * fade
		var half: float = width * fade
		var right: Vector3 = p["right"]
		var pos: Vector3 = p["pos"]
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(pos - right * half)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(pos + right * half)
	_mesh.surface_end()
