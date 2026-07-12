# neat-godot

A full implementation of **NEAT** (NeuroEvolution of Augmenting Topologies) in Godot 4,
with many hyperparameter strategies (randomization methods, mutation operators,
crossover strategies, speciation strategies, evaluation strategies, generation
strategies), two forward-pass modes (standard time-stepped and topological-sort
loop-free), and a built-in graph visualizer panel.

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
  forward/      - Time-stepped and topological-sort forward passes
  population/   - Top-level NEAT population orchestrator
  config/       - NeatConfig (hyperparameter container)
environments/
  xor/          - XOR test environment (headless-friendly)
  cartpole/     - CartPole physics environment
  acrobot/      - Acrobot physics environment
ui/             - Graph visualizer + main runner scene
tests/          - Headless test scenes (each is a tscn entry point)
```

## Running tests

Tests are run as Godot scenes (autoloads are not relied upon for testing).
After importing resources once with `--import`, run e.g.:

```bash
godot --headless --path . --import        # populate .godot/ cache
godot --headless --path . res://tests/test_xor.tscn
```

## License

MIT
