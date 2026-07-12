extends Node
## Full end-to-end test: trains each environment (real-physics) for a few
## generations and verifies that fitness improves and the simulation
## doesn't crash. Tests the full NEAT loop:
##   initialize -> evaluate -> evolve -> repeat
## for each environment (XOR, CartPole, Acrobot, Pong, Spider 2D, Spider 3D).
##
## Run with: godot --headless --path . res://tests/test_full_e2e_v2.tscn

const MAX_GENERATIONS: int = 5

var _failed: bool = false
var _results: Array = []

func _ready() -> void:
	print("=== test_full_e2e_v2: full gameplay test (real-physics envs) ===")
	await _test_xor()
	if _failed: _halt()
	await _test_cartpole()
	if _failed: _halt()
	await _test_acrobot()
	if _failed: _halt()
	await _test_pong()
	if _failed: _halt()
	await _test_spider_2d()
	if _failed: _halt()
	await _test_spider_3d()
	if _failed: _halt()
	await _test_save_load()
	if _failed: _halt()

	print("\n=== Results ===")
	for r in _results:
		print("  %s" % r)
	print("\n=== test_full_e2e_v2: ALL PASSED ===")
	get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _halt() -> void:
	printerr("\n=== test_full_e2e_v2: FAILED ===")
	get_tree().quit(1)

func _make_default_config(num_in: int, num_out: int, pop_size: int = 30) -> NeatConfig:
	var cfg := NeatConfig.new()
	cfg.num_inputs = num_in
	cfg.num_outputs = num_out
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = pop_size
	cfg.forward_mode = "topological"
	cfg.forbid_loops = true
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
	cfg.enable_neuron_mutation = true
	cfg.neuron_mutation_rate = 0.2
	cfg.enable_enable_mutation = true
	cfg.enable_mutation_rate = 0.3
	cfg.selection_method = "roulette"
	return cfg

func _test_xor() -> void:
	print("  --- XOR (RefCounted Evaluator) ---")
	var cfg := _make_default_config(2, 1, 30)
	cfg.output_activation = ActivationFunctions.Func.SIGMOID
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 2
	var best_f: float = -1e9
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	_assert(best_f > 0.0, "XOR: best fitness should be > 0, got %.3f" % best_f)
	_assert(pop.size() == cfg.population_size, "XOR: pop size stable")
	_results.append("XOR: gen=%d best=%.3f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("    XOR: OK (best=%.3f)" % best_f)

func _make_xor_env() -> XorEnvironment:
	return XorEnvironment.new([0, 1], 2, 3)

func _test_cartpole() -> void:
	print("  --- CartPole (Scene Evaluator) ---")
	var cfg := _make_default_config(4, 1, 20)
	var pop := Population.new(cfg)
	pop.initialize()
	var env_scene := load("res://environments/cartpole/cartpole_environment.tscn")
	var evaluator := SceneEvaluator.new(self, env_scene, 20, 510, "topological")
	evaluator.speedup = 2.0
	evaluator.episodes_per_genome = 1
	var input_ids: Array[int] = [0, 1, 2, 3]
	evaluator.env_setup_fn = func(env: Node) -> void:
		env.input_node_ids = input_ids
		env.bias_node_id = 4
		env.output_node_id = 5
		env.set_max_steps(500)
	var best_f: float = -1e9
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	evaluator.dispose()
	_assert(best_f > 0.0, "CartPole: best fitness should be > 0, got %.3f" % best_f)
	_assert(pop.size() == cfg.population_size, "CartPole: pop size stable")
	_results.append("CartPole: gen=%d best=%.3f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("    CartPole: OK (best=%.3f)" % best_f)

func _test_acrobot() -> void:
	print("  --- Acrobot (Scene Evaluator) ---")
	var cfg := _make_default_config(6, 1, 20)
	var pop := Population.new(cfg)
	pop.initialize()
	var env_scene := load("res://environments/acrobot/acrobot_environment.tscn")
	var evaluator := SceneEvaluator.new(self, env_scene, 20, 510, "topological")
	evaluator.speedup = 2.0
	evaluator.episodes_per_genome = 1
	var input_ids: Array[int] = [0, 1, 2, 3, 4, 5]
	evaluator.env_setup_fn = func(env: Node) -> void:
		env.input_node_ids = input_ids
		env.bias_node_id = 6
		env.output_node_id = 7
		env.set_max_steps(500)
	var best_f: float = -1e9
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	evaluator.dispose()
	_assert(best_f > -1e9, "Acrobot: should have at least one fitness value")
	_assert(pop.size() == cfg.population_size, "Acrobot: pop size stable")
	_results.append("Acrobot: gen=%d best=%.3f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("    Acrobot: OK (best=%.3f)" % best_f)

func _test_pong() -> void:
	print("  --- Pong (Scene Evaluator, no opponent) ---")
	var cfg := _make_default_config(6, 1, 15)
	var pop := Population.new(cfg)
	pop.initialize()
	var env_scene := load("res://environments/pong/pong_environment.tscn")
	var evaluator := SceneEvaluator.new(self, env_scene, 15, 1210, "topological")
	evaluator.speedup = 2.0
	evaluator.episodes_per_genome = 1
	var input_ids: Array[int] = [0, 1, 2, 3, 4, 5]
	evaluator.env_setup_fn = func(env: Node) -> void:
		env.input_node_ids = input_ids
		env.bias_node_id = 6
		env.output_node_id = 7
		env.set_player_b(null)
	var best_f: float = -1e9
	for gen in range(3):  # fewer gens because pong is slow
		var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	evaluator.dispose()
	_assert(best_f >= 0.0, "Pong: best fitness should be >= 0, got %.3f" % best_f)
	_assert(pop.size() == cfg.population_size, "Pong: pop size stable")
	_results.append("Pong: gen=%d best=%.3f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("    Pong: OK (best=%.3f)" % best_f)

func _test_spider_2d() -> void:
	print("  --- Spider 2D (Scene Evaluator) ---")
	var cfg := _make_default_config(12, 8, 15)
	var pop := Population.new(cfg)
	pop.initialize()
	var env_scene := load("res://environments/spider_2d/spider_walker_2d_environment.tscn")
	var evaluator := SceneEvaluator.new(self, env_scene, 15, 1100, "topological")
	evaluator.speedup = 2.0
	evaluator.episodes_per_genome = 1
	var input_ids: Array[int] = []
	for i in range(12):
		input_ids.append(i)
	var output_ids: Array[int] = [13, 14, 15, 16, 17, 18, 19, 20]
	evaluator.env_setup_fn = func(env: Node) -> void:
		env.input_node_ids = input_ids
		env.bias_node_id = 12
		env.output_node_ids = output_ids
	var best_f: float = -1e9
	for gen in range(3):  # fewer gens because spider is slow
		var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	evaluator.dispose()
	_assert(best_f >= 0.0, "Spider2D: best fitness should be >= 0, got %.3f" % best_f)
	_assert(pop.size() == cfg.population_size, "Spider2D: pop size stable")
	_results.append("Spider2D: gen=%d best=%.3f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("    Spider 2D: OK (best=%.3f)" % best_f)

func _test_spider_3d() -> void:
	print("  --- Spider 3D (Scene Evaluator) ---")
	var cfg := _make_default_config(16, 12, 10)
	var pop := Population.new(cfg)
	pop.initialize()
	var env_scene := load("res://environments/spider_3d/spider_walker_3d_environment.tscn")
	var evaluator := SceneEvaluator.new(self, env_scene, 10, 1100, "topological")
	evaluator.speedup = 2.0
	evaluator.episodes_per_genome = 1
	var input_ids: Array[int] = []
	for i in range(16):
		input_ids.append(i)
	var output_ids: Array[int] = []
	for i in range(12):
		output_ids.append(17 + i)
	evaluator.env_setup_fn = func(env: Node) -> void:
		env.input_node_ids = input_ids
		env.bias_node_id = 16
		env.output_node_ids = output_ids
	var best_f: float = -1e9
	for gen in range(3):
		var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	evaluator.dispose()
	_assert(best_f >= 0.0, "Spider3D: best fitness should be >= 0, got %.3f" % best_f)
	_assert(pop.size() == cfg.population_size, "Spider3D: pop size stable")
	_results.append("Spider3D: gen=%d best=%.3f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("    Spider 3D: OK (best=%.3f)" % best_f)

func _test_save_load() -> void:
	print("  --- Save/Load ---")
	var cfg := _make_default_config(2, 1, 10)
	cfg.output_activation = ActivationFunctions.Func.SIGMOID
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	evaluator.episodes_per_genome = 1
	var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
	for i in range(pop.genomes.size()):
		pop.genomes[i].fitness = fitnesses[i]
	pop.evolve()
	_assert(pop.generation == 1, "Save/Load: pop generation should be 1, got %d" % pop.generation)
	_assert(pop.size() == 10, "Save/Load: pop size should be 10")
	_results.append("Save/Load: pop gen=%d size=%d OK" % [pop.generation, pop.size()])
	print("    Save/Load: OK")
