extends Node
## Phase 2 test: Pong with real physics via SceneEvaluator.
## Run with: godot --headless --path . res://tests/test_pong_scene.tscn

const MAX_GENERATIONS: int = 10
const POP_SIZE: int = 30
const NUM_SLOTS: int = 30
const MAX_STEPS: int = 1200
const SPEEDUP: float = 2.0

var _failed: bool = false

func _ready() -> void:
	print("=== test_pong_scene: real-physics Pong via SceneEvaluator ===")
	await _test_pong()
	if _failed:
		printerr("\n=== test_pong_scene: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_pong_scene: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test_pong() -> void:
	var cfg := NeatConfig.new()
	cfg.num_inputs = 6
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
	var env_scene: PackedScene = load("res://environments/pong/pong_environment.tscn")
	var input_ids: Array[int] = [0, 1, 2, 3, 4, 5]
	var bias_id: int = 6
	var output_id: int = 7
	var evaluator := SceneEvaluator.new(self, env_scene, NUM_SLOTS, MAX_STEPS + 10, "topological")
	evaluator.speedup = SPEEDUP
	evaluator.episodes_per_genome = 1
	evaluator.env_setup_fn = func(env: Node) -> void:
		env.input_node_ids = input_ids
		env.bias_node_id = bias_id
		env.output_node_id = output_id
		# Pong: paddle B stays static during training (no opponent).
		env.set_player_b(null)
	var best_f: float = -1e9
	var elapsed: float = Time.get_ticks_msec()
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		if gen == 0:
			print("    gen 0 fitness range: min=%.2f max=%.2f avg=%.2f" % [
				fitnesses.min(), fitnesses.max(),
				fitnesses.reduce(func(a, b): return a + b, 0.0) / fitnesses.size()])
		if gen % 2 == 0 or gen == MAX_GENERATIONS - 1:
			print("    gen=%d  best=%.3f  species=%d  elapsed_ms=%d" % [
				pop.generation, best_f, pop.species_count(), Time.get_ticks_msec() - elapsed])
		pop.evolve()
	evaluator.dispose()
	_assert(best_f >= 0.0, "Pong: best fitness should be >= 0, got %.3f" % best_f)
	_assert(pop.size() == cfg.population_size, "Pong: pop size stable")
	print("    RESULT: best=%.3f" % best_f)
