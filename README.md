# cranboardin

A third-person downhill skating prototype built in Godot 4.7. Skate down a
long hillside street toward a distant city skyline, picking up speed as you
descend, dodging (or jumping) obstacles along the way.

## Controls

| Key         | Action                          |
|-------------|----------------------------------|
| `W`         | Accelerate                       |
| `S`         | Brake                            |
| `A` / `D`   | Steer left / right               |
| `Space`     | Jump (coyote time + jump buffer) |
| `R`         | Restart the run                  |

## How it plays

- Speed ramps automatically from a base speed up to a max speed as you
  progress down the hill (`Player.get_progress()` drives the curve), on top
  of which `W`/`S` nudge it further.
- Obstacles come in four flavors, scattered across 3 lanes with at least one
  lane always left open:
  - **Cone / Rail / Crate** -- hazards. Touching one costs you speed and
    gives a brief invulnerability window (it blinks).
  - **Ramp** (blue wedge) -- a boost pad. Touching one launches you upward,
    no penalty.
- Reach the bottom to finish the run and see your time, top speed, and
  crash count. Press `R` any time to restart (obstacles re-shuffle).

## Project structure

```
scenes/
  main.tscn          Entry scene (set as the project's main scene). Wires
                      Player/Track/Background/CameraRig/HUD together.
  player.tscn         CharacterBody3D + capsule collider. The visible
                      board/body/head/arms are built in code.
  obstacle.tscn       Area3D trigger; obstacle.gd swaps its mesh, collider
                      size, and behavior based on `type`.
scripts/
  main.gd             Assembles the scene, handles the R-to-restart key.
  player.gd           Movement, steering, jump, speed ramp, crash/boost
                      hooks; composes the visual rig from the two entities
                      below.
  character.gd        The rider: Godot's standard-animation-library
                      mannequin (Godot/AnimationLibrary_Godot_Standard.glb)
                      plus a small animation state machine -- skate tuck
                      (Crouch_Idle), airborne (Jump_Start), crash
                      (Hit_Chest), finish celebration (Dance).
  skateboard.gd       The board (deck/trucks/wheels) as its own entity,
                      with wheels that spin to match ground speed.
  track.gd            Procedurally builds the ramp, boundary walls, finish
                      banner, the lane-fair obstacle scatter, and roadside
                      scenery: city-canyon building slabs with pixel-art
                      window faces, streetlights, blocky trees, bushes,
                      hydrants, trash cans, manhole covers.
  obstacle.gd         The 4 obstacle types (CONE/RAIL/CRATE/RAMP).
  camera_rig.gd       Smoothed third-person chase camera with a speed-based
                      FOV kick.
  sky_background.gd   Procedural dusk sky plus a pixel-art city backdrop:
                      two parallax skyline strips and blocky clouds drawn
                      pixel-by-pixel into textures (NEAREST-filtered so
                      they stay crisp), riding along just behind the road.
  bird.gd             A single animated background bird (spawned in a flock
                      by sky_background.gd).
  hud.gd              All UI, built in code -- speed/timer/crash readout,
                      progress bar, crash flash, results panel.
```

Aside from the rider (Godot's bundled standard-animation-library mannequin
in `Godot/`), everything -- track, obstacles, board, skyline, clouds,
birds, UI -- is generated at runtime from primitive meshes and
pixel-by-pixel procedural textures. Most tunables (speeds, track length,
obstacle density, colors, camera framing, etc.) are exposed as `@export`
properties on the relevant node, so start in the Inspector before touching
code.

## Opening it

Open `project.godot` in Godot 4.7+ and press Play (it already targets the
Godot install/version configured on this machine), or open
`scenes/main.tscn` directly and run that scene.

## Ideas for next passes

- Swap the primitive obstacles/board for real art.
- Blend steering lean into the rider's skeleton (e.g. spine bones) instead
  of tilting the whole visual rig.
- Curve the track instead of a single straight slope.
- Sound: wind rush that scales with speed, crash/boost stingers, ambient
  city noise.
