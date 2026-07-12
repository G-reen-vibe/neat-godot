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

## Seed the initial population with fully-connected input/output topologies.
## All genomes share the same starting innovation numbers (via the tracker).
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
	# Build initial genomes.
	for i in range(config.population_size):
		var g := Genome.new()
		for iid in input_ids:
			g.add_node(NodeGene.new(iid, NodeGene.Kind.INPUT, config.input_activation))
		if config.use_bias:
			g.add_node(NodeGene.new(bias_id, NodeGene.Kind.BIAS, config.input_activation))
		for oid in output_ids:
			g.add_node(NodeGene.new(oid, NodeGene.Kind.OUTPUT, config.output_activation))
		# Fully connect inputs+bias -> outputs.
		var sources: Array[int] = input_ids.duplicate()
		if config.use_bias:
			sources.append(bias_id)
		for src in sources:
			for dst in output_ids:
				var innov := tracker.get_connection_innov(src, dst)
				var w: float = rng.randf_range(-config.initial_weight_range, config.initial_weight_range)
				g.add_connection(ConnectionGene.new(innov, src, dst, w))
		genomes.append(g)
	# Speciate the initial population.
	var ctx := _make_ctx()
	species_list = speciation.speciate(genomes, [], similarity, ctx)

## Build a MutationContext with current state.
func _make_ctx(p_species: Species = null) -> MutationContext:
	var ctx := MutationContext.new(rng, tracker, p_species)
	ctx.forward_mode = config.forward_mode
	ctx.forbid_loops = config.forbid_loops or config.forward_mode == "topological"
	return ctx

## Evaluate every genome using [param fitness_fn], which takes a Genome and
## returns a float. Resets fitness to 0 before evaluation.
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
