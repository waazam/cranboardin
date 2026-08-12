extends Node3D
## Cranberry bottle power-ups scattered along the road. Grabbing one
## restores a hit. Each bottle is a pixel-art billboard sprite (see
## pixel_sprites.gd) with a two-frame sparkle, bobbing and swelling so it
## reads as a pickup against the muted world.

const PICKUP_S_RANGE := 1.1
const PICKUP_LATERAL_RANGE := 1.0
const PICKUP_MAX_HEIGHT := 1.6  # grabbable even mid-jump

@export var heal_amount: int = 1  # one hit back per bottle
@export var base_count: int = 9
@export var count_per_level: int = 2

var _track: Node3D
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _bottles: Array[Dictionary] = []
var _bottle_time: float = 0.0

## One SpriteFrames shared by every bottle on the road.
var _bottle_sprite_frames: SpriteFrames

signal collected(health: int)


func _ready() -> void:
	_bottle_sprite_frames = PixelSprites.bottle_frames()


func setup(track: Node3D, player: Node3D, level: int) -> void:
	_track = track
	_player = player
	for b in _bottles:
		(b["node"] as Node3D).queue_free()
	_bottles.clear()

	_rng.seed = 9000 + level * 3271
	var count: int = base_count + (level - 1) * count_per_level
	var start_s := 120.0
	var end_s: float = track.arc_length - 60.0
	var spacing := (end_s - start_s) / float(count)
	var half: float = track.road_width * 0.5
	for i in count:
		var s := start_s + spacing * i + _rng.randf_range(0.0, spacing * 0.4)
		var lat := _rng.randf_range(-half + 1.2, half - 1.2)
		var node := _make_bottle()
		add_child(node)
		_bottles.append({"node": node, "s": s, "lat": lat, "phase": _rng.randf() * TAU})


func _physics_process(delta: float) -> void:
	if _track == null or _player == null:
		return
	_bottle_time += delta

	var i := _bottles.size() - 1
	while i >= 0:
		var b := _bottles[i]
		var bs: float = b["s"]
		var blat: float = b["lat"]
		var node := b["node"] as Node3D

		var xf: Transform3D = _track.transform_at(bs, blat)
		var bob: float = 0.15 + sin(_bottle_time * 2.4 + b["phase"]) * 0.1
		node.position = xf.origin + xf.basis.y * bob
		# Gentle swell on top of the bob (phase-offset per bottle) so
		# pickups breathe rather than sit static; the sprite's own frame
		# flip supplies the sparkle. Billboarding handles the facing.
		node.scale = Vector3.ONE * (1.0 + sin(_bottle_time * 3.2 + b["phase"]) * 0.06)

		if _player.run_state == _player.RunState.RUNNING \
				and absf(bs - _player.s) < PICKUP_S_RANGE \
				and absf(blat - _player.lateral) < PICKUP_LATERAL_RANGE \
				and _player.height < PICKUP_MAX_HEIGHT:
			_player.heal(heal_amount)
			collected.emit(_player.health)
			node.queue_free()
			_bottles.remove_at(i)
		elif bs < _player.s - 10.0:
			node.queue_free()
			_bottles.remove_at(i)
		i -= 1


## A little cranberry-juice bottle: one billboard sprite, sparkle baked in.
## 12 art rows at 0.05 m/texel = a ~0.6 m bottle, matching the old mesh.
func _make_bottle() -> Node3D:
	var item := Node3D.new()
	var sprite := PixelSprites.make_sprite(_bottle_sprite_frames, 12, 0.05)
	sprite.play(&"default")
	item.add_child(sprite)
	return item
