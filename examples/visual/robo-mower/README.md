# Robo Mower Sandbox

This is a top-down robotics simulation environment:

- continuous robot pose over a discrete lawn grid
- obstacle and boundary collision checks
- world-truth coverage scoring and robot-owned belief map
- three raycast distance sensors
- boundary-wire style edge distance
- controller modes for random straight-line bounce, boundary following,
  belief-frontier search, belief-mapped coverage, and return-to-base
- custom boundary drawing with a default inset red boundary loop
- mouse editing for obstacles, boundary wire, and erase mode
- mouse HUD controls for mode, speed, pause, reset, grid, sensor rays, and brush
- live robot telemetry for blade state, wheel speeds, battery, rain, phase,
  and communication link
- environment toggles for rain and hills
- reflex-layer toggles for lift, bumper, communication loss, and reflex enable

Run from the repo root:

```sh
./kvist examples/visual/robo-mower/main.kvist -o /tmp/robo-mower.odin
odin run /tmp/robo-mower.odin -file
odin run /tmp/robo-mower.odin -file -- --robot bumper
```

Code layout:

- `world.kvist`: physical truth, scoring, grass/cut state, obstacles, wire,
  dock position, and simulated blade resistance.
- `robot.kvist`: robot pose, sensors, actuator telemetry, collision recovery,
  and kinematics.
- `belief.kvist`: robot-owned internal map built from observations.
- `planner.kvist`: behavior/product logic that requests commands.
- `motion.kvist`: reusable navigation commands such as point driving, wire
  following, homing, and undocking.
- `safety.kvist`: environment effects, reflex overrides, and physical power
  gating.
- `experiment.kvist`: headless controller comparison runner and metrics
  reporting.
- `main.kvist`: app state, UI, mission/docking phase, and frame/update loop.

Headless experiments:

```sh
./kvist examples/visual/robo-mower/main.kvist -o /tmp/robo-mower.odin
odin build /tmp/robo-mower.odin -file -out:/tmp/robo-mower
/tmp/robo-mower --headless --mode all --seconds 180 --runs 3
/tmp/robo-mower --headless --mode mapped --seconds 60 --runs 1 --obstacle --robot forward
/tmp/robo-mower --headless --mode mapped --seconds 60 --runs 1 --obstacle --robot bumper
/usr/bin/time -l /tmp/robo-mower --headless --mode mapped --seconds 180 --runs 10
```

Available modes are `random`, `boundary`, `frontier`, `mapped`, `return`, and
`all`. The runner prints one machine-readable `kind=run` row per run and one
`kind=avg` row per mode. `truth` is world-truth cut coverage, `known` is the
robot's belief-map coverage, `cutting_s` is time with the blade actually on,
and `update_us` is average simulation step cost without rendering. Add
`--obstacle` to place a deterministic obstacle across the first mapped lane.
Use `--robot forward` for a robot that can react to forward distance sensing,
or `--robot bumper` for a bumper-only mower that discovers obstacles by contact.

Controls:

- click the HUD buttons: mode, speed, pause, reset, grid, sensor rays, brush,
  environment, and reflex inputs
- `1`: random straight-line bounce controller
- `2`: boundary-following controller
- `3`: belief-frontier controller
- `4`: belief-mapped coverage controller
- `5`: return-to-base controller
- `[` / `]`: simulation speed down/up
- left mouse: paint the selected brush; wire paints exactly one grid cell
- right mouse: erase cells back to mowable grass
- `g`: grid overlay
- `v`: sensor rays
- `space`: pause
- `r`: reset

Controller intent:

- The default reset starts with grass and a boundary wire only. Use the obstacle
  brush to add obstacles for recovery tests.
- Random drives straight until collision. Obstacle collisions reverse briefly
  before an in-place turn; boundary-wire collisions turn in place without
  reversing.
- Boundary drives straight until it finds the red boundary wire, then tracks the
  configured boundary with the wire centered under the robot body. It follows
  rectangular wire corners as corners instead of smoothing across them.
- Frontier uses the robot belief map to continuously seek the nearest useful
  unknown grass target. When the target is aligned, it drives straight with
  synced wheels instead of applying a permanent search turn. In the forward
  sensor profile it treats the front ray as camera-like obstacle awareness and
  steers away from known or visible obstacles.
- Mapped maintains a robot-owned belief map from odometry, wire/distance
  sensors, and blade-load feedback. Its coverage plan is a configured
  edge-to-edge lane sweep over the known mowing zone. It drives straight across
  one lane, shifts 90 degrees down to the next lane at the same edge, then
  drives back; it does not read the world-truth cut grid.
- Obstacle contact uses shared physical recovery in all modes: blade off while
  reversing, then blade on during a forward bypass arc. Boundary recovery keeps
  arcing until it reacquires the wire, and mapped recovery keeps arcing until
  it reacquires the interrupted lane or shift line. If the robot contacts the
  obstacle again during the arc, it repeats recovery.
- Return disables the blade. Random, boundary, and frontier returns find and
  follow the wire home; mapped returns drive directly to the blue base from its
  pose model.
- Low battery is mission logic for every mowing mode: the robot switches to
  return-to-base before depletion.
- Obstacle contact is robot safety logic: the blade is disabled during obstacle
  hit recovery.
- The HUD `truth` metric is simulation scoring. The HUD `known` metric is the
  robot's internal belief coverage. In mapped mode the active lane is shown in
  the HUD and highlighted over the lawn.

Environment and physical simulation:

- Rain reduces available drive speed.
- Hills reduce drive speed and add a small steering drift.
- Blade load is simulated from real uncut grass under the mower and exposed to
  the robot as a sensor, like resistance/current draw would be on hardware.
- The base marker is on the boundary wire; the mower body docks just inside the
  wire so it does not spawn intersecting the boundary.
- Charging is a physical dock phase and takes simulation time.
- At 0% battery the physical power model stops all actuator output and disables
  the blade, independent of robot planner intent.
- After charging reaches 100%, the mower backs out from the dock and resumes
  its previous mowing mode.

Reflex simulation:

- Reflex enabled means the simulated safety layer can override planner commands.
- Lift or lost link stops drive and disables the blade.
- Bumper forces a slow reverse command with the blade disabled.
