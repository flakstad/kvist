# Particle Simulation Results

Measured on June 6, 2026 from:

- Kvist worktree: `/Users/andreas/Projects/kvist/.worktrees/agent-particle-sim`
- Clojure repo: `/Users/andreas/Projects/fast`

All headless runs simulate 50,000 particles with rendering disabled. The in-app
elapsed time excludes process startup and warmup. CPU/RSS are sampled externally
with `scripts/particle_stats.sh`.

| System | Backend | Steps | Elapsed | ms/step | ns/particle | Particle updates/s | Max RSS | GC delta |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Kvist/Odin | `#soa[dynamic]Particle` | 20,000 | 9.023s | 0.451 | 9.023 | 110.8M | 6.2 MiB | n/a |
| Clojure/JVM | `fast.struct` primitive columns | 20,000 | 12.566s | 0.628 | 12.566 | 79.6M | 660.8 MiB | 122 |
| Clojure/JVM | persistent vector of maps | 5,000 | 16.753s | 3.351 | 67.013 | 14.9M | 840.4 MiB | 133 |

Commands:

```sh
cd /Users/andreas/Projects/kvist/.worktrees/agent-particle-sim
./kvist examples/visual/particle-sim.kvist -o /tmp/kvist-particle-sim.odin
odin build /tmp/kvist-particle-sim.odin -file -out:build/particle-sim
scripts/particle_stats.sh -- build/particle-sim --bench --particles 50000 --steps 20000
```

```sh
cd /Users/andreas/Projects/fast
/Users/andreas/Projects/kvist/.worktrees/agent-particle-sim/scripts/particle_stats.sh -- clojure -M:particle-sim --bench --backend struct --particles 50000 --steps 20000
/Users/andreas/Projects/kvist/.worktrees/agent-particle-sim/scripts/particle_stats.sh -- clojure -M:particle-sim --bench --backend persistent --particles 50000 --steps 5000
```

Notes:

- The Kvist example is written as Kvist forms and lowers to Odin; it does not
  use a whole-program `(odin "...")` escape.
- The Clojure `fast.struct` path is close on update-loop throughput, but the
  process footprint is dominated by the JVM: hundreds of MiB RSS versus single
  digit MiB for the native Odin binary in this run.
- The persistent path is still usable for design and boundary code, but it is
  much slower and allocates enough to drive frequent GC in this hot loop.
