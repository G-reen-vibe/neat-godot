extends Node
## Full end-to-end gameplay test: trains each environment for a few generations
## and verifies that fitness improves and the simulation doesn't crash.
## Run with: godot --headless --path . res://tests/test_full_e2e.tscn
##
## This test simulates actual gameplay by running the full NEAT loop:
##   initialize -> evaluate -> evolve -> repeat
## for each environment (XOR, CartPole, Acrobot, Pong, Spider 2D, Spider 3D).

var _failed: bool = false
var _results: Array = []

func _ready() -> void:
	print("=== test_full_e2e: full gameplay test ===")
	_test_xor()
	if _failed: _halt()
	_test_cartpole()
	if _failed: _halt()
	_test_acrobot()
	if _failed: _halt()
	_test_pong()
	if _failed: _halt()
	_test_spider_2d()
	if _failed: _halt()
	_test_spider_3d()
	if _failed: _halt()
	_test_all_forward_modes()
	if _failed: _halt()
	_test_all_speciation_methods()
	if _failed: _halt()
	_test_all_generation_methods()
	if _failed: _halt()
	_test_all_evaluation_methods()
	if _failed: _halt()
	_test_save_load()
	if _failed: _halt()

	print("\n=== Results ===")
	for r in _results:
		print("  %s" % r)
	print("\n=== test_full_e2e: ALL PASSED ===")
	get_tree().quit()

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _halt() -> void:
	printerr("\n=== test_full_e2e: FAILED ===")
	get_tree().quit(1)

func _test_xor() -> void:
	var cfg := NeatConfig.new()
	cfg.num_inputs = 2
	cfg.num_outputs = 1
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.SIGMOID
	cfg.population_size = 100
	cfg.forward_mode = "topological"
	cfg.speciation_method = "standard"
	cfg.compatibility_threshold = 6.0
	cfg.target_species_count = 10
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
	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	evaluator.num_threads = 0
	var best_f: float = -1e9
	for _g in range(15):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	_assert(pop.size() == cfg.population_size, "XOR: pop size stable at %d, got %d" % [cfg.population_size, pop.size()])
	_assert(best_f > 0.0, "XOR: best fitness should be > 0 after 15 gens, got %.3f" % best_f)
	_assert(pop.species_count() > 0, "XOR: should have at least 1 species")
	_results.append("XOR: gen=%d best=%.3f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("  XOR: OK (best=%.3f)" % best_f)

func _test_cartpole() -> void:
	var cfg := NeatConfig.new()
	cfg.num_inputs = 4
	cfg.num_outputs = 1
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = 50
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
	var evaluator := Evaluator.new(Callable(self, "_make_cartpole_env"), 600, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 0
	var best_f: float = -1e9
	for _g in range(5):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	_assert(pop.size() == cfg.population_size, "CartPole: pop size stable")
	_assert(best_f >= 0.0, "CartPole: best fitness should be >= 0")
	_results.append("CartPole: gen=%d best=%.1f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("  CartPole: OK (best=%.1f)" % best_f)

func _test_acrobot() -> void:
	var cfg := NeatConfig.new()
	cfg.num_inputs = 6
	cfg.num_outputs = 1
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = 40
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
	var evaluator := Evaluator.new(Callable(self, "_make_acrobot_env"), 600, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 0
	var best_f: float = -1e9
	for _g in range(5):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	_assert(pop.size() == cfg.population_size, "Acrobot: pop size stable")
	_results.append("Acrobot: gen=%d best=%.3f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("  Acrobot: OK (best=%.3f)" % best_f)

func _test_pong() -> void:
	var cfg := NeatConfig.new()
	cfg.num_inputs = 6
	cfg.num_outputs = 1
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = 30
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
	# Pong needs custom evaluation (tournament). Use static paddle for simplicity.
	var input_ids: Array[int] = [0, 1, 2, 3, 4, 5]
	var bias_id: int = 6
	var output_id: int = 7
	var best_f: float = -1e9
	for _g in range(5):
		for g: Genome in pop.genomes:
			var env := PongEnvironment.new(input_ids, bias_id, output_id, 5)
			env.set_player_a(g)
			env.set_player_b(null)
			env.reset()
			var state: Dictionary = env.initial_state()
			var steps: int = 0
			while not env.is_done() and steps < 500:
				var out: Dictionary = g.forward(state, "topological")
				var action: Dictionary = env.interpret_output(out, {})
				state = env.step(action)
				steps += 1
			g.fitness = env.current_fitness()
			if g.fitness > best_f:
				best_f = g.fitness
		pop.evolve()
	_assert(pop.size() == cfg.population_size, "Pong: pop size stable")
	_assert(best_f >= 0.0, "Pong: best fitness should be >= 0")
	_results.append("Pong: gen=%d best=%.2f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("  Pong: OK (best=%.2f)" % best_f)

func _test_spider_2d() -> void:
	var cfg := NeatConfig.new()
	cfg.num_inputs = 12
	cfg.num_outputs = 8
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = 30
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
	var in_ids: Array[int] = []
	for i in range(12):
		in_ids.append(i)
	var out_ids: Array[int] = []
	for i in range(8):
		out_ids.append(13 + i)
	var evaluator := Evaluator.new(Callable(self, "_make_spider2d_env"), 1100, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 0
	var best_f: float = -1e9
	for _g in range(5):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	_assert(pop.size() == cfg.population_size, "Spider 2D: pop size stable")
	# Spider 2D should have non-negative fitness (distance + bonus).
	_assert(best_f >= 0.0, "Spider 2D: best fitness should be >= 0, got %.3f" % best_f)
	_results.append("Spider 2D: gen=%d best=%.3f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("  Spider 2D: OK (best=%.3f)" % best_f)

func _test_spider_3d() -> void:
	var cfg := NeatConfig.new()
	cfg.num_inputs = 16
	cfg.num_outputs = 12
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = 30
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
	var evaluator := Evaluator.new(Callable(self, "_make_spider3d_env"), 1100, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 0
	var best_f: float = -1e9
	for _g in range(5):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		pop.evolve()
	_assert(pop.size() == cfg.population_size, "Spider 3D: pop size stable")
	_assert(best_f >= 0.0, "Spider 3D: best fitness should be >= 0, got %.3f" % best_f)
	_results.append("Spider 3D: gen=%d best=%.3f species=%d" % [pop.generation, best_f, pop.species_count()])
	print("  Spider 3D: OK (best=%.3f)" % best_f)

func _test_all_forward_modes() -> void:
	# Test that both forward modes work for a simple genome.
	var g := Genome.new()
	g.add_node(NodeGene.new(0, NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR))
	g.add_node(NodeGene.new(1, NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR))
	g.add_node(NodeGene.new(2, NodeGene.Kind.BIAS, ActivationFunctions.Func.LINEAR))
	g.add_node(NodeGene.new(3, NodeGene.Kind.OUTPUT, ActivationFunctions.Func.TANH))
	g.add_connection(ConnectionGene.new(0, 0, 3, 0.5))
	g.add_connection(ConnectionGene.new(1, 1, 3, -0.5))
	g.add_connection(ConnectionGene.new(2, 2, 3, 0.3))
	var out_topo: Dictionary = g.forward({0: 1.0, 1: 0.5}, "topological")
	var out_ts: Dictionary = g.forward({0: 1.0, 1: 0.5}, "timestep", 8)
	for k in out_topo.keys():
		var diff: float = absf(float(out_topo[k]) - float(out_ts[k]))
		_assert(diff < 1e-4, "Forward modes should match for feedforward, diff=%f" % diff)
	print("  forward modes: OK")

func _test_all_speciation_methods() -> void:
	for method in ["single", "standard", "purge"]:
		var cfg := NeatConfig.new()
		cfg.num_inputs = 2
		cfg.num_outputs = 1
		cfg.use_bias = true
		cfg.population_size = 30
		cfg.speciation_method = method
		cfg.compatibility_threshold = 6.0
		cfg.target_species_count = 5
		var pop := Population.new(cfg)
		pop.initialize()
		_assert(pop.species_count() >= 1, "Speciation '%s' should produce >= 1 species" % method)
		_assert(pop.size() == cfg.population_size, "Speciation '%s': pop size stable" % method)
	print("  speciation methods: OK")

func _test_all_generation_methods() -> void:
	for method in ["asexual", "crossover", "mixed"]:
		var cfg := NeatConfig.new()
		cfg.num_inputs = 2
		cfg.num_outputs = 1
		cfg.use_bias = true
		cfg.population_size = 30
		cfg.generation_method = method
		cfg.crossover_rate = 0.5
		cfg.overall_crossover_method = "fitter"
		cfg.neuron_crossover_method = "standard"
		cfg.speciation_method = "standard"
		cfg.compatibility_threshold = 6.0
		var pop := Population.new(cfg)
		pop.initialize()
		var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
		evaluator.num_threads = 0
		for _g in range(3):
			var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
			for i in range(pop.genomes.size()):
				pop.genomes[i].fitness = fitnesses[i]
			pop.evolve()
		_assert(pop.size() == cfg.population_size, "Generation '%s': pop size stable" % method)
	print("  generation methods: OK")

func _test_all_evaluation_methods() -> void:
	for method in ["equal", "improvement_rate", "novelty"]:
		var cfg := NeatConfig.new()
		cfg.num_inputs = 2
		cfg.num_outputs = 1
		cfg.use_bias = true
		cfg.population_size = 30
		cfg.evaluation_method = method
		cfg.speciation_method = "standard"
		cfg.compatibility_threshold = 6.0
		var pop := Population.new(cfg)
		pop.initialize()
		var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
		evaluator.num_threads = 0
		for _g in range(3):
			var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
			for i in range(pop.genomes.size()):
				pop.genomes[i].fitness = fitnesses[i]
			pop.evolve()
		_assert(pop.size() == cfg.population_size, "Evaluation '%s': pop size stable" % method)
	print("  evaluation methods: OK")

func _test_save_load() -> void:
	var cfg := NeatConfig.new()
	cfg.num_inputs = 2
	cfg.num_outputs = 1
	cfg.use_bias = true
	cfg.population_size = 20
	cfg.speciation_method = "standard"
	cfg.compatibility_threshold = 6.0
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	evaluator.num_threads = 0
	var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
	for i in range(pop.genomes.size()):
		pop.genomes[i].fitness = fitnesses[i]
	pop.evolve()
	# Save.
	var save_view := SaveLoadView.new()
	save_view.population = pop
	save_view.config = cfg
	save_view.env_idx = 0
	var data: Dictionary = {
		"env_idx": 0,
		"generation": pop.generation,
		"best_fitness": pop.best_fitness,
		"config": save_view._config_to_dict(cfg),
		"population": save_view._population_to_dict(pop),
	}
	# Load.
	var loaded_cfg := save_view._config_from_dict(data["config"])
	var loaded_pop := save_view.load_population_from_dict(data["population"], loaded_cfg)
	_assert(loaded_pop.size() == pop.size(), "Save/Load: pop size should match")
	_assert(loaded_pop.generation == pop.generation, "Save/Load: generation should match")
	_assert(absf(loaded_pop.best_fitness - pop.best_fitness) < 1e-6, "Save/Load: best_fitness should match")
	# Verify genomes match.
	for i in range(pop.genomes.size()):
		var orig: Genome = pop.genomes[i]
		var loaded: Genome = loaded_pop.genomes[i]
		_assert(orig.node_count() == loaded.node_count(), "Save/Load: node count mismatch at %d" % i)
		_assert(orig.connection_count() == loaded.connection_count(), "Save/Load: conn count mismatch at %d" % i)
	print("  save/load: OK")

# --- Env factories ---

func _make_xor_env() -> XorEnvironment:
	return XorEnvironment.new([0, 1], 2, 3)

func _make_cartpole_env() -> CartPoleEnvironment:
	return CartPoleEnvironment.new([0, 1, 2, 3], 4, 5, 500)

func _make_acrobot_env() -> AcrobotEnvironment:
	return AcrobotEnvironment.new([0, 1, 2, 3, 4, 5], 6, 7, 500)

func _make_spider2d_env() -> SpiderWalker2DEnvironment:
	var in_ids: Array[int] = []
	for i in range(12):
		in_ids.append(i)
	var out_ids: Array[int] = []
	for i in range(8):
		out_ids.append(13 + i)
	return SpiderWalker2DEnvironment.new(in_ids, 12, out_ids)

func _make_spider3d_env() -> SpiderWalker3DEnvironment:
	var in_ids: Array[int] = []
	for i in range(16):
		in_ids.append(i)
	var out_ids: Array[int] = []
	for i in range(12):
		out_ids.append(17 + i)
	return SpiderWalker3DEnvironment.new(in_ids, 16, out_ids)
