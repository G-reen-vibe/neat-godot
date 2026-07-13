# NEAT Backend Specification — As Implemented

This document specifies the exact behavior of the NEAT backend in `neat-godot` as it currently exists. All algorithms, default values, edge cases, and safety checks are documented here so the backend can be reproduced from scratch.

---

## Table of Contents

1. [Core Data Structures](#1-core-data-structures)
2. [Innovation Tracker](#2-innovation-tracker)
3. [Activation Functions](#3-activation-functions)
4. [Forward Pass](#4-forward-pass)
5. [Population Initialization](#5-population-initialization)
6. [Evolution Loop](#6-evolution-loop)
7. [Randomization Methods](#7-randomization-methods)
8. [Mutation System](#8-mutation-system)
9. [Crossover](#9-crossover)
10. [Similarity Tests](#10-similarity-tests)
11. [Speciation](#11-speciation)
12. [Evaluation Strategies](#12-evaluation-strategies)
13. [Generation Strategies](#13-generation-strategies)
14. [Dead Node Cleanup](#14-dead-node-cleanup)
15. [Configuration Defaults](#15-configuration-defaults)
16. [Evaluators](#16-evaluators)

---

## 1. Core Data Structures

### NodeGene

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | int | 0 | Universally unique node ID (assigned by InnovationTracker) |
| `kind` | enum | HIDDEN | One of: `INPUT`, `BIAS`, `HIDDEN`, `OUTPUT` |
| `activation` | int | TANH | Activation function ID (see §3) |
| `depth` | int | -1 | Cached topological depth (0 = input/bias, increases along connections). -1 = not computed. |
| `bias` | float | 0.0 | Bias term added to pre-activation sum. Ignored for INPUT/BIAS nodes. |
| `times_selected` | int | 0 | Counter for "Least Common" selectors (unused in current implementation, reserved). |

**Methods:**
- `is_input_like() -> bool`: Returns true if kind is INPUT or BIAS.
- `duplicate() -> NodeGene`: Deep copy.

### ConnectionGene

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `innovation` | int | 0 | Universally unique innovation number (assigned by InnovationTracker) |
| `from_node` | int | 0 | Source node ID |
| `to_node` | int | 0 | Target node ID |
| `weight` | float | 0.0 | Connection weight |
| `enabled` | bool | true | Whether this connection participates in the forward pass |
| `times_selected` | int | 0 | Counter for "Least Common" selectors (unused, reserved). |

### Genome

Stores `nodes: Dictionary<int, NodeGene>` and `connections: Dictionary<int, ConnectionGene>` (keyed by innovation number) for O(1) lookup.

**Cached graph state (lazily rebuilt):**
- `_adj_out: Dictionary<int, Array<ConnectionGene>>` — outgoing adjacency (enabled connections only)
- `_adj_in: Dictionary<int, Array<ConnectionGene>>` — incoming adjacency (enabled connections only)
- `_topo_order: Array<int>` — topological order of node IDs
- `_topo_dirty: bool` — true if structure changed since last topo sort
- `_has_loop: bool` — true if the enabled subgraph contains a cycle
- `_activation_cache: Dictionary<int, float>` — activation values for forward pass

**Genome-level fields:**
- `fitness: float = 0.0`
- `adjusted_fitness: float = 0.0`
- `species_id: int = -1`
- `parent_species_id: int = -1` — used by Standard speciation as a fast first-match candidate
- `metadata: Dictionary = {}` — free-form, for novelty descriptors etc.

**Key methods:**
- `add_node(n)`, `remove_node(id)` — removes all connections touching the node
- `add_connection(c)`, `remove_connection(innov)`
- `enabled_connections() -> Array`, `disabled_connections() -> Array`
- `would_create_loop(from, to) -> bool` — DFS from `to` to see if `from` is reachable
- `compute_topological_order() -> bool` — Kahn's algorithm; returns false if cycle
- `forward(inputs, mode, steps) -> Dictionary` — see §4
- `duplicate() -> Genome` — deep copy
- `candidate_sources() -> Array<int>` — all non-OUTPUT node IDs
- `candidate_targets() -> Array<int>` — all non-INPUT/BIAS node IDs
- `candidate_new_connections(allow_loop_check) -> Array<Vector2i>` — all (from, to) pairs not present, optionally excluding loop-creating pairs
- `prune_disconnected_hidden_nodes() -> int` — see §14

---

## 2. Innovation Tracker

A single `InnovationTracker` instance is owned by the `Population` and shared across all genomes via `MutationContext`. This ensures **universal node indexing**: the same connection or split always yields the same ID, forever.

**Fields:**
- `_next_conn_innov: int = 0` — next connection innovation number
- `_next_node_id: int = 0` — next node ID
- `_conn_innov: Dictionary<String, int>` — maps `"from,to"` → innovation number
- `_split_node: Dictionary<int, int>` — maps connection innovation → split node ID

**Methods:**

| Method | Behavior |
|--------|----------|
| `get_connection_innov(from, to) -> int` | Returns existing innovation for (from, to), or allocates a new one. |
| `peek_connection_innov(from, to) -> int` | Returns existing innovation or -1. **Does NOT allocate.** Used by selectors. |
| `get_split_node_id(conn_innov) -> int` | Returns existing split node ID for the connection, or allocates a new one. |
| `peek_split_node_id(conn_innov) -> int` | Returns existing or -1. **Does NOT allocate.** Used by selectors. |
| `new_node_id() -> int` | Allocates a brand-new node ID (for inputs/outputs at init). |
| `reserve_node_id(id)` | Pre-reserves a node ID so future allocations don't collide (used at init). |
| `reserve_connection_innov(innov)` | Pre-reserves an innovation number. |
| `clear()` | Resets everything. |

**Key invariant:** Node IDs and connection innovations use **separate counters** — no collision is possible.

---

## 3. Activation Functions

14 activation functions, dispatched via an int enum + match statement for speed:

| Enum | Name | Formula |
|------|------|---------|
| LINEAR | linear | `x` |
| ABSOLUTE | abs | `|x|` |
| SQUARED | squared | `x²` |
| CUBED | cubed | `x³` |
| BINARY_STEP | step | `1.0 if x ≥ 0 else 0.0` |
| GAUSSIAN | gaussian | `exp(-x²/2)` |
| SIGMOID | sigmoid | `1 / (1 + exp(-x))` |
| TANH | tanh | `tanh(x)` |
| RELU | relu | `max(0, x)` |
| LEAKY_RELU | leaky_relu | `x if x > 0 else 0.01 * x` |
| ELU | elu | `x if x > 0 else exp(x) - 1` |
| SELU | selu | `1.0507 * (x if x > 0 else 1.6733 * (exp(x) - 1))` |
| GELU | gelu | `0.5 * x * (1 + tanh(0.7979 * (x + 0.0447 * x³)))` |
| SWISH | swish | `x / (1 + exp(-x))` |

---

## 4. Forward Pass

Two modes, selected by `config.forward_mode`:

### Topological mode (default, recommended)

1. Call `compute_topological_order()`. If it returns false (cycle detected), fall back to timestep mode.
2. Seed activation cache: INPUT nodes get `inputs[id]`, BIAS nodes get `1.0`, all others get `0.0`.
3. Iterate nodes in topological order. For each non-input-like node:
   - `s = node.bias + Σ(connection.weight * activation_cache[connection.from_node])` over all incoming **enabled** connections.
   - `activation_cache[node.id] = ActivationFunctions.activate(node.activation, s)`
4. Return `{output_node_id: activation}` for all OUTPUT nodes.

**Single sweep, deterministic, no iteration needed.** Requires `forbid_loops = true` to guarantee acyclicity.

### Timestep mode

1. Rebuild adjacency if dirty.
2. Seed: INPUT nodes get `inputs[id]`, BIAS nodes get `1.0`, all others get `0.0`.
3. For `steps` iterations (default 5):
   - For each non-input-like node: compute `s = bias + Σ(weight * prev_activation[from])` and apply activation.
   - All nodes update **synchronously** using the previous step's activations.
4. Return output activations.

---

## 5. Population Initialization

`Population.initialize()` does:

1. Reset: `generation = 0`, `best_fitness = -1e9`, `best_genome = null`, clear species and genomes.
2. Reserve node IDs for inputs (IDs `0..num_inputs-1`), bias (ID `num_inputs`), and outputs (IDs `num_inputs+1..num_inputs+num_outputs`).
3. For each of `population_size` genomes, call `_build_random_genome()`.
4. Speciate the initial population.

### `_build_random_genome(input_ids, bias_id, output_ids)`

1. Create a bare genome with INPUT, BIAS, and OUTPUT nodes (no connections).
2. Add `randi_range(init_min_hidden_nodes, init_max_hidden_nodes)` hidden nodes using `tracker.new_node_id()`.
3. Build the list of all feasible (src, dst) pairs:
   - src ∈ inputs + bias + hidden (any non-OUTPUT node)
   - dst ∈ outputs + hidden (any non-INPUT/BIAS node)
   - No self-loops (src ≠ dst)
   - In topological mode: only forward edges allowed (INPUT/BIAS → anything; HIDDEN → HIDDEN with higher ID, or HIDDEN → OUTPUT; never backward)
4. Shuffle the candidate pairs (Fisher-Yates with the Population's RNG).
5. Pick the first `randi_range(init_min_connections, init_max_connections)` pairs (clamped to available).
6. For each pair, allocate innovation via `tracker.get_connection_innov(from, to)` and add a connection with weight `randf_range(init_weight_min, init_weight_max)`.
7. **Call `g.prune_disconnected_hidden_nodes()`** to remove any hidden nodes that didn't get both an incoming and outgoing connection (see §14).

---

## 6. Evolution Loop

```
Population.evolve():
    generation += 1
    for each species: sp.record_generation_stats()
    evaluation.evaluate(species_list, population_size, ctx)
    if PhasedPruning: advance_generation()
    new_genomes = generation_strategy.produce(species_list, ctx)
    genomes = new_genomes
    species_list = speciation.speciate(genomes, species_list, similarity, ctx)
```

**`Species.record_generation_stats()`:**
- `cur_best = max(member.fitness for member in members)`
- `best_fitness = max(best_fitness, cur_best)`
- If `cur_best > best_fitness_history[-1] + 1e-9`: `staleness = 0`, else `staleness += 1`
- `best_fitness_history.append(cur_best)`
- `average_fitness = sum(fitness) / member_count`
- `average_fitness_history.append(average_fitness)`

**Training loop (in RunScreen):**
1. Evaluate all genomes → get fitnesses
2. Set `genome.fitness` for each
3. Update `pop.best_fitness` / `pop.best_genome`
4. **Record stats** (BEFORE evolve, so we capture evaluated fitnesses)
5. `pop.evolve()`

---

## 7. Randomization Methods

Used by generation strategies to pick parents. All take `(items, values, rng)` and return a single item.

### Gaussian
- Compute mean and std of `values`.
- Sample `s = mean + randfn() * std`.
- Return the item whose value is closest to `s`.
- If all values equal (std ≈ 0), uniform random.

### Triangular
- `a = n` (item count)
- `b = 200 / a²`
- `seed = randf(0, 100)`
- `disc = (b*a)² - 2*b*seed` (clamped to ≥ 0)
- `index = int((b*a - sqrt(disc)) / b)`, clamped to `[0, n-1]`
- Returns item at that index. Biases toward index 0 (fittest, since members are sorted by fitness descending).

### Roulette
- `sum = Σ(max(0, v) for v in values)`
- If sum ≈ 0: uniform random.
- `r = randf() * sum`, walk the array, return the item where the cumulative sum first exceeds `r`.
- Negative values are treated as 0 (cannot be selected).

### Inverse Roulette
- `max_v = max(values)`
- Each value replaced by `(max_v - value)`.
- Standard roulette on the inverted values.
- Items with smaller original values become more likely.

### Uniform
- `items[randi_range(0, n-1)]`

---

## 8. Mutation System

Each mutation type has a **selector** (chooses what to mutate) and a **mutator** (applies the mutation). Selectors are given a `MutationContext` with `rng`, `tracker`, `species`, `forward_mode`, `forbid_loops`, and `rate_multiplier`.

### 8.1 Count Selection Formula

All selectors use this formula to decide how many items to select:

```
eff_rate = rate * ctx.rate_multiplier
if eff_rate < 1.0:
    n = 1 if randf() < eff_rate else 0
else:
    n = int(eff_rate)
n = max(min_count, n)
n = min(n, total_available)
```

**Interpretation:** When `rate < 1.0`, it's the probability of applying exactly 1 mutation (standard NEAT). When `rate ≥ 1.0`, it's a count. `min_count` is a floor.

### 8.2 Weight Mutation

**Weight Selectors:**

| Selector | Behavior |
|----------|----------|
| Standard | Uniform random over enabled connections. |
| Capped | Biases toward connections pinned at `min_weight`/`max_weight`. Self-adjusts rate: if >30% pinned, multiply rate by 2; if <5% pinned, multiply by 0.5. |
| All | Returns ALL enabled connections (used when `weight_mutation_mode = "all"`). |

**Weight Mutators:**

| Mutator | Behavior |
|---------|----------|
| Standard | `weight = clamp(weight + randf(min_delta, max_delta), clamp_min, clamp_max)` |
| Normal | `weight = clamp(weight + mean + randfn() * std, clamp_min, clamp_max)` |
| SafeGradient | Tentatively add connection, evaluate output norm with ±delta perturbation, accept the direction with larger output change. Revert if no change. |

**Weight mutation modes:**
- `"single"` (default): Select 1 (or `min_count`) connection(s), apply full delta.
- `"all"`: Apply a small perturbation (scaled by `weight_mutation_all_scale = 0.1`) to ALL enabled connections.

**Default values (UI config):**
- `weight_mutation_rate = 0.8`
- `weight_mutation_min = 1`
- `weight_mutation_delta_min = -0.5`, `max = 0.5`
- `weight_mutation_normal_std = 0.5`

### 8.3 Connection Mutation

**Connection Selectors** (select which NOT-YET-EXISTING connections to add):

| Selector | Behavior |
|----------|----------|
| Standard | Uniform random over `genome.candidate_new_connections(forbid_loops)`. |
| LeastUsed | Biases toward pairs where `degree(from) + degree(to)` is small. Weight = `1 / (1 + deg_sum)`. Weighted sample without replacement. |
| LeastCommon | Biases toward innovation numbers selected infrequently in this species. Uses `tracker.peek_connection_innov()` (no allocation). Weight = `1 / (1 + selection_count)`. |

**Connection Mutators:**

| Mutator | Behavior |
|---------|----------|
| Standard | Weight = `randf(min_weight, max_weight)`. |
| Normal | Weight = `mean + randfn() * std`. |
| SafeGradient | Tentatively add with weight 0, evaluate ±delta, keep the direction that changes output, revert if no change. |

**Safety:** If `ctx.forbid_loops` is true, `genome.would_create_loop(from, to)` is checked before adding. Skip if it would create a loop.

**Default values (UI config):**
- `connection_mutation_rate = 0.05` (NEAT paper: 3-5%)
- `connection_mutation_min = 0`
- `connection_weight_min = -1.0`, `max = 1.0`

### 8.4 Neuron Mutation

Splits existing enabled connections to insert hidden neurons.

**Neuron Selectors** (select which enabled connections to split):

| Selector | Behavior |
|----------|----------|
| Standard | Uniform random over enabled connections. |
| LeastCommon | Biases toward connections whose would-be split node ID has been split infrequently. Uses `tracker.peek_split_node_id()` (no allocation). |

**Neuron Mutator (Standard only):**

For each selected connection `c` (from `a` to `b` with weight `w`):
1. `split_node_id = tracker.get_split_node_id(c.innovation)` — universal ID.
2. If genome already has this node, skip (already split).
3. Create hidden node with `split_node_id`, kind HIDDEN, activation = `config.hidden_activation`.
4. Disable the original connection `c`.
5. Add connection `(a → split_node_id)` with weight `1.0`.
6. Add connection `(split_node_id → b)` with weight `w` (original weight).
7. If species context available: `species.increment_node_selection(split_node_id)`.

**Default values (UI config):**
- `neuron_mutation_rate = 0.03` (NEAT paper: 0.5-3%)
- `neuron_mutation_min = 0`

### 8.5 Prune Mutation

**Prune Selectors** (select which connections to prune):

| Selector | Behavior |
|----------|----------|
| Standard | Uniform random over ALL connections (enabled + disabled). |
| LeastWeight | Biases toward connections with small `|weight|`. Weight = `1 / (|w| + 0.01)`. |

**Prune Mutators:**

| Mutator | Behavior |
|---------|----------|
| Base (default) | Removes enabled connections only if **safe**: both endpoints must have at least one other enabled connection in the same direction. Disabled connections removed unconditionally. |
| PruneDisabled | Removes only if the connection is currently disabled. |
| PruneNonEssential | Checks `_is_safe_to_remove()` (both endpoints have other enabled connections) AND that every output remains reachable from some input via BFS. Re-adds if removal isolates an output. |
| MergePair | Finds hidden nodes with exactly 1 incoming and 1 outgoing connection. Removes the node and its two connections, adds a direct connection `(in_c.from → out_c.to)` with weight `in_c.weight * out_c.weight`. **This is the ONLY prune mutator allowed to change graph shape.** |

**`_is_safe_to_remove(genome, conn)` (static):**
- Returns true only if `conn.from_node` has at least one OTHER enabled outgoing connection AND `conn.to_node` has at least one OTHER enabled incoming connection.

**Default values (UI config):**
- `enable_prune_mutation = false`
- `prune_mutation_rate = 0.01`
- `prune_mutator_method = "disabled"`

### 8.6 Enable Mutation

Re-enables disabled connections.

**Enable Selector (Standard only):** Uniform random over disabled connections.

**Application:** For each selected disabled connection, if `ctx.forbid_loops` and `genome.would_create_loop(from, to)`, skip. Otherwise set `enabled = true`.

**Default values (UI config):**
- `enable_mutation_rate = 0.05`
- `enable_mutation_min = 0`

### 8.7 Mutation Policies

Combine all selectors/mutators and apply them to a genome.

**General (standard):**
- Fields: `rate_multiplier = 1.0`, `stacked = true`.
- If `stacked`: apply weight, connection, neuron, prune, enable mutations in sequence.
- If not stacked: pick one configured mutation type uniformly at random and apply only that.
- **After all mutations:** call `genome.prune_disconnected_hidden_nodes()` to clean up any dead nodes created by prune mutations.

**PhasedPruning:**
- Alternates between growth and pruning phases, each `phase_length` generations long.
- Growth phase: apply weight, connection, neuron mutations with `growth_rate_multiplier = 1.0`.
- Pruning phase: apply prune, enable mutations with `pruning_rate_multiplier = 3.0`.
- **After all mutations:** call `genome.prune_disconnected_hidden_nodes()`.
- `advance_generation()` is called externally by `Population.evolve()`.

---

## 9. Crossover

### 9.1 Neuron-Level Crossover (weight of shared connections)

| Strategy | Behavior |
|----------|----------|
| Standard | Randomly pick `w_a` or `w_b` (50/50). |
| StandardAll | Per-neuron: choose parent A or B (50/50). All shared connections touching that neuron take their weight from the chosen parent. If endpoints disagree, fall back to random. |
| Average | `(w_a + w_b) / 2` |
| BiasedAverage | `lerp(w_b, w_a, bias)` where `bias = lerp(0.5, clamp(0.5 + 0.5*(fit_a-fit_b)/(|fit_a|+|fit_b|+eps), 0, 1), bias_strength)` |

### 9.2 Overall Crossover (topology)

All implementations:
1. Child inherits the **union** of nodes from both parents (activation/kind from fitter parent for shared nodes).
2. Connections handled per strategy (see below).
3. **After crossover:** call `child.prune_disconnected_hidden_nodes()` to remove nodes that lost their connections.

| Strategy | Behavior |
|----------|----------|
| Fitter | Shared connections get neuron-crossover weight; disjoints/excess inherited from the fitter parent only. |
| Bigger | Same as Fitter but uses the bigger (more connections) parent as the topology source. |
| Combine | Shared + as many disjoints as possible from BOTH parents. If a loop forms, skip that disjoint. |
| Excluded | Shared + minimal disjoints. Start with no disjoints; if an output has no incoming path, add disjoints from the more-fit parent one-by-one (innovation order) until connected. Skip any that would create a loop. |

**Loop checking:** All strategies check `ctx.forbid_loops and child.would_create_loop(from, to)` before adding a disjoint. If it would create a loop, the connection is skipped.

---

## 10. Similarity Tests

### Standard (NEAT paper)

```
delta = (c1 * E + c2 * D) / N + c3 * W_avg
```

Where:
- `E` = number of excess genes (innovations beyond the other genome's max)
- `D` = number of disjoint genes (innovations in one but not the other, within range)
- `N` = `max(|A|, |B|)` if both genomes have > `n_threshold` (20) genes, else 1
- `W_avg` = average absolute weight difference over shared (matching) connections
- `c1 = 1.0`, `c2 = 1.0`, `c3 = 0.4` (NEAT paper defaults)

### Percentage

```
diff = Σ |w_a - w_b|  over all innovations in either (missing → weight 0)
total = Σ |w_a| + |w_b|  over all innovations in either
pct = diff / total  (0 if total ≈ 0 and diff ≈ 0; 1 if total ≈ 0 and diff > 0)
```

Returns a value in [0, 1].

---

## 11. Speciation

### 11.1 Standard

**Fields:**
- `compatibility_threshold = 3.0` (dynamically adjusted)
- `target_species_count = 10`
- `threshold_up_speed = 0.3`, `threshold_down_speed = 0.3`
- `max_species_count = 20`
- `merge_ratio = 0.5`
- `min_threshold = 0.5`, `max_threshold = 30.0`

**Algorithm:**
1. Reset prev species members; keep representatives.
2. For each genome:
   a. Try parent's species first (optimization): if `distance(genome, species.representative) < threshold`, assign.
   b. Try all other species: if `distance < threshold`, assign.
   c. If no match: create new species with this genome as representative.
3. Remove empty species.
4. Keep previous representatives (standard NEAT practice for stability). Only set new representative if species is brand new.
5. **Dynamic threshold adjustment:**
   - If `count > target`: `threshold += threshold_up_speed * (count / target)`
   - If `count < target`: `threshold -= threshold_down_speed * (target / count)`
   - Clamp to `[min_threshold, max_threshold]`.
6. If `count > target`: merge similar species:
   - `merge_threshold = threshold * merge_ratio * (count / target)` (more aggressive when far above target)
   - For each pair of species, if `distance(representative_a, representative_b) < merge_threshold`, merge B into A.

### 11.2 Purge (first generation only)

**Fields:**
- `standard: Standard` — internal delegate for subsequent generations
- `first_generation: bool = true`
- `mutation_policy: MutationPolicy` — used to mutate seeds
- `ideal_threshold: float = 3.0`
- `target_species_count: int = 10`

**First generation algorithm:**
1. Sort genomes by fitness descending.
2. Pick top N = `min(target_species_count, pop_size)` as seeds.
3. Apply mutations to each seed so they diverge slightly.
4. Fill the remaining population slots with mutated clones of the seeds (round-robin). Each clone's `parent_species_id` = its seed index.
5. **Replace the genomes array in-place** (the caller sees the new genomes).
6. Compute `ideal_threshold`:
   - If only 1 seed: use `standard.compatibility_threshold`.
   - Else: `ideal_threshold = min(pairwise_distance(seeds))` — the minimum pairwise distance, which is the largest value that keeps all N seeds in separate species.
   - **Clamp** to `[standard.min_threshold, standard.max_threshold]`.
7. Set `standard.compatibility_threshold = ideal_threshold`.
8. Build N species, each with its seed as representative. Assign each genome to its seed's species.
9. Set `first_generation = false`.

**Subsequent generations:** Delegate to `standard.speciate()`.

### 11.3 KMedian

K-median clustering. Very slow: O(K × N × iterations).

1. Pick K random genomes as initial medioids.
2. For `iterations` (5) rounds:
   a. Assign each genome to nearest medioid (by similarity distance).
   b. Recompute each medioid as the member with min total distance to others.
3. Match new clusters with old species by medioid similarity; transfer `id`, `best_fitness`, `best_fitness_history`, `staleness`, `selection_counts`.

### 11.4 Single

All genomes in one species. Testing purposes only.

---

## 12. Evaluation Strategies

Score each species to allocate children for the next generation. Three categories: children count, mutation rate, delete species.

### Equal

All species scored equally. Children split evenly:
- `per = total_population / num_species`
- `remainder = total_population - per * num_species`
- First `remainder` species get `per + 1` children; rest get `per`.
- All species get `mutation_rate_multiplier = 1.0`.

### ImprovementRate

- `improvement = (cur_avg - prev_avg) / (|prev_avg| + 1e-6)`
- `score = max(0, cur_avg) * (1 + max(0, improvement))`
- If `improvement ≤ 0`: `mutation_rate_multiplier = 2.0` (encourage exploration)
- If `improvement > 0`: `mutation_rate_multiplier = 0.5`
- Cull species with `score < 0.01` (only after we have history, i.e., `best_fitness_history.size() >= 2`). Never cull all; keep at least the best one.
- Allocate children proportionally to scores.

### Novelty

- `novelty = 1 + novelty_weight * (avg_distance_to_other_species_representatives)`
- `score = max(0, avg_fitness) * novelty`
- `mutation_rate_multiplier = 1 / (1 + novelty * 0.1)` (more novel → lower mutation rate)
- Allocate children proportionally to scores.

### Proportional Allocation (`_allocate_proportional`)

1. Reset all `allocated_children = 0`.
2. If `total_score ≈ 0`: equal split fallback.
3. `share = round(score_i / total_score * total_population)` for each species.
4. Adjust for rounding: add/subtract the difference from the largest species.

---

## 13. Generation Strategies

All strategies:
1. For each species with `allocated_children > 0`:
   a. Sort members by fitness descending.
   b. **Elitism:** Copy top `elite_count` members unchanged.
   c. Fill remaining slots (allocated_children - elite_count) with children.
2. Set `child.parent_species_id = species.id`, `child.fitness = 0.0`, `child.adjusted_fitness = 0.0`.
3. Apply mutation policy with `ctx.rate_multiplier = species.mutation_rate_multiplier`.

### Asexual

Each child = `parent.duplicate()` + mutation. Parent picked via `selection_method`.

### Crossover

Each child = crossover of two parents from the same species (or interspecies with probability `interspecies_rate`). Parents ordered by fitness (fitter, less_fit). If `overall_crossover != null`: `child = crossover(fitter, less_fit)`, else `child = fitter.duplicate()`. Then apply mutation.

### Mixed

With probability `crossover_rate` (if species has ≥ 2 members): use crossover. Otherwise: asexual.

**Default values (UI config):**
- `generation_method = "mixed"`
- `crossover_rate = 0.75`
- `elite_count = 1`
- `interspecies_rate = 0.001`

---

## 14. Dead Node Cleanup

### `Genome.prune_disconnected_hidden_nodes() -> int`

Removes hidden nodes that are structurally disconnected from the network. A hidden node is removed if it has:
- **No connections at all** (floating node)
- **Only incoming connections** (dead-end node)
- **Only outgoing connections** (dead-start node)

Input, bias, and output nodes are **never** removed. Removal is **iterative**: after removing a node, its connections are also removed, which may cause other nodes to become disconnected. The process repeats until no more hidden nodes can be removed.

**Called after:**
1. `_build_random_genome()` (initialization)
2. Every crossover implementation (Fitter, Bigger, Combine, Excluded)
3. Every mutation policy `apply()` (General stacked/non-stacked, PhasedPruning growth/pruning)

**Rationale:** Under standard NEAT rules (topological mode, no pruning), dead nodes should never arise because all new nodes are created by splitting a connection (which gives them exactly 1 incoming + 1 outgoing). However, they can appear during:
- Initial population generation (random hidden nodes + random connections may not wire every node on both sides)
- Crossover (child inherits union of nodes but filtered connections)
- Prune mutations (if enabled)

---

## 15. Configuration Defaults

### NeatConfig defaults (base class)

| Field | Default |
|-------|---------|
| `num_inputs` | 2 |
| `num_outputs` | 1 |
| `use_bias` | true |
| `input_activation` | LINEAR |
| `output_activation` | TANH |
| `hidden_activation` | TANH |
| `forward_mode` | "topological" |
| `timestep_steps` | 5 |
| `population_size` | 150 |
| `selection_method` | "roulette" |
| `similarity_method` | "standard" |
| `similarity_c1/c2/c3` | 1.0 / 1.0 / 0.4 |
| `similarity_n_threshold` | 20 |
| `speciation_method` | "standard" |
| `compatibility_threshold` | 3.0 |
| `target_species_count` | 10 |
| `max_species_count` | 20 |
| `threshold_up_speed` | 0.3 |
| `threshold_down_speed` | 0.3 |
| `merge_ratio` | 0.5 |
| `min_threshold` | 0.5 |
| `max_threshold` | 30.0 |
| `evaluation_method` | "equal" |
| `generation_method` | "asexual" |
| `elite_count` | 1 |
| `interspecies_rate` | 0.001 |
| `crossover_rate` | 0.5 |
| `weight_mutation_rate` | 0.8 |
| `weight_mutation_min` | 1 |
| `connection_mutation_rate` | 0.05 |
| `neuron_mutation_rate` | 0.03 |
| `prune_mutation_rate` | 0.01 |
| `enable_mutation_rate` | 0.01 |
| `forbid_loops` | true |
| `init_min_hidden_nodes` | 0 |
| `init_max_hidden_nodes` | 3 |
| `init_min_connections` | 5 |
| `init_max_connections` | 20 |
| `init_weight_min/max` | -1.0 / 1.0 |

### UI config defaults (ConfigScreen._make_config)

These override the NeatConfig defaults when the user starts training from the UI:

| Field | UI Default |
|-------|------------|
| `speciation_method` | "purge" |
| `generation_method` | "mixed" |
| `crossover_rate` | 0.75 |
| `interspecies_rate` | 0.001 |
| `init_max_hidden_nodes` | 0 (start minimal) |
| `init_min_connections` | 1 |
| `init_max_connections` | 3 |
| `weight_mutation_delta_min/max` | -0.5 / 0.5 |
| `connection_mutation_rate` | 0.05 |
| `neuron_mutation_rate` | 0.03 |
| `enable_mutation_rate` | 0.05 |
| `enable_enable_mutation` | true |
| `enable_prune_mutation` | false |
| `overall_crossover_method` | "fitter" |
| `neuron_crossover_method` | "standard" |

**Per-environment settings:**

| Env | num_inputs | num_outputs | output_activation | population_size | extra |
|-----|-----------|-------------|-------------------|-----------------|-------|
| XOR | 2 | 1 | SIGMOID | 150 | `_solved_threshold = 15.5` |
| CartPole | 4 | 1 | TANH | 100 | `_max_steps = 500`, `_episodes = 3` |
| Acrobot | 6 | 1 | TANH | 100 | `_max_steps = 500`, `_episodes = 2` |
| Pong | 6 | 1 | TANH | 80 | `_points_to_win = 5`, `_episodes = 3` |

All envs: `_max_generations = 200`, `_speedup = 2.0`.

---

## 16. Evaluators

### Evaluator (non-physics, e.g. XOR)

RefCounted, synchronous. Each genome:
1. Create fresh env via `env_factory`.
2. `env.reset(rng)` with per-genome RNG (`seed = index * 7919 + 1`).
3. `state = env.initial_state()`
4. Loop until `env.is_done()` or `max_steps`:
   - `output = genome.forward(state, forward_mode)`
   - `action = env.interpret_output(output)`
   - `state = env.step(action)`
5. Return `env.current_fitness()`.

Multi-episodes: averaged. Multi-threaded via `WorkerThreadPool` (each thread gets its own env instance).

### SceneEvaluator (physics, e.g. CartPole/Acrobot/Pong)

Node-based, asynchronous (coroutine). Batches N genomes across N SubViewports (each with its own World2D).

1. Allocate pool of `num_slots` SubViewports, each with an env instance.
2. `evaluate_all(genomes)`:
   a. Apply speedup: `Engine.time_scale = speedup`, `Engine.physics_ticks_per_second = base * speedup`.
   b. Process in batches of `num_slots`.
   c. For each batch, for each episode:
      - Reset each env with its genome and per-genome-per-episode RNG.
      - Step loop: apply actions for non-done envs, `await physics_frame`, check done states. Repeat until all done or `max_steps`.
      - Collect `env.current_fitness()` for each.
      - Average over episodes.
   d. Restore engine settings.
3. `dispose()`: free all SubViewports.

**Key detail:** The step loop applies actions BEFORE yielding the physics frame. The `is_done()` check happens AFTER the physics frame steps the world. This means an env that becomes done during a physics frame is detected on the next iteration, and its action was already applied (which is fine because `apply_action` checks `_done` internally).

---

## Summary of Safety Checks

1. **Loop prevention:** If `forbid_loops = true` (required for topological mode), connection-add and enable mutations check `would_create_loop()` before applying.
2. **Prune safety:** Base and PruneNonEssential mutators check `_is_safe_to_remove()` — both endpoints must have at least one other enabled connection in the same direction. MergePair is the only prune mutator allowed to change graph shape (and only for nodes with exactly 1 in + 1 out).
3. **Dead node cleanup:** `prune_disconnected_hidden_nodes()` is called after initialization, every crossover, and every mutation policy apply. Removes hidden nodes with no incoming or no outgoing connections (iteratively, cascading).
4. **Threshold clamping:** Purge's `ideal_threshold` is clamped to `[min_threshold, max_threshold]` before assignment. Standard's threshold is clamped after every adjustment.
5. **Cull safeguard:** ImprovementRate never culls all species; keeps at least the best one.
6. **Rounding adjustment:** `_allocate_proportional` adjusts for rounding by adding/subtracting the difference from the largest species.
