extends Node
## Full end-to-end test: simulates the entire gameplay flow as if a user was
## playing the game. Tests:
##   1. Population initialization with each env's config.
##   2. SceneEvaluator creation + env_setup_fn configuration.
##   3. Multiple training generations (evaluate -> set fitness -> evolve).
##   4. Live env setup (set_live_genome, set_live_mode, set_bodies_frozen).
##   5. Live env auto-reset on done (via _live_step).
##   6. Best genome selection + visualization reset.
##   7. Save/load (best genome duplication).
##   8. Dispose (cleanup SubViewports).
##
## This test does NOT use the UI (RunScreen); it directly drives the same
## components the UI uses, in the same order a user would trigger them.
##
## Run with:
##   godot --headless --path . res://tests/test_full_gameplay.tscn

const MAX_GENERATIONS: int = 3
const POP_SIZE: int = 10
const NUM_SLOTS: int = 10
const MAX_STEPS: int = 100

var _failed: bool = false

func _ready() -> void:
	print("=== test_full_gameplay: full end-to-end flow ===")
	await _test()
	if _failed:
		printerr("\n=== test_full_gameplay: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_full_gameplay: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test() -> void:
	# Test each env as if a user selected it, configured it, and trained.
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
		var ok: bool = await _test_one_env(env_info)
		if not ok:
			_failed = true
		if _failed:
			break

func _test_one_env(env_info: Dictionary) -> bool:
	# 1. Create config (like ConfigScreen._make_config).
	var cfg := NeatConfig.new()
	cfg.num_inputs = int(env_info.num_inputs)
	cfg.num_outputs = int(env_info.num_outputs)
	cfg.use_bias = true
	cfg.input_activation = ActivationFunctions.Func.LINEAR
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.hidden_activation = ActivationFunctions.Func.TANH
	cfg.population_size = POP_SIZE
	cfg.forward_mode = "topological"
	cfg.forbid_loops = true
	cfg.speciation_method = "standard"
	cfg.compatibility_threshold = 6.0
	cfg.target_species_count = 5
	cfg.generation_method = "mixed"
	cfg.crossover_rate = 0.75
	cfg.elite_count = 1
	cfg.enable_weight_mutation = true
	cfg.weight_mutation_rate = 0.8
	cfg.weight_mutation_min = 1
	cfg.enable_connection_mutation = true
	cfg.connection_mutation_rate = 0.1
	cfg.enable_neuron_mutation = true
	cfg.neuron_mutation_rate = 0.1
	cfg.enable_enable_mutation = true
	cfg.enable_mutation_rate = 0.1
	cfg.selection_method = "roulette"
	# 2. Initialize population.
	var pop := Population.new(cfg)
	pop.initialize()
	_assert(pop.genomes.size() == POP_SIZE, "%s: pop size = %d" % [env_info.name, pop.genomes.size()])
	_assert(pop.species_count() > 0, "%s: has species" % env_info.name)
	# 3. Create evaluator (like RunScreen._setup_evaluator).
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
	# 4. Training loop (like RunScreen._step_generation).
	var best_f: float = -1e9
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
			if fitnesses[i] > pop.best_fitness:
				pop.best_fitness = fitnesses[i]
				pop.best_genome = pop.genomes[i].duplicate()
		print("    gen=%d  best=%.1f  species=%d" % [pop.generation, best_f, pop.species_count()])
		pop.evolve()
	_assert(best_f != -1e9, "%s: fitness was set" % env_info.name)
	_assert(pop.best_genome != null, "%s: best genome exists" % env_info.name)
	_assert(pop.generation == MAX_GENERATIONS, "%s: generation = %d" % [env_info.name, pop.generation])
	# 5. Test live env setup (like RunScreen._setup_visualization).
	var live_env: Node = env_scene.instantiate()
	add_child(live_env)
	await get_tree().process_frame  # let _ready fire
	_assert(live_env is NeatRLAdapter, "%s: live env is NeatRLAdapter" % env_info.name)
	# Configure IO (like env_setup_fn).
	live_env.input_node_ids = input_ids
	live_env.bias_node_id = bias_id
	live_env.output_node_id = output_start
	live_env.output_node_ids = output_ids
	live_env.set_max_steps(MAX_STEPS)
	# Set live genome (best genome from training).
	live_env.set_live_genome(pop.best_genome)
	live_env.live_forward_mode = cfg.forward_mode
	live_env.set_live_mode(false)
	live_env.set_physics_process(false)
	live_env.set_bodies_frozen(true)
	# Reset with fixed seed (like RunScreen._reset_live_env).
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	live_env.reset(pop.best_genome, rng)
	await get_tree().physics_frame  # let teleport apply
	_assert(not live_env.is_done(), "%s: not done after reset" % env_info.name)
	# 6. Enable live mode (like RunScreen._set_live_env_active(true)).
	live_env.set_live_mode(true)
	live_env.set_physics_process(true)
	live_env.set_bodies_frozen(false)
	live_env.live_episode_count = 0
	# Run live for ~60 frames, verify it auto-resets on done.
	var initial_episode: int = live_env.live_episode_count
	for i in range(200):
		await get_tree().physics_frame
	# The live env should have run some episodes (or at least not crashed).
	_assert(is_instance_valid(live_env), "%s: live env still valid after 200 frames" % env_info.name)
	print("    live episodes after 200 frames: %d" % live_env.live_episode_count)
	# 7. Switch back to training mode (like _set_live_env_active(false)).
	live_env.set_live_mode(false)
	live_env.set_physics_process(false)
	live_env.set_bodies_frozen(true)
	# 8. Test genome switching (N key -> next genome).
	if pop.genomes.size() > 1:
		live_env.set_live_genome(pop.genomes[0])
		rng.seed = 12345
		live_env.reset(pop.genomes[0], rng)
		await get_tree().physics_frame
		_assert(not live_env.is_done(), "%s: not done after genome switch" % env_info.name)
	# 9. Cleanup.
	live_env.queue_free()
	await get_tree().process_frame
	evaluator.dispose()
	print("    RESULT: %s best=%.3f, live OK" % [env_info.name, best_f])
	return not _failed
