extends Node3D
## Spawns and drives the zombie horde. A spawn plan is laid out along the
## track at level start; zombies only get instantiated once the player is
## within activation range, and are freed once passed. Each zombie is a
## single pixel-art billboard sprite (see pixel_sprites.gd) -- one quad per
## zombie, so the horde stays cheap even on the web build.
##
## Zombies live in the same spline space as the player (s, lateral) and
## hunt the player's lane -- dodging them is the core game, and they can
## be jumped over (hits only land when the player is low).
##
## The hunt is smarter than a straight chase, but every layer stays fair:
##   PREDICTIVE INTERCEPT -- zombies lead the player's carve, aiming where
##     the lateral velocity says the player WILL be at contact time.
##     Runners lead hard; shamblers only vaguely anticipate.
##   RUNNER LUNGE -- a runner near the player freezes for a readable beat,
##     then bursts sideways-and-forward. The burst never out-turns the
##     player's own steering, so a committed dodge always wins.
##   PACK FLANKING -- pack members each carry a persistent lane offset from
##     the predicted intercept, so a pack forms a short wall to jump or
##     thread instead of a single dodgeable column. The spread is capped
##     so a gap always survives at one road edge.
##   SHAMBLER WEAVE -- shamblers overlay a slow personal sine drift on
##     their target lane so the approach reads organic, not mechanical.
## All per-zombie brains live in the plan/active dictionaries, and every
## random trait is rolled at plan time from the seeded RNG, so a level
## replays identically for the same seed.
##
## Spawn types:
##   SIDE  -- starts just off the road edge and walks in across it.
##   AHEAD -- lurks on the road ahead and closes on the player's lateral.

signal zombie_passed(kind: String)  # "over" = cleared airborne, "near" = grazed
signal zombie_smashed(pos: Vector3)  # bowled through while boosting

enum SpawnType { SIDE, AHEAD }

const ACTIVATION_RANGE := 150.0
const DESPAWN_BEHIND := 14.0
const HIT_S_RANGE := 1.0
const HIT_LATERAL_RANGE := 0.95
const HIT_MAX_HEIGHT := 1.0
const NEAR_MISS_RANGE := 2.4

## Intercept lead factors: fraction of the full velocity-lead each class
## applies. Runners genuinely cut you off; shamblers only half-remember to.
const SHAMBLER_LEAD := 0.35
const RUNNER_LEAD := 0.9
## Time-to-contact clamp for the lead estimate -- beyond ~1.2s a prediction
## is guesswork, and an uncapped lead would send far zombies lane-hopping.
const TTC_MAX := 1.2

## Runner lunge: inside this s-gap the runner winds up (a readable freeze),
## then bursts. The burst's lateral speed is hard-capped just under the
## player's steer_speed (10.5) so out-steering a lunge is always possible.
const LUNGE_RANGE := 12.0
const LUNGE_WINDUP := 0.3
const LUNGE_DURATION := 0.55
const LUNGE_COOLDOWN := 1.6
const LUNGE_SHAMBLE_MULT := 2.4
const LUNGE_CLOSE_MULT := 2.6
const MAX_LATERAL_SPEED := 10.0

## Pack members fan out this far either side of the predicted lane. Capped
## at 1.2 so a full pack wall spans ~4.3 units of hitbox against a ~7-unit
## playable road: at least one edge lane (or a jump) always escapes.
const PACK_SPREAD := 1.2

@export var damage_per_hit: int = 1  # health is 3 hits; each contact costs one
@export var base_count: int = 78
@export var count_per_level: int = 24

var _track: Node3D
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _spawns: Array[Dictionary] = []
var _next_spawn: int = 0
var _active: Array[Dictionary] = []
## Shared clock for the shambler weave -- each zombie's plan-time phase
## offsets into it, so one accumulator serves the whole horde.
var _weave_time: float = 0.0
## Zombies mid-launch after a boost smash: {node, vel, t}.
var _smashed: Array[Dictionary] = []
## Floating score popups over smashed zombies: {node, t}.
var _popups: Array[Dictionary] = []
const POPUP_LIFETIME := 0.8
## Small shared SpriteFrames pools rather than per-instance art: however big
## the horde gets, only a handful of tiny textures ever exist. Everything
## stays inside the game's strict cyan/pink/teal/purple palette: shamblers
## in the cool half (cyan/teal/purple) with hot pink eyes, runners in the
## hot half (magenta/pink) with cyan eyes so danger still reads at a
## distance.
var _shambler_frames: Array[SpriteFrames] = []
var _runner_frames: Array[SpriteFrames] = []


func _ready() -> void:
	for tint: Color in [
		Color(0.2, 0.85, 0.75),   # neon teal
		Color(0.3, 0.8, 0.95),    # glacier cyan
		Color(0.7, 0.35, 1.0),    # electric purple
		Color(0.6, 0.55, 0.95),   # dusk lavender
	]:
		_shambler_frames.append(PixelSprites.zombie_frames(tint, Color(1.0, 0.3, 0.65)))

	for tint: Color in [
		Color(0.95, 0.3, 0.85),   # hot magenta
		Color(1.0, 0.25, 0.55),   # hot pink
	]:
		_runner_frames.append(PixelSprites.zombie_frames(tint, Color(0.55, 1.0, 1.0)))


func setup(track: Node3D, player: Node3D, level: int) -> void:
	_track = track
	_player = player
	for z in _active:
		(z["node"] as Node3D).queue_free()
	_active.clear()
	for sm in _smashed:
		(sm["node"] as Node3D).queue_free()
	_smashed.clear()
	for p in _popups:
		(p["node"] as Node3D).queue_free()
	_popups.clear()
	_next_spawn = 0
	_weave_time = 0.0  # same seed, same weave: replays stay identical

	# Placement is fully random over the run (sorted afterwards for the
	# activation cursor): clumps and dead stretches emerge naturally, and
	# ~30% of rolls drop a tight pack of 2-4 -- a mini-horde to jump,
	# thread, or bowl through on a boost.
	_rng.seed = 5000 + level * 4409
	_spawns.clear()
	var count: int = base_count + (level - 1) * count_per_level
	var start_s := 70.0
	var end_s: float = track.arc_length - 40.0
	var half: float = track.road_width * 0.5
	var placed := 0
	while placed < count:
		var pack: int = 1 if _rng.randf() < 0.7 else _rng.randi_range(2, 4)
		pack = mini(pack, count - placed)
		var center := _rng.randf_range(start_s, end_s)
		for i in pack:
			var spawn_s := clampf(center + _rng.randf_range(-6.0, 6.0), start_s, end_s)
			var type := SpawnType.SIDE if _rng.randf() < 0.45 else SpawnType.AHEAD
			var lat: float
			if type == SpawnType.SIDE:
				lat = (half + 1.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
			else:
				lat = _rng.randf_range(-half + 1.5, half - 1.5)
			# Runners: rare fast sprinters, more common on later levels.
			var runner: bool = _rng.randf() < minf(0.10 + 0.03 * (level - 1), 0.3)
			# Flanking: pack members fan out evenly across the capped spread
			# (with a little jitter so the wall isn't a picket fence);
			# loners drift a touch off-lane so solo dodges vary too.
			var flank: float
			if pack > 1:
				flank = lerpf(-PACK_SPREAD, PACK_SPREAD, float(i) / float(pack - 1)) \
						+ _rng.randf_range(-0.2, 0.2)
			else:
				flank = _rng.randf_range(-0.8, 0.8)
			_spawns.append({
				"s": spawn_s,
				"lat": lat,
				"type": type,
				"runner": runner,
				"shamble": _rng.randf_range(3.2, 4.0) + (level - 1) * 0.1 if runner \
						else _rng.randf_range(1.9, 2.7) + (level - 1) * 0.12,
				"close": 3.5 if runner else 1.5,
				"flank": clampf(flank, -PACK_SPREAD, PACK_SPREAD),
				# Weave traits are rolled here even for runners (who ignore
				# them) so the RNG stream -- and thus the whole level layout
				# -- stays identical whatever mix of classes gets rolled.
				"weave_phase": _rng.randf_range(0.0, TAU),
				"weave_amp": _rng.randf_range(0.25, 0.6),
				"weave_rate": _rng.randf_range(0.6, 1.1),
			})
			placed += 1
	_spawns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["s"] < b["s"])


func _physics_process(delta: float) -> void:
	if _track == null or _player == null:
		return

	# Activate spawns entering range.
	while _next_spawn < _spawns.size() and _spawns[_next_spawn]["s"] < _player.s + ACTIVATION_RANGE:
		_activate(_spawns[_next_spawn])
		_next_spawn += 1

	_weave_time += delta
	var player_running: bool = _player.run_state == _player.RunState.RUNNING
	var half: float = _track.road_width * 0.5
	var i := _active.size() - 1
	while i >= 0:
		var z := _active[i]
		var zs: float = z["s"]
		var zlat: float = z["lat"]
		var shamble: float = z["shamble"]
		var close: float = z["close"]
		var gap: float = zs - _player.s

		# Runner lunge: a three-beat state machine on one timer. Stalking
		# runners inside range freeze (windup -- the player's read window),
		# then burst both sideways and down-road, then cool off before they
		# can try again.
		if z["runner"]:
			z["lunge_t"] -= delta
			match z["lunge_state"]:
				0:  # stalking / cooling down
					if player_running and gap > 0.0 and gap < LUNGE_RANGE and z["lunge_t"] <= 0.0:
						z["lunge_state"] = 1
						z["lunge_t"] = LUNGE_WINDUP
				1:  # windup: plant the feet so the pounce telegraphs
					close = 0.0
					shamble *= 0.3
					if z["lunge_t"] <= 0.0:
						z["lunge_state"] = 2
						z["lunge_t"] = LUNGE_DURATION
						var anim := z["anim"] as AnimatedSprite3D
						if anim:
							anim.speed_scale = z["anim_speed"] * 1.7
				2:  # lunge: fast, but never faster than the player can steer
					shamble *= LUNGE_SHAMBLE_MULT
					close *= LUNGE_CLOSE_MULT
					if z["lunge_t"] <= 0.0:
						z["lunge_state"] = 0
						z["lunge_t"] = LUNGE_COOLDOWN
						var anim := z["anim"] as AnimatedSprite3D
						if anim:
							anim.speed_scale = z["anim_speed"]

		# Predictive intercept: lead the player's carve by their lateral
		# velocity over the estimated time-to-contact. Behind the player the
		# gap (and so the lead) collapses to zero -- plain pursuit.
		var ttc: float = clampf(gap / maxf(_player.current_speed, 1.0), 0.0, TTC_MAX)
		var lead: float = RUNNER_LEAD if z["runner"] else SHAMBLER_LEAD
		var target: float = _player.lateral + _player._lateral_velocity * ttc * lead + z["flank"]
		# Shambler weave: a slow personal sine so the drift feels undead,
		# not servo-driven. Runners are too locked-on to wander.
		if not z["runner"]:
			target += sin(_weave_time * z["weave_rate"] + z["weave_phase"]) * z["weave_amp"]

		# The lateral cap is the fairness line: whatever multipliers stack,
		# a zombie can never out-turn the player's steer_speed.
		shamble = minf(shamble, MAX_LATERAL_SPEED)
		zlat = move_toward(zlat, clampf(target, -half + 0.4, half - 0.4), shamble * delta)
		if player_running and zs > _player.s:
			zs = maxf(zs - close * delta, _player.s)
		z["s"] = zs
		z["lat"] = zlat

		var xf: Transform3D = _track.transform_at(zs, zlat)
		var node := z["node"] as Node3D
		node.position = xf.origin  # billboard sprite faces the camera on its own

		# Contact damage -- unless the player is airborne over them.
		if player_running \
				and absf(zs - _player.s) < HIT_S_RANGE \
				and absf(zlat - _player.lateral) < HIT_LATERAL_RANGE \
				and _player.height < HIT_MAX_HEIGHT:
			if _player.is_boosting():
				# Boosting bowls straight through: launch it, no damage.
				_launch(z, xf)
				_active.remove_at(i)
				zombie_smashed.emit(xf.origin)
				i -= 1
				continue
			z["scored"] = true  # no style points off the zombie that got you
			_player.take_damage(damage_per_hit)

		# Style scoring, once per zombie, as the player clears it: jumped
		# clean over it, or squeaked past within near-miss range.
		if not z["scored"] and zs < _player.s - 0.6:
			z["scored"] = true
			if player_running:
				var lat_gap := absf(zlat - _player.lateral)
				if lat_gap < HIT_LATERAL_RANGE and _player.height >= HIT_MAX_HEIGHT:
					zombie_passed.emit("over")
				elif lat_gap < NEAR_MISS_RANGE:
					zombie_passed.emit("near")

		# Free zombies the player has passed.
		if zs < _player.s - DESPAWN_BEHIND:
			node.queue_free()
			_active.remove_at(i)
		i -= 1

	_update_smashed(delta)
	_update_popups(delta)


## Small floating "+points" text above a smashed zombie. Main calls this
## with the final (combo-multiplied) amount right after the smash scores.
func popup_points(pos: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 42
	label.outline_size = 10
	label.pixel_size = 0.02
	label.modulate = color
	label.outline_modulate = Color(0.05, 0.02, 0.09)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true  # never swallowed by the launched body
	label.position = pos + Vector3(0, 2.0, 0)
	add_child(label)
	_popups.append({"node": label, "t": 0.0})


func _update_popups(delta: float) -> void:
	var j := _popups.size() - 1
	while j >= 0:
		var p := _popups[j]
		p["t"] += delta
		var label := p["node"] as Label3D
		label.position.y += 1.6 * delta  # drift up as it fades
		var fade: float = 1.0 - p["t"] / POPUP_LIFETIME
		label.modulate.a = clampf(fade, 0.0, 1.0)
		if p["t"] >= POPUP_LIFETIME:
			label.queue_free()
			_popups.remove_at(j)
		j -= 1


## Ragdoll-ish arc for smashed zombies: up, aside, and down-road -- flipped
## upside down mid-flight, the classic 2D "launched" read.
func _launch(z: Dictionary, xf: Transform3D) -> void:
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var sprite := z["anim"] as AnimatedSprite3D
	if sprite:
		sprite.flip_v = true
	_smashed.append({
		"node": z["node"],
		"vel": xf.basis.y * 7.0 + xf.basis.x * side * 4.0 \
				- xf.basis.z * _player.current_speed * 0.5,
		"t": 0.0,
	})


func _update_smashed(delta: float) -> void:
	var j := _smashed.size() - 1
	while j >= 0:
		var sm := _smashed[j]
		sm["t"] += delta
		sm["vel"] += Vector3.DOWN * 20.0 * delta
		var node := sm["node"] as Node3D
		node.position += sm["vel"] * delta
		if sm["t"] > 1.3:
			node.queue_free()
			_smashed.remove_at(j)
		j -= 1


func _activate(spawn: Dictionary) -> void:
	var node := Node3D.new()
	add_child(node)

	# One billboard sprite from the shared tinted pools: sickly greens and
	# purples for shamblers, rusty reds for runners. Eyes are baked hot
	# pixels, so the stare comes free with the sprite.
	var is_runner: bool = spawn.get("runner", false)
	var pool := _runner_frames if is_runner else _shambler_frames
	var frames: SpriteFrames = pool[_rng.randi_range(0, pool.size() - 1)]
	var anim := PixelSprites.make_sprite(frames, 18)
	node.add_child(anim)

	if is_runner:
		anim.play(&"run")
		anim.speed_scale = _rng.randf_range(1.0, 1.2)
	else:
		anim.play(&"walk")
		anim.speed_scale = _rng.randf_range(0.95, 1.25)

	# The active dict is the zombie's whole brain: plan-time traits carried
	# over verbatim, plus the lunge state machine and the anim handle (the
	# lunge tell bumps speed_scale, so remember the resting value).
	_active.append({
		"node": node,
		"s": spawn["s"],
		"lat": spawn["lat"],
		"shamble": spawn["shamble"],
		"close": spawn.get("close", 1.5),
		"runner": is_runner,
		"flank": spawn.get("flank", 0.0),
		"weave_phase": spawn.get("weave_phase", 0.0),
		"weave_amp": spawn.get("weave_amp", 0.0),
		"weave_rate": spawn.get("weave_rate", 1.0),
		"lunge_state": 0,
		"lunge_t": 0.0,
		"anim": anim,
		"anim_speed": anim.speed_scale if anim else 1.0,
		"scored": false,
	})
