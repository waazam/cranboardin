extends SceneTree
## Dev-only visual smoke test for spawned track objects: builds a level 1
## track plus the barrier / boost pad / drone spawners (no player, physics
## paused), then walks a camera to the first barrier, the first MEGA boost
## pad, and a hand-activated drone, saving a PNG of each. Needs a real
## renderer. Usage:
##
##   godot --path . -s res://tools/visual_check.gd -- out_dir=C:/tmp

var _out_dir := "user://"
var _frames := 0
var _shot := 0
var _track: Node3D
var _obstacles: Node3D
var _boosts: Node3D
var _zombies: Node3D
var _camera: Camera3D
var _targets: Array = []  # [name, world Transform3D of the thing to frame]


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "out_dir":
			_out_dir = kv[1]
	process_frame.connect(_tick)


func _build() -> void:
	_track = (load("res://scripts/track.gd") as GDScript).new()
	root.add_child(_track)
	_track.generate(1)

	var dummy := Node3D.new()  # setup() stores a player ref; never ticked
	root.add_child(dummy)

	_obstacles = (load("res://scripts/obstacle_manager.gd") as GDScript).new()
	root.add_child(_obstacles)
	_obstacles.set_physics_process(false)
	_obstacles.setup(_track, dummy, 1)

	_boosts = (load("res://scripts/boost_manager.gd") as GDScript).new()
	root.add_child(_boosts)
	_boosts.set_physics_process(false)  # dummy player has no run_state
	_boosts.setup(_track, dummy, 1)

	_zombies = (load("res://scripts/zombie_manager.gd") as GDScript).new()
	root.add_child(_zombies)
	_zombies.set_physics_process(false)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	root.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	root.add_child(_camera)
	_camera.current = true

	# Targets: first barrier, first mega pad, one drone parked at hover
	# height over the road.
	var b: Dictionary = _obstacles._barriers[0]
	_targets.append(["barrier", _track.transform_at(b["s"], b["lat"])])

	for pad: Dictionary in _boosts._pads:
		if pad["mega"]:
			_targets.append(["megapad", _track.transform_at(pad["s"], pad["lat"])])
			break

	_zombies._activate({"s": 200.0, "lat": 0.0, "runner": false, "drone": true,
			"hover_phase": 0.0, "shamble": 2.0, "close": 1.5, "flank": 0.0,
			"weave_phase": 0.0, "weave_amp": 0.0, "weave_rate": 1.0})
	var z: Dictionary = _zombies._active[0]
	var zxf: Transform3D = _track.transform_at(200.0, 0.0)
	(z["node"] as Node3D).position = zxf.origin + zxf.basis.y * 1.9
	_targets.append(["drone", zxf])


func _frame_target(xf: Transform3D) -> void:
	# Stand a few meters uphill of the target, at rider eye height, looking
	# slightly down at it -- roughly the gameplay camera's view of it.
	_camera.position = xf.origin + xf.basis.z * 6.0 + xf.basis.y * 1.6
	_camera.look_at(xf.origin + xf.basis.y * 0.8, xf.basis.y)


func _tick() -> void:
	_frames += 1
	if _frames == 1:
		_build()
	# 20 frames per target: enough for the boost shader clock to sweep.
	if _frames >= 20 * (_shot + 1):
		if _shot >= _targets.size():
			quit()
			return
		_frame_target(_targets[_shot][1])
		if _frames >= 20 * (_shot + 1) + 5:  # a few frames to render the move
			var img := root.get_texture().get_image()
			var path: String = _out_dir + "/check_" + _targets[_shot][0] + ".png"
			img.save_png(path)
			print("saved ", path)
			_shot += 1
