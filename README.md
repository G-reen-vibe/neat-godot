# neat-godot

A full implementation of **NEAT** (NeuroEvolution of Augmenting Topologies) in Godot 4,
with many hyperparameter strategies (randomization methods, mutation operators,
crossover strategies, speciation strategies, evaluation strategies, generation
strategies), two forward-pass modes (standard time-stepped and topological-sort
loop-free), a built-in graph visualizer panel, and **real Godot physics** for
the physics-based environments (CartPole, Acrobot, Pong).

## Architecture

The project uses a **hybrid evaluator architecture**:

- **Non-physics envs** (XOR) extend `NeatEnvironment` (RefCounted) and run
  synchronously inside the threaded `Evaluator` (uses `WorkerThreadPool`).
- **Physics envs** (CartPole, Acrobot, Pong) extend
  `NeatPhysicsEnvironment` (Node2D) and use **real Godot physics bodies**
  (RigidBody2D, CharacterBody2D, PinJoint2D, Area2D sensors). They run
  inside the `SceneEvaluator`, which batches N env instances across N
  SubViewports (each with its own World2D) so all N worlds step in
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
  evaluator.gd                - Evaluator (threaded, for RefCounted envs)
  scene_evaluator.gd          - SceneEvaluator (SubViewport batched, for physics envs)
  xor/                        - XOR env (RefCounted, no physics)
  cartpole/                   - CartPole env + .tscn (RigidBody2D + PinJoint2D)
  acrobot/                    - Acrobot env + .tscn (2 RigidBody2D + 2 PinJoint2D)
  pong/                       - Pong env + .tscn (CharacterBody2D + RigidBody2D)
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
- `test_full_e2e_v2.tscn` — comprehensive end-to-end test of all 4 envs + save/load
- `test_cartpole_scene.tscn` — CartPole with real physics (Phase 1 PoC)

## Running the app

```bash
godot --path .                            # opens the env selection screen
```

## License

MIT
