extends Node
## Final comprehensive end-to-end test: simulates a complete user session
## for each env, as if someone was playing the game:
##   1. Select env (by index)
##   2. Create config (like ConfigScreen)
##   3. Initialize population
##   4. Setup evaluator + live env
##   5. Train for N generations (like RunScreen._step_generation)
##   6. Pause (speed=0): enable live mode, run live env for ~60 frames
##   7. Switch genome (N key -> next genome), verify live env resets
##   8. Switch back to best (B key), verify live env resets
##   9. Resume training (speed=1), run 1 more generation
##  10. Cleanup (dispose evaluator, free live env)
##
## Run with:
##   godot --headless --path . res://tests/test_final_e2e.tscn

const TRAINING_GENS: int = 3
const POP_SIZE: int = 10
const NUM_SLOTS: int = 10
const MAX_STEPS: int = 100
const LIVE_FRAMES: int = 60

var _failed: bool = false

func _ready() -> void:
	print("=== test_final_e2e: complete user session simulation ===")
	await _test()
	if _failed:
		printerr("\n=== test_final_e2e: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_final_e2e: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test() -> void:
	var envs: Array = [
		{"name": "CartPole", "scene": load("res://environments/cartpole/neat_cartpole_env.tscn"),
		 "num_inputs": 4, "num_outputs": 1,
		 "input_ids": ([0, 1, 2, 3] as Array[int]),
		 "output_ids": ([5] as Array[int])},
		{"name": "Pong", "scene": load("res://environments/pong/neat_pong_env.tscn"),
		 "num_inputs": 5, "num_outputs": 1,
		 "input_ids": ([0, 1, 2, 3, 4] as Array[int]),
		 "output_ids": ([6] as Array[int])},
		{"name": "LunarLander", "scene": load("res://environments/lunar_lander/neat_lunar_lander_env.tscn"),
		 "num_inputs": 6, "num_outputs": 3,
		 "input_ids": ([0, 1, 2, 3, 4, 5] as Array[int]),
		 "output_ids": ([7, 8, 9] as Array[int])},
		{"name": "BipedalWalker", "scene": load("res://environments/bipedal_walker/neat_bipedal_walker_env.tscn"),
		 "num_inputs": 8, "num_outputs": 4,
		 "input_ids": ([0, 1, 2, 3, 4, 5, 6, 7] as Array[int]),
		 "output_ids": ([9, 10, 11, 12] as Array[int])},
	]
	for env_info: Dictionary in envs:
		print("\n  --- %s ---" % env_info.name)
		var ok: bool = await _test_session(env_info)
		if not ok:
			_failed = true
		if _failed:
			break

func _test_session(env_info: Dictionary) -> bool:
	# 1. Create config.
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
	_assert(pop.genomes.size() == POP_SIZE, "%s: pop initialized" % env_info.name)
	# 3. Setup evaluator.
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
	# 4. Setup live env (like RunScreen._setup_visualization).
	var live_env: NeatRLAdapter = env_scene.instantiate() as NeatRLAdapter
	add_child(live_env)
	await get_tree().process_frame
	live_env.input_node_ids = input_ids
	live_env.bias_node_id = bias_id
	live_env.output_node_id = output_start
	live_env.output_node_ids = output_ids
	live_env.set_max_steps(MAX_STEPS)
	live_env.set_live_genome(pop.best_genome if pop.best_genome else pop.genomes[0])
	live_env.live_forward_mode = cfg.forward_mode
	live_env.set_live_mode(false)
	live_env.set_physics_process(false)
	live_env.set_bodies_frozen(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	live_env.reset(pop.best_genome if pop.best_genome else pop.genomes[0], rng)
	await get_tree().physics_frame
	# 5. Train for N generations.
	var best_f: float = -1e9
	for gen in range(TRAINING_GENS):
		# Training mode: live env frozen, physics_process off.
		live_env.set_live_mode(false)
		live_env.set_physics_process(false)
		live_env.set_bodies_frozen(true)
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
		# Update live genome to best.
		live_env.set_live_genome(pop.best_genome)
	_assert(best_f != -1e9, "%s: training produced fitness" % env_info.name)
	_assert(pop.best_genome != null, "%s: best genome exists" % env_info.name)
	# 6. Pause: enable live mode.
	live_env.set_live_mode(true)
	live_env.set_physics_process(true)
	live_env.set_bodies_frozen(false)
	live_env.live_episode_count = 0
	# Run live for LIVE_FRAMES frames.
	for i in range(LIVE_FRAMES):
		await get_tree().physics_frame
	_assert(is_instance_valid(live_env), "%s: live env valid after %d frames" % [env_info.name, LIVE_FRAMES])
	var eps_after_live: int = live_env.live_episode_count
	print("    live episodes after %d frames: %d" % [LIVE_FRAMES, eps_after_live])
	# 7. Switch genome (N key -> next genome).
	var prev_genome_idx: int = 0
	var next_genome: Genome = pop.genomes[prev_genome_idx]
	live_env.set_live_genome(next_genome)
	rng.seed = 12345
	live_env.reset(next_genome, rng)
	await get_tree().physics_frame
	_assert(not live_env.is_done(), "%s: not done after genome switch" % env_info.name)
	# Run a few frames with the new genome.
	for i in range(30):
		await get_tree().physics_frame
	_assert(is_instance_valid(live_env), "%s: live env valid after genome switch" % env_info.name)
	# 8. Switch back to best (B key).
	live_env.set_live_genome(pop.best_genome)
	rng.seed = 12345
	live_env.reset(pop.best_genome, rng)
	await get_tree().physics_frame
	_assert(not live_env.is_done(), "%s: not done after best genome reset" % env_info.name)
	# 9. Resume training (1 more generation).
	live_env.set_live_mode(false)
	live_env.set_physics_process(false)
	live_env.set_bodies_frozen(true)
	var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
	for i in range(pop.genomes.size()):
		pop.genomes[i].fitness = fitnesses[i]
		if fitnesses[i] > best_f:
			best_f = fitnesses[i]
		if fitnesses[i] > pop.best_fitness:
			pop.best_fitness = fitnesses[i]
			pop.best_genome = pop.genomes[i].duplicate()
	print("    gen=%d (resumed)  best=%.1f  species=%d" % [pop.generation, best_f, pop.species_count()])
	pop.evolve()
	_assert(pop.generation == TRAINING_GENS + 1, "%s: generation = %d, expected %d" % [env_info.name, pop.generation, TRAINING_GENS + 1])
	# 10. Cleanup.
	live_env.set_physics_process(false)
	live_env.set_live_mode(false)
	live_env.queue_free()
	await get_tree().process_frame
	evaluator.dispose()
	print("    RESULT: %s best=%.3f, full session OK" % [env_info.name, best_f])
	return not _failed
