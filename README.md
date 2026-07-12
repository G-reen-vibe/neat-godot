# neat-godot

A full implementation of **NEAT** (NeuroEvolution of Augmenting Topologies) in Godot 4,
with many hyperparameter strategies (randomization methods, mutation operators,
crossover strategies, speciation strategies, evaluation strategies, generation
strategies), two forward-pass modes (standard time-stepped and topological-sort
loop-free), a built-in graph visualizer panel, and **real Godot physics** for
all physics-based environments.

## Architecture

The project uses a **hybrid evaluator architecture**:

- **Non-physics envs** (XOR) extend `NeatEnvironment` (RefCounted) and run
  synchronously inside the threaded `Evaluator` (uses `WorkerThreadPool`).
- **Physics envs** (CartPole, Acrobot, Pong, Spider 2D, Spider 3D) extend
  `NeatPhysicsEnvironment` (Node2D) or `NeatPhysicsEnvironment3D` (Node3D)
  and use **real Godot physics bodies** (RigidBody2D/3D, CharacterBody2D,
  PinJoint2D, ConeTwistJoint3D, HingeJoint3D, Area2D/3D sensors). They run
  inside the `SceneEvaluator`, which batches N env instances across N
  SubViewports (each with its own World2D/3D) so all N worlds step in
  parallel every physics frame. Speedup is achieved via `Engine.time_scale`
  and `Engine.physics_ticks_per_second`.

All UI is built as **proper Godot scenes** (`.tscn` files) — no programmatic
Control tree construction. Reusable components live in `ui/components/`,
screens in `ui/screens/`, and the main app composes them.

## Layout

```
src/
  core/         - Genome, NodeGene, ConnectionGene, InnovationTracker, ActivationFunctions
  random/       - Randomization methods (Gaussian / Triangular / Roulette / Inverse Roulette)
  mutation/     - Selectors + mutators for weights / connections / neurons / pruning / enabling
                  + mutation policies (General, Phased Pruning)
  crossover/    - Neuron-level and overall crossover strategies
  similarity/   - Standard + Percentage network similarity tests
  speciation/   - Single / K-Median / Standard / Purge speciation
  evaluation/   - Equal / Improvement-Rate / Novelty evaluation
  generation/   - Asexual / Crossover / Mixed generation (with elitism + interspecies)
  population/   - Top-level NEAT population orchestrator
  config/       - NeatConfig (hyperparameter container)
environments/
  environment.gd              - NeatEnvironment (RefCounted base, for non-physics)
  physics_environment.gd      - NeatPhysicsEnvironment (Node2D base, for 2D physics)
  physics_environment_3d.gd   - NeatPhysicsEnvironment3D (Node3D base, for 3D physics)
  evaluator.gd                - Evaluator (threaded, for RefCounted envs)
  scene_evaluator.gd          - SceneEvaluator (SubViewport batched, for physics envs)
  xor/                        - XOR env (RefCounted, no physics)
  cartpole/                   - CartPole env + .tscn (RigidBody2D + PinJoint2D)
  acrobot/                    - Acrobot env + .tscn (2 RigidBody2D + 2 PinJoint2D)
  pong/                       - Pong env + .tscn (CharacterBody2D + RigidBody2D)
  spider_2d/                  - Spider 2D env + .tscn (9 bodies + 8 PinJoint2D)
  spider_3d/                  - Spider 3D env + .tscn (9 bodies + 8 joints)
ui/
  main_app.tscn/gd           - Composes the 3 screens
  screens/                    - env_select, config, run screens (each a .tscn)
  components/                 - env_card, config_row, env_viewport, graph_view,
                                graph_visualizer, training_stats_view, save_load_view,
                                xor_truth_table (each a .tscn)
tests/                        - Headless test scenes (each is a tscn entry point)
```

## Running tests

Tests are run as Godot scenes (autoloads are not relied upon for testing).
After importing resources once with `--import`, run e.g.:

```bash
godot --headless --path . --import        # populate .godot/ cache
godot --headless --path . res://tests/test_full_e2e_v2.tscn
```

Key tests:
- `test_full_e2e_v2.tscn` — comprehensive end-to-end test of all 6 envs + save/load
- `test_cartpole_scene.tscn` — CartPole with real physics (Phase 1 PoC)
- `test_spider_2d_scene.tscn` — Spider 2D with real multi-body physics
- `test_spider_3d_scene.tscn` — Spider 3D with real 3D physics

## Running the app

```bash
godot --path .                            # opens the env selection screen
```

## License

MIT
