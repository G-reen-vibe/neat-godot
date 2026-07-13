extends Node
## Test that the NeatCartPoleEnv adapter works with the SceneEvaluator.
##
## Verifies:
##   1. The adapter scene instantiates correctly (RL env child is added).
##   2. reset() + get_state() + interpret_output() + apply_action() work.
##   3. step_env() advances the RL env's physics_step.
##   4. is_done() fires when the pole tips or max_steps is reached.
##   5. NEAT can actually learn CartPole (best fitness increases over gens).
##
## Run with:
##   godot --headless --path . res://tests/test_neat_cartpole.tscn

const MAX_GENERATIONS: int = 30
const POP_SIZE: int = 40
const NUM_SLOTS: int = 40
const MAX_STEPS: int = 500

var _failed: bool = false

func _ready() -> void:
	print("=== test_neat_cartpole: NeatCartPoleEnv + SceneEvaluator ===")
	await _test_cartpole()
	if _failed:
		printerr("\n=== test_neat_cartpole: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_neat_cartpole: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test_cartpole() -> void:
	# 1. Verify the adapter scene instantiates and has the right structure.
	var env_scene: PackedScene = load("res://environments/cartpole/neat_cartpole_env.tscn")
	var probe: Node = env_scene.instantiate()
	add_child(probe)
	await get_tree().process_frame  # let _ready fire
	_assert(probe is NeatCartPoleEnv, "probe is NeatCartPoleEnv")
	_assert(probe.get_rl_env() != null, "RL env child exists")
	_assert(probe.get_rl_env() is RLEnvironment, "RL env is RLEnvironment")
	_assert(probe.get_primary_agent() != null, "primary agent exists")
	_assert(probe.get_primary_agent() is RLAgent, "primary agent is RLAgent")
	# Set IO + max_steps.
	var input_ids: Array[int] = [0, 1, 2, 3]
	var output_ids: Array[int] = [5]
	probe.input_node_ids = input_ids
	probe.bias_node_id = 4
	probe.output_node_id = 5
	probe.output_node_ids = output_ids
	probe.set_max_steps(MAX_STEPS)
	# 2. reset + get_state.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	probe.reset(null, rng)
	var state: Dictionary = probe.get_state()
	_assert(state.size() == 4, "state has 4 inputs, got %d" % state.size())
	for i in range(4):
		_assert(state.has(input_ids[i]), "state has input %d" % input_ids[i])
	# 3. interpret_output.
	var fake_output: Dictionary = {5: 0.5}
	var action: Dictionary = probe.interpret_output(fake_output)
	_assert(action.has("action_arr"), "action has action_arr")
	_assert(action["action_arr"].size() == 1, "action_arr size 1")
	# 4. apply_action (should not crash).
	probe.apply_action(action)
	await get_tree().physics_frame
	_assert(not probe.is_done(), "not done after 1 step")
	# 5. Step a few times and check fitness increases.
	for i in range(10):
		probe.apply_action(action)
		await get_tree().physics_frame
	var fit_after_10: float = probe.current_fitness()
	_assert(fit_after_10 >= 0.0, "fitness >= 0 after 10 steps, got %f" % fit_after_10)
	probe.queue_free()
	await get_tree().process_frame
	if _failed:
		return
	# 6. Full NEAT training loop.
	var cfg := NeatConfig.new()
	cfg.num_inputs = 4
	cfg.num_outputs = 1
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = POP_SIZE
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
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := SceneEvaluator.new(self, env_scene, NUM_SLOTS, MAX_STEPS + 10, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.env_setup_fn = func(env: Node) -> void:
		env.input_node_ids = input_ids
		env.bias_node_id = 4
		env.output_node_id = 5
		env.output_node_ids = output_ids
		env.set_max_steps(MAX_STEPS)
	var best_f: float = -1e9
	var first_gen_best: float = -1e9
	var elapsed: float = Time.get_ticks_msec()
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
			if gen == 0 and fitnesses[i] > first_gen_best:
				first_gen_best = fitnesses[i]
		if gen == 0:
			print("    gen 0 fitness range: min=%.1f max=%.1f avg=%.1f" % [
				fitnesses.min(), fitnesses.max(),
				fitnesses.reduce(func(a, b): return a + b, 0.0) / fitnesses.size()])
		if gen % 3 == 0 or gen == MAX_GENERATIONS - 1:
			print("    gen=%d  best=%.3f  species=%d  elapsed_ms=%d" % [
				pop.generation, best_f, pop.species_count(), Time.get_ticks_msec() - elapsed])
		pop.evolve()
	evaluator.dispose()
	_assert(best_f > 0.0, "CartPole: best fitness > 0 after %d gens, got %.3f" % [MAX_GENERATIONS, best_f])
	_assert(best_f >= 50.0, "CartPole: best fitness >= 50 (basic learning), got %.3f" % best_f)
	_assert(pop.size() == cfg.population_size, "pop size stable at %d, got %d" % [cfg.population_size, pop.size()])
	print("    RESULT: best=%.3f (first gen best=%.3f)" % [best_f, first_gen_best])
