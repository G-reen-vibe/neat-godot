extends Node
## End-to-end test: NEAT training on all 4 envs via the NeatRLAdapter.
##
## Runs a short training loop (3 generations, small pop) on each env to verify
## the full pipeline works: SceneEvaluator + adapter + Population.evolve().
## Does NOT assert learning (too few generations); just verifies fitnesses
## are produced, population evolves, and no errors/crashes.
##
## Run with:
##   godot --headless --path . res://tests/test_train_all_envs.tscn

const MAX_GENERATIONS: int = 3
const POP_SIZE: int = 12
const NUM_SLOTS: int = 12
const MAX_STEPS: int = 150

var _failed: bool = false

func _ready() -> void:
	print("=== test_train_all_envs: NEAT training on all 4 envs ===")
	await _test()
	if _failed:
		printerr("\n=== test_train_all_envs: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_train_all_envs: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test() -> void:
	var envs: Array = [
		{
			"name": "CartPole",
			"scene": load("res://environments/cartpole/neat_cartpole_env.tscn"),
			"num_inputs": 4,
			"num_outputs": 1,
			"input_ids": ([0, 1, 2, 3] as Array[int]),
			"output_ids": ([5] as Array[int]),
		},
		{
			"name": "Pong",
			"scene": load("res://environments/pong/neat_pong_env.tscn"),
			"num_inputs": 5,
			"num_outputs": 1,
			"input_ids": ([0, 1, 2, 3, 4] as Array[int]),
			"output_ids": ([6] as Array[int]),
		},
		{
			"name": "LunarLander",
			"scene": load("res://environments/lunar_lander/neat_lunar_lander_env.tscn"),
			"num_inputs": 6,
			"num_outputs": 3,
			"input_ids": ([0, 1, 2, 3, 4, 5] as Array[int]),
			"output_ids": ([7, 8, 9] as Array[int]),
		},
		{
			"name": "BipedalWalker",
			"scene": load("res://environments/bipedal_walker/neat_bipedal_walker_env.tscn"),
			"num_inputs": 8,
			"num_outputs": 4,
			"input_ids": ([0, 1, 2, 3, 4, 5, 6, 7] as Array[int]),
			"output_ids": ([9, 10, 11, 12] as Array[int]),
		},
	]
	for env_info: Dictionary in envs:
		print("\n  --- %s ---" % env_info.name)
		var ok: bool = await _train_one_env(env_info)
		if not ok:
			_failed = true
		if _failed:
			break

func _train_one_env(env_info: Dictionary) -> bool:
	var cfg := NeatConfig.new()
	cfg.num_inputs = int(env_info.num_inputs)
	cfg.num_outputs = int(env_info.num_outputs)
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = POP_SIZE
	cfg.forward_mode = "topological"
	cfg.forbid_loops = true
	cfg.speciation_method = "standard"
	cfg.compatibility_threshold = 6.0
	cfg.target_species_count = 5
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
	var pop := Population.new(cfg)
	pop.initialize()
	var env_scene: PackedScene = env_info.scene
	var input_ids: Array[int] = env_info.input_ids
	var output_ids: Array[int] = env_info.output_ids
	var bias_id: int = cfg.num_inputs
	var output_start: int = cfg.num_inputs + 1
	var evaluator := SceneEvaluator.new(self, env_scene, NUM_SLOTS, MAX_STEPS + 10, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.env_setup_fn = func(env: Node) -> void:
		env.input_node_ids = input_ids
		env.bias_node_id = bias_id
		env.output_node_id = output_start
		env.output_node_ids = output_ids
		env.set_max_steps(MAX_STEPS)
	var best_f: float = -1e9
	var elapsed: float = Time.get_ticks_msec()
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
			if fitnesses[i] > pop.best_fitness:
				pop.best_fitness = fitnesses[i]
				pop.best_genome = pop.genomes[i].duplicate()
		var avg_f: float = fitnesses.reduce(func(a, b): return a + b, 0.0) / fitnesses.size()
		print("    gen=%d  best=%.1f  avg=%.1f  species=%d  elapsed_ms=%d" % [
			pop.generation, best_f, avg_f, pop.species_count(),
			Time.get_ticks_msec() - elapsed])
		pop.evolve()
	evaluator.dispose()
	# Assertions:
	_assert(best_f != -1e9, "%s: best fitness was set" % env_info.name)
	_assert(not is_nan(best_f), "%s: best fitness is not NaN" % env_info.name)
	_assert(pop.size() == cfg.population_size, "%s: pop size stable at %d, got %d" % [env_info.name, cfg.population_size, pop.size()])
	_assert(pop.generation == MAX_GENERATIONS, "%s: generation = %d, expected %d" % [env_info.name, pop.generation, MAX_GENERATIONS])
	print("    RESULT: %s best=%.3f" % [env_info.name, best_f])
	return not _failed
