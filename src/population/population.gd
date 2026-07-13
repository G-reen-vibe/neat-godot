## Top-level NEAT orchestrator. Owns the [InnovationTracker], the current
## generation's species list, and the strategy objects built from a [NeatConfig].
##
## Typical usage:
## [code]
##   var pop = Population.new(config)
##   pop.initialize()
##   while not pop.solved:
##       pop.evaluate_genomes(my_fitness_function)
##       pop.evolve()
## [/code]
class_name Population
extends RefCounted

var config: NeatConfig
var tracker: InnovationTracker
var species_list: Array = []  # Array[Species]
var genomes: Array = []        # Array[Genome] (current generation's evaluated genomes)
var generation: int = 0
var best_genome: Genome = null
var best_fitness: float = -1e9
var solved: bool = false

# Strategies (built from config).
var similarity: SimilarityTest
var speciation: SpeciationStrategy
var evaluation: EvaluationStrategy
var generation_strategy: GenerationStrategy
var mutation_policy: MutationPolicy
var overall_crossover: OverallCrossover
var neuron_crossover: NeuronCrossover

# Cached RNG (single-threaded default; for parallel evaluation, use
# [method evaluate_genomes_parallel] which builds thread-local RNGs).
var rng: RandomNumberGenerator

func _init(p_config: NeatConfig = null) -> void:
		config = p_config if p_config != null else NeatConfig.new()
		tracker = InnovationTracker.new()
		rng = RandomNumberGenerator.new()
		rng.randomize()
		_build_strategies()

func _build_strategies() -> void:
		var s: Dictionary = config.build_strategies()
		similarity = s["similarity"]
		speciation = s["speciation"]
		evaluation = s["evaluation"]
		generation_strategy = s["generation"]
		mutation_policy = s["mutation_policy"]
		overall_crossover = s["overall_crossover"]
		neuron_crossover = s["neuron_crossover"]

## Seed the initial population using a random sequence of connection-add and
## neuron-add mutations applied to each genome independently.
##
## Each genome starts with a bare input/output/bias topology (no connections).
## Then we:
##   1. Add a random number of hidden nodes (init_min_hidden_nodes..init_max_hidden_nodes).
##   2. Add a random number of connections (init_min_connections..init_max_connections),
##      clamped to the maximum feasible count (all possible source->target pairs).
##   3. Each connection's weight is sampled uniformly from [init_weight_min, init_weight_max].
##
## This produces diverse starting topologies so speciation has meaningful
## structure from generation 0. All genomes share the same innovation tracker
## so matching connections get the same innovation number.
func initialize() -> void:
		generation = 0
		solved = false
		best_fitness = -1e9
		best_genome = null
		species_list.clear()
		genomes.clear()
		# Reserve node ids for inputs and bias.
		var next_id := 0
		var input_ids: Array[int] = []
		for i in range(config.num_inputs):
				var nid := next_id
				next_id += 1
				input_ids.append(nid)
				tracker.reserve_node_id(nid)
		var bias_id: int = -1
		if config.use_bias:
				bias_id = next_id
				next_id += 1
				tracker.reserve_node_id(bias_id)
		var output_ids: Array[int] = []
		for i in range(config.num_outputs):
				var nid := next_id
				next_id += 1
				output_ids.append(nid)
				tracker.reserve_node_id(nid)
		# Build initial genomes using random mutation sequences.
		for i in range(config.population_size):
				var g := _build_random_genome(input_ids, bias_id, output_ids)
				genomes.append(g)
		# Speciate the initial population.
		var ctx := _make_ctx()
		species_list = speciation.speciate(genomes, [], similarity, ctx)

## Build a single random genome by starting from a bare topology and applying
## a random sequence of node-add and connection-add mutations.
func _build_random_genome(input_ids: Array[int], bias_id: int, output_ids: Array[int]) -> Genome:
		var g := Genome.new()
		# Add input, bias, output nodes.
		for iid in input_ids:
				g.add_node(NodeGene.new(iid, NodeGene.Kind.INPUT, config.input_activation))
		if config.use_bias:
				g.add_node(NodeGene.new(bias_id, NodeGene.Kind.BIAS, config.input_activation))
		for oid in output_ids:
				g.add_node(NodeGene.new(oid, NodeGene.Kind.OUTPUT, config.output_activation))
		# Sources = inputs + bias; targets = outputs (initially).
		var sources: Array[int] = input_ids.duplicate()
		if config.use_bias:
				sources.append(bias_id)
		var targets: Array[int] = output_ids.duplicate()
		# Step 1: Add a random number of hidden nodes.
		var n_hidden: int = rng.randi_range(config.init_min_hidden_nodes, config.init_max_hidden_nodes)
		var hidden_ids: Array[int] = []
		for _i in range(n_hidden):
				var hid := tracker.new_node_id()
				hidden_ids.append(hid)
				g.add_node(NodeGene.new(hid, NodeGene.Kind.HIDDEN, config.hidden_activation))
				# Hidden nodes can be both sources and targets.
				sources.append(hid)
				targets.append(hid)
		# Step 2: Compute the maximum feasible connections.
		# A connection goes from any non-output node to any non-input/bias node.
		# Max = |sources| x |targets|, minus self-loops (hidden->same hidden).
		var max_feasible: int = 0
		for src in sources:
				for dst in targets:
						if src == dst:
								continue  # no self-loops
						max_feasible += 1
		# Decide how many connections to add.
		var target_conns: int = rng.randi_range(config.init_min_connections, config.init_max_connections)
		target_conns = mini(target_conns, max_feasible)
		# Build the list of all feasible (src, dst) pairs.
		var candidate_pairs: Array[Vector2i] = []
		for src in sources:
				for dst in targets:
						if src == dst:
								continue
						# In topological mode, skip pairs that would create a loop.
						# For initialization, we only add feedforward connections:
						# inputs/bias -> hidden/output, hidden -> hidden/output (with id ordering).
						# This avoids loops in topological mode.
						if config.forward_mode == "topological":
								# Only allow forward edges: src id < dst id (rough topological order).
								# Bias and inputs have lowest ids, then hidden (allocated later), then outputs.
								# Actually outputs were allocated before hidden, so we need a different check.
								# Use the kind: INPUT/BIAS -> anything; HIDDEN -> HIDDEN (higher id) or OUTPUT.
								var src_node: NodeGene = g.get_node(src)
								var dst_node: NodeGene = g.get_node(dst)
								if src_node.kind == NodeGene.Kind.INPUT or src_node.kind == NodeGene.Kind.BIAS:
										pass  # inputs can connect to anything
								elif src_node.kind == NodeGene.Kind.HIDDEN:
										if dst_node.kind == NodeGene.Kind.HIDDEN and dst <= src:
												continue  # hidden -> hidden only forward (higher id)
										if dst_node.kind == NodeGene.Kind.INPUT or dst_node.kind == NodeGene.Kind.BIAS:
												continue  # no backward to inputs
								elif src_node.kind == NodeGene.Kind.OUTPUT:
										continue  # outputs can't be sources
						candidate_pairs.append(Vector2i(src, dst))
		# Shuffle and pick the first target_conns pairs.
		# Use the Population's rng (not the global RNG) for reproducibility.
		for i in range(candidate_pairs.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = candidate_pairs[i]
				candidate_pairs[i] = candidate_pairs[j]
				candidate_pairs[j] = tmp
		var n_to_add: int = mini(target_conns, candidate_pairs.size())
		for i in range(n_to_add):
				var pair: Vector2i = candidate_pairs[i]
				var innov := tracker.get_connection_innov(pair.x, pair.y)
				var w: float = rng.randf_range(config.init_weight_min, config.init_weight_max)
				g.add_connection(ConnectionGene.new(innov, pair.x, pair.y, w))
		# Prune any hidden nodes that ended up with no incoming or no outgoing
		# connections. This can happen because we add hidden nodes first, then
		# pick random connections from candidate pairs -- there's no guarantee
		# every hidden node gets wired in on both sides.
		g.prune_disconnected_hidden_nodes()
		return g

## Build a MutationContext with current state.
func _make_ctx(p_species: Species = null) -> MutationContext:
		var ctx := MutationContext.new(rng, tracker, p_species)
		ctx.forward_mode = config.forward_mode
		ctx.forbid_loops = config.forbid_loops or config.forward_mode == "topological"
		return ctx

## Evaluate every genome using [param fitness_fn], which takes a Genome and
## returns a float. Updates [member best_fitness] / [member best_genome] as
## a side effect.
func evaluate_genomes(fitness_fn: Callable) -> void:
		for g: Genome in genomes:
				g.fitness = float(fitness_fn.call(g))
				if g.fitness > best_fitness:
						best_fitness = g.fitness
						best_genome = g.duplicate()

## Run one generation: speciate, evaluate, evolve.
## Assumes [method evaluate_genomes] has already been called for the current
## generation's genomes.
func evolve() -> void:
		generation += 1
		# Update species stats from current genomes.
		for sp: Species in species_list:
				sp.record_generation_stats()
		# Evaluate species (allocate children, set mutation multipliers).
		var eval_ctx := _make_ctx()
		evaluation.evaluate(species_list, config.population_size, eval_ctx)
		# If PhasedPruning policy, advance its generation counter.
		if mutation_policy is MutationPolicy.PhasedPruning:
				(mutation_policy as MutationPolicy.PhasedPruning).advance_generation()
		# Produce next generation's genomes.
		var gen_ctx := _make_ctx()
		var new_genomes: Array = generation_strategy.produce(species_list, gen_ctx)
		# Replace genomes.
		genomes = new_genomes
		# Speciate the new genomes.
		species_list = speciation.speciate(genomes, species_list, similarity, gen_ctx)

## Convenience: evolve one generation given a fitness function.
## Equivalent to evaluate_genomes(fitness_fn) then evolve().
func step(fitness_fn: Callable) -> void:
		evaluate_genomes(fitness_fn)
		evolve()

## Run the whole NEAT loop until either [param max_generations] is reached or
## [param stop_fn] returns true. [param stop_fn] is called after each generation
## with the current Population as argument.
func run(fitness_fn: Callable, max_generations: int, stop_fn: Callable = Callable()) -> void:
		for _g in range(max_generations):
				step(fitness_fn)
				if stop_fn.is_valid() and stop_fn.call(self):
						solved = true
						return

## Get the best genome of the current generation.
func current_best() -> Genome:
		var best: Genome = null
		var best_f: float = -1e9
		for g: Genome in genomes:
				if g.fitness > best_f:
						best_f = g.fitness
						best = g
		return best

## Total number of species in the current generation.
func species_count() -> int:
		return species_list.size()

## Total number of genomes (should equal [member config.population_size]).
func size() -> int:
		return genomes.size()
