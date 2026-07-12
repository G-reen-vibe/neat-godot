extends Node
## Full XOR training test: run NEAT until it solves XOR (or hits max generations).
## Run with: godot --headless --path . res://tests/test_xor.tscn

const MAX_GENERATIONS: int = 100
const SOLVED_FITNESS: float = 15.5
const POP_SIZE: int = 150

func _ready() -> void:
	print("=== test_xor: full NEAT XOR training ===")
	var cfg := NeatConfig.new()
	cfg.num_inputs = 2
	cfg.num_outputs = 1
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.SIGMOID
	cfg.population_size = POP_SIZE
	cfg.forward_mode = "topological"
	cfg.speciation_method = "standard"
	cfg.compatibility_threshold = 6.0
	cfg.target_species_count = 10
	cfg.generation_method = "asexual"
	cfg.elite_count = 1
	cfg.enable_weight_mutation = true
	cfg.weight_mutation_rate = 0.8
	cfg.weight_mutation_min = 1
	cfg.weight_mutation_delta_min = -2.0
	cfg.weight_mutation_delta_max = 2.0
	cfg.enable_connection_mutation = true
	cfg.connection_mutation_rate = 0.3
	cfg.connection_mutation_min = 0
	cfg.enable_neuron_mutation = true
	cfg.neuron_mutation_rate = 0.2
	cfg.neuron_mutation_min = 0
	cfg.enable_enable_mutation = true
	cfg.enable_mutation_rate = 0.3
	cfg.enable_mutation_min = 0
	cfg.selection_method = "roulette"
	cfg.similarity_method = "standard"
	cfg.similarity_c1 = 1.0
	cfg.similarity_c2 = 1.0
	cfg.similarity_c3 = 0.4

	var pop := Population.new(cfg)
	pop.initialize()
	print("  Initialized: pop=%d, species=%d" % [pop.size(), pop.species_count()])

	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	evaluator.num_threads = 0

	var start_time := Time.get_ticks_msec()
	var solved_gen: int = -1
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		var cur_best: float = -1e9
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > cur_best:
				cur_best = fitnesses[i]
			if fitnesses[i] > pop.best_fitness:
				pop.best_fitness = fitnesses[i]
				pop.best_genome = pop.genomes[i].duplicate()
		if cur_best >= SOLVED_FITNESS and solved_gen < 0:
			solved_gen = pop.generation
			print("  *** SOLVED at gen %d (fitness=%.3f) ***" % [pop.generation, cur_best])
			break
		if gen % 10 == 0:
			print("  gen=%d  best=%.3f  cur_best=%.3f  species=%d  avg_conns=%.1f" %
				[pop.generation, pop.best_fitness, cur_best, pop.species_count(), _avg_conns(pop)])
		pop.evolve()

	var elapsed := Time.get_ticks_msec() - start_time
	print("  Total time: %d ms (%.1f s)" % [elapsed, elapsed / 1000.0])
	print("  Best fitness: %.3f" % pop.best_fitness)
	print("  Final species count: %d" % pop.species_count())
	if pop.best_genome != null:
		print("  Best genome: %s" % pop.best_genome)
	if solved_gen >= 0:
		print("\n=== test_xor: SOLVED at gen %d ===" % solved_gen)
	else:
		print("\n=== test_xor: did NOT solve in %d generations ===" % MAX_GENERATIONS)
		assert(false, "XOR should be solvable within %d generations" % MAX_GENERATIONS)
	get_tree().quit()

func _make_xor_env() -> XorEnvironment:
	return XorEnvironment.new([0, 1], 2, 3)

func _avg_conns(pop: Population) -> float:
	var total: int = 0
	for g: Genome in pop.genomes:
		total += g.connection_count()
	return float(total) / float(maxi(1, pop.genomes.size()))
