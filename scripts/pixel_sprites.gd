class_name PixelSprites
## Procedural pixel-art sprite factory: string grids (one char per pixel)
## rendered to ImageTextures, bundled into SpriteFrames, and mounted on
## billboard AnimatedSprite3Ds. Supplies the horde -- shambling ALIENS and
## sprinting CYBORGS -- and world objects like the cranberry juice bottle.
## One flat quad per thing keeps the web build fast, and it IS the chunky
## 2D look.
##
## Everything is drawn in code like the rest of the game's art (audio,
## skyline, facades), so there are no image assets to ship.

const OUTLINE := Color(0.05, 0.04, 0.09)
const MOUTH := Color(0.25, 0.08, 0.1)
const METAL := Color(0.72, 0.73, 0.78)
const METAL_SHADE := Color(0.45, 0.46, 0.52)

# --- Alien frames -----------------------------------------------------------
# 16x20 canvas, front view shambling at the camera: dome head with glowing
# antenna tips, huge eyes, skinny neck and arms out Romero-style.

const ALIEN_WALK_1 := [
	"....E....E......",
	"....K....K......",
	"...KFFFFFFK.....",
	"..KFEEFFEEFK....",
	"..KfEEFFEEfK....",
	"...KfFFFFfK.....",
	".....KfOfK......",
	"..KFK.KCK.KFK...",
	"..KfKKCCCKKfK...",
	".....KCcCK......",
	".....KCCCK......",
	".....KcCcK......",
	".....KRRRK......",
	"....KRRKRRK.....",
	"....KRK.KRRK....",
	"....KRK..KRK....",
	"...KFFK..KRK....",
	".........KFFK...",
	"................",
	"................",
]

const ALIEN_WALK_2 := [
	"....E....E......",
	"....K....K......",
	"...KFFFFFFK.....",
	"..KFEEFFEEFK....",
	"..KfEEFFEEfK....",
	"...KfFFFFfK.....",
	".....KfOfK......",
	"..KFK.KCK.KffK..",
	"..KfKKCCCKKFK...",
	".....KCcCK......",
	".....KCCCK......",
	".....KcCcK......",
	".....KRRRK......",
	"....KRRKRRK.....",
	"...KRRK.KRK.....",
	"....KRK..KRK....",
	"....KFFK.KRK....",
	".........KFFK...",
	"................",
	"................",
]

# --- Cyborg frames ----------------------------------------------------------
# 16x20 canvas, hunched front-view sprint: boxy head with a glowing visor
# band, silver chest plating, one full-metal leg -- half machine, all speed.

const CYBORG_RUN_1 := [
	"................",
	"................",
	"...KKKKKKK......",
	"..KMFFFFFMK.....",
	"..KMEEEEEMK.....",
	"...KfffffK......",
	"....KfffK.......",
	"..KFK.KMMK.KFK..",
	"..KfKMMmMMKfK...",
	"....KMmMmMK.....",
	".....KMMMK......",
	".....KcCcK......",
	"....KRRMMK......",
	"...KRRKKMMK.....",
	"..KRRK..KMMK....",
	".KFFK....KmK....",
	".........KMMK...",
	"................",
	"................",
	"................",
]

const CYBORG_RUN_2 := [
	"................",
	"................",
	"...KKKKKKK......",
	"..KMFFFFFMK.....",
	"..KMEEEEEMK.....",
	"...KfffffK......",
	"....KfffK.......",
	"..KFK.KMMK.KFK..",
	"..KfKMMmMMKfK...",
	"....KMmMmMK.....",
	".....KMMMK......",
	".....KcCcK......",
	"....KMMRRK......",
	"...KMMKKRRK.....",
	"....KmK..KRRK...",
	"....KMMK..KRK...",
	"..........KFFK..",
	"................",
	"................",
	"................",
]

# --- Cranberry bottle -------------------------------------------------------
# 10x16 canvas: crimson juice, silver cap, a shimmering highlight that
# hops between frames so the pickup sparkles as it bobs.

const BOTTLE_1 := [
	"...KMMK...",
	"...KmmK...",
	"....KJK...",
	"...KJJJK..",
	"..KJJJJJK.",
	".KJhJJJJK.",
	".KJJJJJJK.",
	".KJJJJJJK.",
	".KJJJJJJK.",
	".KjJJJJjK.",
	".KjJJJJjK.",
	"..KKKKKK..",
	"..........",
	"..........",
	"..........",
	"..........",
]

const BOTTLE_2 := [
	"...KMMK...",
	"...KmmK...",
	"....KJK...",
	"...KJJJK..",
	"..KJJJJJK.",
	".KJJJJJJK.",
	".KJJJJhJK.",
	".KJJJJJJK.",
	".KJJJJJJK.",
	".KjJJJJjK.",
	".KjJJJJjK.",
	"..KKKKKK..",
	"..........",
	"..........",
	"..........",
	"..........",
]


## Renders a string grid into an Image. Rows may be ragged; the canvas is
## sized to the longest row. Unknown chars (and ".") stay transparent.
static func grid_image(rows: Array, palette: Dictionary) -> Image:
	var w := 0
	for row: String in rows:
		w = maxi(w, row.length())
	var img := Image.create_empty(w, rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if palette.has(ch):
				img.set_pixel(x, y, palette[ch])
	return img


static func _tex(rows: Array, palette: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(grid_image(rows, palette))


static func _add_anim(frames: SpriteFrames, anim: StringName, fps: float,
		loop: bool, grids: Array, palette: Dictionary) -> void:
	if not frames.has_animation(anim):
		frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	for grid: Array in grids:
		frames.add_frame(anim, _tex(grid, palette))


## Body tints stay in the flesh-tint family (clothes just darker, grayer
## steps of it) so the class color reads at distance through the fog.
static func _tint_palette(tint: Color, eye: Color) -> Dictionary:
	return {
		"K": OUTLINE,
		"F": tint.lightened(0.35),
		"f": tint.lightened(0.05),
		"E": eye,
		"O": MOUTH,
		"C": tint.darkened(0.1),
		"c": tint.darkened(0.3),
		"R": tint.darkened(0.35),
		"M": METAL,
		"m": METAL_SHADE,
	}


## One tinted alien variant: a "walk" loop.
static func alien_frames(tint: Color, eye: Color) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	_add_anim(frames, &"walk", 4.0, true, [ALIEN_WALK_1, ALIEN_WALK_2],
			_tint_palette(tint, eye))
	return frames


## One tinted cyborg variant: a "run" loop.
static func cyborg_frames(tint: Color, eye: Color) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	_add_anim(frames, &"run", 7.0, true, [CYBORG_RUN_1, CYBORG_RUN_2],
			_tint_palette(tint, eye))
	return frames


## The cranberry juice bottle: a slow two-frame sparkle loop.
static func bottle_frames() -> SpriteFrames:
	var palette := {
		"K": OUTLINE,
		"J": Color(0.78, 0.16, 0.3),   # cranberry juice
		"j": Color(0.55, 0.1, 0.22),
		"h": Color(1.0, 0.75, 0.85),   # glass highlight
		"M": METAL,
		"m": METAL_SHADE,
	}
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	_add_anim(frames, &"default", 3.0, true, [BOTTLE_1, BOTTLE_2], palette)
	return frames


## Billboard sprite mount, shared config: nearest filtering for hard texel
## edges, alpha-discard so depth sorting stays sane, unshaded for the flat
## 2D read (environment fog still applies, so distant sprites haze out).
## The offset pins the art's feet row to the node origin. Enemies at the
## default 0.092 m/texel stand ~1.65 m -- life-size.
static func make_sprite(frames: SpriteFrames, feet_row: int,
		pixel_size: float = 0.092) -> AnimatedSprite3D:
	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = frames
	sprite.pixel_size = pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Centered sprite: origin sits at canvas center. Lift it so the feet row
	# lands on the node origin instead.
	var h := frames.get_frame_texture(frames.get_animation_names()[0], 0).get_height()
	sprite.offset = Vector2(0.0, float(feet_row) - h * 0.5)
	return sprite
