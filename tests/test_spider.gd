extends Node
## Spider Walker 2D/3D training tests.
## Run with: godot --headless --path . res://tests/test_spider.tscn

const MAX_GENERATIONS: int = 15
const POP_SIZE: int = 40

var rng: RandomNumberGenerator

func _ready() -> void:
	print("=== test_spider: 2D and 3D spider walker training ===")
	rng = RandomNumberGenerator.new()
	rng.seed = 11

	_test_spider_2d()
	_test_spider_3d()

	print("\n=== test_spider: DONE ===")
	get_tree().quit()

func _test_spider_2d() -> void:
	print("  --- 2D Spider Walker ---")
	var cfg := NeatConfig.new()
	cfg.num_inputs = 12
	cfg.num_outputs = 8
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = POP_SIZE
	cfg.forward_mode = "topological"
	cfg.speciation_method = "standard"
	cfg.compatibility_threshold = 6.0
	cfg.target_species_count = 8
	cfg.generation_method = "asexual"
	cfg.elite_count = 1
	cfg.enable_weight_mutation = true
	cfg.weight_mutation_rate = 0.8
	cfg.weight_mutation_min = 1
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

	var pop := Population.new(cfg)
	pop.initialize()
	var input_ids: Array[int] = []
	for i in range(12):
		input_ids.append(i)
	var output_ids: Array[int] = [13, 14, 15, 16, 17, 18, 19, 20]
	var evaluator := Evaluator.new(Callable(self, "_make_spider_2d_env"), 1100, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 4
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > pop.best_fitness:
				pop.best_fitness = fitnesses[i]
				pop.best_genome = pop.genomes[i].duplicate()
		if gen % 3 == 0:
			print("    gen=%d  best=%.3f  species=%d" % [pop.generation, pop.best_fitness, pop.species_count()])
		pop.evolve()
	print("    final best=%.3f" % pop.best_fitness)

func _test_spider_3d() -> void:
	print("  --- 3D Spider Walker ---")
	var cfg := NeatConfig.new()
	cfg.num_inputs = 16
	cfg.num_outputs = 12
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = POP_SIZE
	cfg.forward_mode = "topological"
	cfg.speciation_method = "standard"
	cfg.compatibility_threshold = 6.0
	cfg.target_species_count = 8
	cfg.generation_method = "asexual"
	cfg.elite_count = 1
	cfg.enable_weight_mutation = true
	cfg.weight_mutation_rate = 0.8
	cfg.weight_mutation_min = 1
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

	var pop := Population.new(cfg)
	pop.initialize()
	var input_ids: Array[int] = []
	for i in range(16):
		input_ids.append(i)
	var output_ids: Array[int] = [17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28]
	var evaluator := Evaluator.new(Callable(self, "_make_spider_3d_env"), 1100, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 4
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > pop.best_fitness:
				pop.best_fitness = fitnesses[i]
				pop.best_genome = pop.genomes[i].duplicate()
		if gen % 3 == 0:
			print("    gen=%d  best=%.3f  species=%d" % [pop.generation, pop.best_fitness, pop.species_count()])
		pop.evolve()
	print("    final best=%.3f" % pop.best_fitness)

func _make_spider_2d_env() -> SpiderWalker2DEnvironment:
	var input_ids: Array[int] = []
	for i in range(12):
		input_ids.append(i)
	var output_ids: Array[int] = [13, 14, 15, 16, 17, 18, 19, 20]
	return SpiderWalker2DEnvironment.new(input_ids, 12, output_ids)

func _make_spider_3d_env() -> SpiderWalker3DEnvironment:
	var input_ids: Array[int] = []
	for i in range(16):
		input_ids.append(i)
	var output_ids: Array[int] = [17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28]
	return SpiderWalker3DEnvironment.new(input_ids, 16, output_ids)
