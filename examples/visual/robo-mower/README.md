# Robo Mower

A top-down mower simulation with sensors, a robot-owned belief map, safety
overrides, several planners, and headless experiments.

## Run

```sh
./kvist compile examples/visual/robo-mower/main.kvist -o /tmp/robo-mower.odin
odin run /tmp/robo-mower.odin -file
```

Use `-- --robot bumper` to start with the bumper-only sensor profile.

## Code

- `world.kvist` - lawn, obstacles, wire, dock, and scoring
- `robot.kvist` - pose, sensors, actuators, and kinematics
- `belief.kvist` - the robot's internal map
- `planner.kvist` - coverage and return behavior
- `motion.kvist` - navigation commands
- `safety.kvist` - environment and reflex overrides
- `experiment.kvist` - headless comparisons
- `main.kvist` - application and interface

## Controls

- `1`–`5`: select random, boundary, frontier, mapped, or return mode
- `[` / `]`: change simulation speed
- `space`: pause
- `r`: reset
- `g`: toggle the grid
- `v`: toggle sensor rays
- left mouse: paint with the selected brush
- right mouse: erase

The interface also controls speed, obstacles, boundary wire, rain, hills, and
simulated lift, bumper, and communication-loss inputs.

## Headless Runs

```sh
./kvist compile examples/visual/robo-mower/main.kvist -o /tmp/robo-mower.odin
odin build /tmp/robo-mower.odin -file -out:/tmp/robo-mower
/tmp/robo-mower --headless --mode all --seconds 180 --runs 3
/tmp/robo-mower --headless --mode mapped --seconds 60 --runs 1 --obstacle
```

Modes are `random`, `boundary`, `frontier`, `mapped`, `return`, and `all`.
Output contains one `kind=run` row per run and one `kind=avg` row per mode.
Use `--robot forward` or `--robot bumper` to select the sensor profile.

The planner reads robot state and beliefs, not the simulation's world-truth
coverage grid. World truth is used only for scoring.
