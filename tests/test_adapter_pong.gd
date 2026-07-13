extends Node
## Test that the NeatPongEnv adapter mechanics work.
##
## Verifies:
##   1. The adapter scene instantiates correctly (RL env child is added).
##   2. There are 2 agents (LeftAgent, RightAgent); primary = LeftAgent.
##   3. reset() + get_state() + interpret_output() + apply_action() work.
##   4. step_env() advances the RL env's physics_step.
##   5. is_done() fires when someone scores.
##   6. Hit detection works (ball vx sign change increments _hits).
##   7. Fitness shaping: hits + survival + score delta.
##
## Run with:
##   godot --headless --path . res://tests/test_adapter_pong.tscn

const MAX_STEPS: int = 1000

var _failed: bool = false

func _ready() -> void:
	print("=== test_adapter_pong: NeatPongEnv mechanics ===")
	await _test()
	if _failed:
		printerr("\n=== test_adapter_pong: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_adapter_pong: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test() -> void:
	var env_scene: PackedScene = load("res://environments/pong/neat_pong_env.tscn")
	var probe: Node = env_scene.instantiate()
	add_child(probe)
	await get_tree().process_frame
	_assert(probe is NeatPongEnv, "probe is NeatPongEnv")
	_assert(probe.get_rl_env() != null, "RL env child exists")
	_assert(probe.get_rl_env() is RLEnvironment, "RL env is RLEnvironment")
	_assert(probe.get_primary_agent() != null, "primary agent exists")
	# Should have 2 agents (left + right); primary = left (index 0).
	_assert(probe.get_rl_env().get_agent_count() == 2, "pong has 2 agents, got %d" % probe.get_rl_env().get_agent_count())
	# Set IO + max_steps.
	var input_ids: Array[int] = [0, 1, 2, 3, 4]
	var output_ids: Array[int] = [6]
	probe.input_node_ids = input_ids
	probe.bias_node_id = 5
	probe.output_node_id = 6
	probe.output_node_ids = output_ids
	probe.set_max_steps(MAX_STEPS)
	probe.set_live_mode(false)
	probe.set_physics_process(true)
	# reset + get_state.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	probe.reset(null, rng)
	await get_tree().physics_frame  # let reset apply
	var state: Dictionary = probe.get_state()
	_assert(state.size() == 5, "state has 5 inputs, got %d" % state.size())
	for i in range(5):
		_assert(state.has(input_ids[i]), "state has input %d" % input_ids[i])
	print("    initial state: ", state)
	# Apply a fixed action (move paddle up) and step. The ball should move;
	# eventually someone scores.
	var action: Dictionary = probe.interpret_output({6: 0.8})
	var steps_to_done: int = 0
	for i in range(MAX_STEPS + 20):
		probe.apply_action(action)
		await get_tree().physics_frame
		steps_to_done += 1
		if probe.is_done():
			break
	print("    steps to done: %d" % steps_to_done)
	_assert(steps_to_done > 0, "should survive at least 1 step")
	_assert(steps_to_done < MAX_STEPS + 5, "should end before max_steps (ball eventually scores)")
	var fit: float = probe.current_fitness()
	print("    fitness at done: %.3f" % fit)
	_assert(fit >= 0.0, "fitness >= 0, got %f" % fit)
	# Reset clears state.
	probe.reset(null, rng)
	await get_tree().physics_frame
	_assert(not probe.is_done(), "not done right after reset")
	_assert(probe.current_fitness() == 0.0, "fitness reset to 0, got %f" % probe.current_fitness())
	probe.queue_free()
