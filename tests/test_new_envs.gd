extends Node
## Test new environments: Pong, SpiderWalker2D, SpiderWalker3D.
## Run with: godot --headless --path . res://tests/test_new_envs.tscn

var tracker: InnovationTracker
var rng: RandomNumberGenerator

func _ready() -> void:
	print("=== test_new_envs ===")
	tracker = InnovationTracker.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 42

	_test_pong_basic()
	_test_pong_tournament()
	_test_spider_2d_basic()
	_test_spider_3d_basic()

	print("\n=== test_new_envs: ALL PASSED ===")
	get_tree().quit()

func _test_pong_basic() -> void:
	# Build a simple genome.
	var g := _build_simple_genome([0, 1, 2, 3, 4, 5], 6, [7], 6, 1)
	var env := PongEnvironment.new([0, 1, 2, 3, 4, 5], 6, 7)
	env.set_player_a(g)
	env.set_player_b(null)  # static opponent
	env.reset(rng)
	assert(not env.is_done(), "Fresh env should not be done")
	var state: Dictionary = env.initial_state()
	assert(state.size() == 6, "Pong should have 6 input ids in state")
	# Run a few steps.
	for _i in range(50):
		var out: Dictionary = g.forward(state, "topological")
		var action: Dictionary = env.interpret_output(out, {})
		state = env.step(action)
		if env.is_done():
			break
	var fit: float = env.current_fitness()
	assert(fit >= 0.0, "Fitness should be non-negative")
	print("  pong basic: OK (fit=%.2f, score_a=%d, score_b=%d, hits_a=%d)" % [fit, env._score_a, env._score_b, env._hits_a])

func _test_pong_tournament() -> void:
	# Build two different genomes.
	var g1 := _build_simple_genome([0, 1, 2, 3, 4, 5], 6, [7], 6, 1)
	var g2 := _build_simple_genome([0, 1, 2, 3, 4, 5], 6, [7], 6, 1)
	# Make g2 slightly different.
	for c: ConnectionGene in g2.connections.values():
		c.weight += 0.1
	var env := PongEnvironment.new([0, 1, 2, 3, 4, 5], 6, 7)
	env.set_player_a(g1)
	env.set_player_b(g2)
	env.reset(rng)
	var state: Dictionary = env.initial_state()
	while not env.is_done():
		var out_a: Dictionary = g1.forward(state, "topological")
		var out_b: Dictionary = g2.forward(state, "topological")
		var action: Dictionary = env.interpret_output(out_a, out_b)
		state = env.step(action)
	var fit: float = env.current_fitness()
	print("  pong tournament: OK (fit=%.2f, score_a=%d, score_b=%d)" % [fit, env._score_a, env._score_b])

func _test_spider_2d_basic() -> void:
	var input_ids: Array[int] = []
	for i in range(12):
		input_ids.append(i)
	var output_ids: Array[int] = [13, 14, 15, 16, 17, 18, 19, 20]
	var g := _build_simple_genome(input_ids, 12, output_ids, 12, 8)
	var env := SpiderWalker2DEnvironment.new(input_ids, 12, output_ids)
	env.reset(rng)
	assert(not env.is_done(), "Fresh env should not be done")
	var state: Dictionary = env.initial_state()
	assert(state.size() == 12, "Spider2D should have 12 input ids")
	# Run simulation.
	for _i in range(100):
		var out: Dictionary = g.forward(state, "topological")
		var action: Dictionary = env.interpret_output(out)
		state = env.step(action)
		if env.is_done():
			break
	var fit: float = env.current_fitness()
	assert(fit >= 0.0, "Fitness should be non-negative")
	# Visual state should have legs.
	var vs: Dictionary = env.get_visual_state()
	assert(vs.has("feet"), "Visual state should have feet")
	assert((vs["feet"] as Array).size() == 4, "Should have 4 legs")
	print("  spider 2d basic: OK (fit=%.3f, dist=%.3f)" % [fit, float(vs.get("distance", 0.0))])

func _test_spider_3d_basic() -> void:
	var input_ids: Array[int] = []
	for i in range(16):
		input_ids.append(i)
	var output_ids: Array[int] = [17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28]
	var g := _build_simple_genome(input_ids, 16, output_ids, 16, 12)
	var env := SpiderWalker3DEnvironment.new(input_ids, 16, output_ids)
	env.reset(rng)
	assert(not env.is_done(), "Fresh env should not be done")
	var state: Dictionary = env.initial_state()
	assert(state.size() == 16, "Spider3D should have 16 input ids")
	# Run simulation.
	for _i in range(100):
		var out: Dictionary = g.forward(state, "topological")
		var action: Dictionary = env.interpret_output(out)
		state = env.step(action)
		if env.is_done():
			break
	var fit: float = env.current_fitness()
	assert(fit >= 0.0, "Fitness should be non-negative")
	var vs: Dictionary = env.get_visual_state()
	assert(vs.has("feet"), "Visual state should have feet")
	assert((vs["feet"] as Array).size() == 4, "Should have 4 legs")
	print("  spider 3d basic: OK (fit=%.3f, dist=%.3f)" % [fit, float(vs.get("distance", 0.0))])

func _build_simple_genome(input_ids: Array[int], bias_id: int, output_ids: Array[int], num_inputs: int, num_outputs: int) -> Genome:
	var g := Genome.new()
	for i in range(num_inputs):
		g.add_node(NodeGene.new(input_ids[i], NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR))
	g.add_node(NodeGene.new(bias_id, NodeGene.Kind.BIAS, ActivationFunctions.Func.LINEAR))
	for i in range(num_outputs):
		g.add_node(NodeGene.new(output_ids[i], NodeGene.Kind.OUTPUT, ActivationFunctions.Func.TANH))
	# Fully connect inputs+bias -> outputs.
	var sources: Array[int] = input_ids.duplicate()
	sources.append(bias_id)
	for src in sources:
		for oid in output_ids:
			var innov := tracker.get_connection_innov(src, oid)
			g.add_connection(ConnectionGene.new(innov, src, oid, rng.randf_range(-1.0, 1.0)))
	return g
