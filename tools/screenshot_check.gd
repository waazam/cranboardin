extends SceneTree
## Dev-only visual smoke test: boots a scene, lets it render for a number
## of frames, saves a PNG of the window, and quits. Needs a real renderer
## (not --headless). Usage:
##
##   godot --path . -s res://tools/screenshot_check.gd -- \
##       scene=res://scenes/menu.tscn out=C:/tmp/menu.png frames=40

var _scene_path := "res://scenes/menu.tscn"
var _out := "user://shot.png"
var _wait := 40
var _frames := 0


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"scene": _scene_path = kv[1]
				"out": _out = kv[1]
				"frames": _wait = int(kv[1])
	change_scene_to_file.call_deferred(_scene_path)
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames >= _wait:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		quit()
