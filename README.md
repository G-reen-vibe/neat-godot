# neat-godot

A full implementation of **NEAT** (NeuroEvolution of Augmenting Topologies) in Godot 4,
with many hyperparameter strategies (randomization methods, mutation operators,
crossover strategies, speciation strategies, evaluation strategies, generation
strategies), two forward-pass modes (standard time-stepped and topological-sort
loop-free), a built-in graph visualizer panel, and **real Godot physics** for
all environments.

## Environments

All environments are adapted from the [godot_rl](https://github.com/G-reen-vibe/godot_rl)
module and use real Godot 2D physics (RigidBody2D, PinJoint2D, etc.):

- **CartPole** — Balance a pole on a moving cart. 4 inputs, 1 output.
- **Pong** — Control a paddle to hit the ball past a stationary opponent. 5 inputs, 1 output.
- **LunarLander** — Fire thrusters to land safely on the pad. 6 inputs, 3 outputs.
- **BipedalWalker** — Walk forward on two legs without falling. 8 inputs, 4 outputs.

## Architecture

The project uses a **hybrid evaluator architecture**:

- **Non-physics envs** extend `NeatEnvironment` (RefCounted) and run synchronously
  inside the threaded `Evaluator` (uses `WorkerThreadPool`). Used only by backend
  unit tests (`MockTestEnv`).
- **Physics envs** extend `NeatPhysicsEnvironment` (Node2D) and use **real Godot
  physics bodies** (RigidBody2D, PinJoint2D, StaticBody2D). They run inside the
  `SceneEvaluator`, which batches N env instances across N SubViewports (each
  with its own World2D) so all N worlds step in parallel every physics frame.

### NEAT ↔ RL Adapter

The godot_rl envs use a different interface (`RLEnvironment` / `RLAgent` with
`PackedFloat32Array` observations/actions) than NEAT expects (Dictionary of
`{node_id: value}`). The `NeatRLAdapter` base class bridges this gap:

- Instantiates an RL env scene as a child.
- Converts NEAT `Dictionary<int, float>` state ↔ RL `PackedFloat32Array` observation.
- Converts NEAT `Dictionary<int, float>` output ↔ RL `PackedFloat32Array` action.
- Drives the RL env's `physics_step()` from `step_env()`.
- Accumulates the primary agent's per-step reward into cumulative fitness.
- For multi-agent envs (Pong), the genome controls one agent; others get zero action.

Per-env subclasses (`NeatCartPoleEnv`, `NeatPongEnv`, `NeatLunarLanderEnv`,
`NeatBipedalWalkerEnv`) specify the RL env scene and provide env-specific
visual state for the live visualization.

All UI is built as **proper Godot scenes** (`.tscn` files). Reusable components
live in `ui/components/`, screens in `ui/screens/`, and the main app composes them.

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
rl/                         - godot_rl module (RLEnvironment, RLAgent, RLResettableBody2D, envs)
environments/
  environment.gd              - NeatEnvironment (RefCounted base, for non-physics)
  physics_environment.gd      - NeatPhysicsEnvironment (Node2D base, for 2D physics)
  neat_rl_adapter.gd          - NeatRLAdapter (bridges RLEnvironment <-> NeatPhysicsEnvironment)
  evaluator.gd                - Evaluator (threaded, for RefCounted envs)
  scene_evaluator.gd          - SceneEvaluator (SubViewport batched, for physics envs)
  teleport_body_2d.gd         - TeleportBody2D (reliable reset for RigidBody2D)
  cartpole/                   - NeatCartPoleEnv adapter + .tscn
  pong/                       - NeatPongEnv adapter + .tscn
  lunar_lander/               - NeatLunarLanderEnv adapter + .tscn
  bipedal_walker/             - NeatBipedalWalkerEnv adapter + .tscn
ui/
  main_app.tscn/gd           - Composes the 3 screens
  screens/                    - env_select, config, run screens (each a .tscn)
  components/                 - env_card, config_row, env_viewport, graph_view,
                                graph_visualizer, training_stats_view, save_load_view
tests/                        - Headless test scenes (each is a tscn entry point)
```

## Running tests

Tests are run as Godot scenes (autoloads are not relied upon for testing).
After importing resources once with `--import`, run e.g.:

```bash
godot --headless --path . --import        # populate .godot/ cache
godot --headless --path . res://tests/test_full_gameplay.tscn
```

Key tests:
- `test_full_gameplay.tscn` — full end-to-end flow (training + live viz + cleanup) on all 4 envs
- `test_train_all_envs.tscn` — short NEAT training on all 4 envs
- `test_train_cartpole.tscn` — longer CartPole training (verifies learning)
- `test_adapter_*.tscn` — adapter mechanics for each env
- `test_core.tscn`, `test_mutation.tscn`, etc. — backend unit tests

## Running the app

```bash
godot --path .                            # opens the env selection screen
```

## License

MIT
