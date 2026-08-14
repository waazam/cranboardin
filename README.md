# cranboardin

**[▶ Play it in your browser](https://waazam.github.io/cranboardin/)**

A third-person downhill skating game built in Godot 4.7, with a retro
pixelated neon look. Bomb a long, curving city hill at dusk, dodge (or
jump over) the zombie horde shambling onto the street, grab cranberry
juice bottles to stay alive, and reach the finish line. Each level is a
longer hill with a bigger horde.

## Controls

**PC:**

| Key         | Action                                    |
|-------------|-------------------------------------------|
| `W`         | Accelerate                                 |
| `S`         | Brake                                      |
| `A` / `D`   | Steer left / right                         |
| `Space`     | Jump (clears zombies; coyote time + buffer)|
| `R`         | Restart / next level / retry               |

**Mobile (Android/iOS, auto-detected):** an on-screen d-pad -- left/
right steer, up/down accelerate/brake -- plus a jump button. Tap the
end screens to continue. Pixelation is chunkier on mobile (1/5 res vs
1/3 on desktop).

Every jump alternates between two air tricks: a **kickflip** (the
board rolls under you) and a **360 spin** (the whole rider spins).

## How it plays

- Speed ramps automatically from a base speed to a max as you descend
  (`Player.get_progress()` drives the curve); `W`/`S` push it further.
- **Zombies** spawn from the road sides and lurk ahead, shambling toward
  your lane. Contact costs 26 HP and a chunk of speed (with a brief
  blink-invulnerability window); at 0 HP you crash out -- game over,
  `R` to retry. Jumping clears them.
- **Drones** hover at head height over the road: stay low and slip
  underneath (worth points) -- jumping into one costs a hit.
- **Hazard barriers** stand across the lane in pink warning stripes:
  hurdle them airborne for points or steer around; riding into one
  costs a hit.
- **Boost pads** (cyan chevrons) surge you forward -- and while
  boosting you bowl straight through the horde. Rarer purple **mega
  pads** surge harder and longer. Neon **ramps** fling you into big
  assisted airs.
- The main menu lists every scoring move; chaining moves builds a
  combo multiplier up to x5.
- **Cranberry bottles** restore 30 HP -- or *overheal* you up to 150
  if you're already full (the HP bar turns cranberry).
- Reach the bottom to finish the level; `R` rolls you into the next,
  longer, more crowded one. A run takes roughly 1.5-2.5 minutes.
- All audio -- the retro synth loop, speed-scaled wind rush, ambient
  city bed, and hit/jump/pickup/finish stingers -- is procedurally
  synthesized by `tools/gen_audio.gd` (no third-party assets).
- The whole 3D world renders at 1/3 resolution into a SubViewport
  upscaled with nearest filtering: full-screen chunky pixels, crisp HUD.

## Project structure

```
scenes/
  menu.tscn           Entry scene: main menu -- the rider (sunglasses,
                      board at his side) against the neon backdrop, with
                      its own synth theme. Any input starts the game.
  main.tscn           The game: pixelation viewport wrapping the 3D
                      world, plus the HUD.
  player.tscn         CharacterBody3D shell for the player rig.
scripts/
  menu.gd             Builds the menu scene in code (character, glasses,
                      board, title UI, menu music).
  main.gd             Level loop (running / complete / game over), audio
                      stack, R-key handling.
  track.gd            Procedural curved road: wandering-heading downhill
                      centerline, road/curb/ground ribbons, neon center
                      line, finish banner, and city scenery along the
                      curve. transform_at(s, lateral) is the API everything
                      else positions itself with.
  player.gd           Spline-space movement (s / lateral / height), speed
                      ramp, jump, health + overheal, damage/death.
  character.gd        The rider: Godot's standard-animation-library
                      mannequin with a state machine (skate tuck, airborne,
                      hit, death, finish dance) and a sideways skate stance.
  lean_modifier.gd    SkeletonModifier3D that rolls the rider's spine bones
                      into turns (post-animation, so it blends with clips).
  skateboard.gd       The board: deck, kicktails, grip tape, trucks, and
                      wheels that spin to match ground speed.
  zombie_manager.gd   Zombie spawn plan + activation window + shamble AI +
                      contact damage (green-tinted mannequins, Walk anim).
  pickup_manager.gd   Cranberry bottle spawns, bob/spin, heal-on-touch.
  camera_rig.gd       Chase camera following the player's heading around
                      curves, with speed-based FOV kick.
  sky_background.gd   Neon dusk: purple/pink sky, fog, pixel-art skyline
                      strips with neon windows, clouds, birds -- follows
                      the player's position and heading.
  bird.gd             A single ambient bird (flock spawned by the sky).
  hud.gd              Code-built UI: speed/time/level, HP bar (cranberry
                      when overhealed), progress bar, messages, panels.
tools/
  gen_audio.gd        Offline synthesizer for all wav assets in audio/.
audio/                Generated music, ambience loops, and stingers.
Godot/                The engine's standard animation library mannequin
                      (rider + zombies).
docs/                 Web export served by GitHub Pages.
```

Everything except the mannequin GLB is generated at runtime from
primitives and pixel-by-pixel textures. Most tunables (speeds, track
length/curviness, zombie counts, heal amounts, colors, camera framing,
pixelation level) are `@export`s or constants on the relevant script.

## Opening it

Open `project.godot` in Godot 4.7+ and press Play, or open
`scenes/main.tscn` and run that. To rebuild the web export:

```
godot --headless --path . --export-release "Web"
```

To regenerate the audio:

```
godot --headless --path . -s res://tools/gen_audio.gd
```

## Ideas for next passes

- Real art for the board and bottles.
- Zombie variety: runners, big bruisers, groaning audio stingers.
- Score/combo system for near-misses and airtime.
- CRT shader (scanlines + curvature) over the pixelation viewport.
- GitHub Actions workflow to export and deploy Pages on push.
