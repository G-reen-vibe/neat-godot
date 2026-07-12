extends Node
## Phase 4 test: Spider 3D with real 3D physics.
## Run with: godot --headless --path . res://tests/test_spider_3d_scene.tscn

const MAX_GENERATIONS: int = 6
const POP_SIZE: int = 20
const NUM_SLOTS: int = 20
const SPEEDUP: float = 2.0

var _failed: bool = false

func _ready() -> void:
	print("=== test_spider_3d_scene: real-physics Spider 3D via SceneEvaluator ===")
	await _test_spider_3d()
	if _failed:
		printerr("\n=== test_spider_3d_scene: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_spider_3d_scene: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test_spider_3d() -> void:
	var cfg := NeatConfig.new()
	cfg.num_inputs = 16
	cfg.num_outputs = 12
	cfg.use_bias = true
	cfg.output_activation = ActivationFunctions.Func.TANH
	cfg.population_size = POP_SIZE
	cfg.forward_mode = "topological"
	cfg.forbid_loops = true
	cfg.speciation_method = "standard"
	cfg.compatibility_threshold = 6.0
	cfg.target_species_count = 6
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
	var env_scene: PackedScene = load("res://environments/spider_3d/spider_walker_3d_environment.tscn")
	var input_ids: Array[int] = []
	for i in range(16):
		input_ids.append(i)
	var bias_id: int = 16
	var output_ids: Array[int] = []
	for i in range(12):
		output_ids.append(17 + i)
	var evaluator := SceneEvaluator.new(self, env_scene, NUM_SLOTS, 1100, "topological")
	evaluator.speedup = SPEEDUP
	evaluator.episodes_per_genome = 1
	evaluator.env_setup_fn = func(env: Node) -> void:
		env.input_node_ids = input_ids
		env.bias_node_id = bias_id
		env.output_node_ids = output_ids
	var best_f: float = -1e9
	var elapsed: float = Time.get_ticks_msec()
	for gen in range(MAX_GENERATIONS):
		var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
			if fitnesses[i] > best_f:
				best_f = fitnesses[i]
		if gen == 0:
			print("    gen 0 fitness range: min=%.3f max=%.3f avg=%.3f" % [
				fitnesses.min(), fitnesses.max(),
				fitnesses.reduce(func(a, b): return a + b, 0.0) / fitnesses.size()])
		print("    gen=%d  best=%.3f  species=%d  elapsed_ms=%d" % [
			pop.generation, best_f, pop.species_count(), Time.get_ticks_msec() - elapsed])
		pop.evolve()
	evaluator.dispose()
	_assert(best_f >= 0.0, "Spider3D: best fitness should be >= 0, got %.3f" % best_f)
	_assert(pop.size() == cfg.population_size, "Spider3D: pop size stable")
	print("    RESULT: best=%.3f" % best_f)
