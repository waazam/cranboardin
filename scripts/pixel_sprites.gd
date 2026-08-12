class_name PixelSprites
## Procedural pixel-art sprite factory: string grids (one char per pixel)
## rendered to ImageTextures, bundled into SpriteFrames, and mounted on
## billboard AnimatedSprite3Ds. Replaces the horde's skinned GLB mannequins
## -- one flat quad per zombie instead of a 53-bone rig, which is what makes
## the web build breathe, and it fits the chunky pixelated look.
##
## Everything is drawn in code like the rest of the game's art (audio,
## skyline, facades), so there are no image assets to ship.

const OUTLINE := Color(0.05, 0.04, 0.09)
const MOUTH := Color(0.25, 0.08, 0.1)

# --- Zombie frames ----------------------------------------------------------
# 16x20 canvas, front view shambling at the camera, Romero arms out.
# "F"/"f" are the flesh tint (filled per palette variant); "E" the hot eyes.

const ZOMBIE_WALK_1 := [
	"................",
	".....KKKKK......",
	"....KFFFFFK.....",
	"....KEFFEFK.....",
	"....KfFFFfK.....",
	".....KfOfK......",
	"..KFFK...KFFK...",
	"..KffKCCCKffK...",
	".....KCCCCK.....",
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

const ZOMBIE_WALK_2 := [
	"................",
	".....KKKKK......",
	"....KFFFFFK.....",
	"....KEFFEFK.....",
	"....KfFFFfK.....",
	".....KfOfK......",
	"..KFFK...KffK...",
	"..KffKCCCKFFK...",
	".....KCCCCK.....",
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

const ZOMBIE_RUN_1 := [
	"................",
	"................",
	"....KKKKK.......",
	"...KFFFFFK......",
	"...KEFFEFK......",
	"...KfFOOfK......",
	"....KfffK.......",
	"..KFK.KCCK.KFK..",
	"..KfKCCCCCKfK...",
	"....KCCcCCK.....",
	".....KCCCK......",
	".....KcCcK......",
	"....KRRRRK......",
	"...KRRKKRRK.....",
	"..KRRK..KRRK....",
	".KFFK....KRK....",
	".........KFFK...",
	"................",
	"................",
	"................",
]

const ZOMBIE_RUN_2 := [
	"................",
	"................",
	"....KKKKK.......",
	"...KFFFFFK......",
	"...KEFFEFK......",
	"...KfFOOfK......",
	"....KfffK.......",
	"..KFK.KCCK.KFK..",
	"..KfKCCCCCKfK...",
	"....KCCcCCK.....",
	".....KCCCK......",
	".....KcCcK......",
	"....KRRRRK......",
	"...KRRKKRRK.....",
	"....KRK..KRRK...",
	"....KFFK..KRK...",
	"..........KFFK..",
	"................",
	"................",
	"................",
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


## One tinted zombie variant: "walk" and "run" loops. The whole body stays
## in the flesh tint family (clothes just darker, grayer steps of it) so the
## class color reads at distance through the fog, the way the old whole-rig
## material tint did.
static func zombie_frames(tint: Color, eye: Color) -> SpriteFrames:
	var palette := {
		"K": OUTLINE,
		"F": tint.lightened(0.35),
		"f": tint.lightened(0.05),
		"E": eye,
		"O": MOUTH,
		"C": tint.darkened(0.1),
		"c": tint.darkened(0.3),
		"R": tint.darkened(0.35),
	}
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	_add_anim(frames, &"walk", 4.0, true, [ZOMBIE_WALK_1, ZOMBIE_WALK_2], palette)
	_add_anim(frames, &"run", 7.0, true, [ZOMBIE_RUN_1, ZOMBIE_RUN_2], palette)
	return frames


## Billboard sprite mount, shared config: nearest filtering for hard texel
## edges, alpha-discard so depth sorting stays sane, unshaded for the flat
## 2D read (environment fog still applies, so distant sprites haze out).
## The offset pins the art's feet row to the node origin. ~18 px of figure
## at 0.092 m/texel = a ~1.65 m zombie, right at life-size; the bright
## palette tints carry the at-distance readability.
static func make_sprite(frames: SpriteFrames, feet_row: int) -> AnimatedSprite3D:
	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = frames
	sprite.pixel_size = 0.092
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
