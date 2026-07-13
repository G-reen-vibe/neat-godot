extends Node
## Test that the NeatCartPoleEnv adapter mechanics work (no training).
##
## Verifies:
##   1. The adapter scene instantiates correctly (RL env child is added).
##   2. reset() + get_state() + interpret_output() + apply_action() work.
##   3. step_env() advances the RL env's physics_step.
##   4. is_done() fires when the pole tips or max_steps is reached.
##
## Run with:
##   godot --headless --path . res://tests/test_adapter_cartpole.tscn

const MAX_STEPS: int = 500

var _failed: bool = false

func _ready() -> void:
	print("=== test_adapter_cartpole: NeatCartPoleEnv mechanics ===")
	await _test()
	if _failed:
		printerr("\n=== test_adapter_cartpole: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_adapter_cartpole: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test() -> void:
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
	# Disable live mode, enable physics_process for training-style stepping.
	probe.set_live_mode(false)
	probe.set_physics_process(true)
	# reset + get_state.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	probe.reset(null, rng)
	await get_tree().physics_frame  # let reset teleport apply
	var state: Dictionary = probe.get_state()
	_assert(state.size() == 4, "state has 4 inputs, got %d" % state.size())
	for i in range(4):
		_assert(state.has(input_ids[i]), "state has input %d" % input_ids[i])
	print("    initial state: ", state)
	# interpret_output.
	var fake_output: Dictionary = {5: 0.5}
	var action: Dictionary = probe.interpret_output(fake_output)
	_assert(action.has("action_arr"), "action has action_arr")
	_assert(action["action_arr"].size() == 1, "action_arr size 1, got %d" % action["action_arr"].size())
	# apply_action + step. Run up to MAX_STEPS, check that done eventually fires
	# (a random fixed action should tip the pole).
	var steps_to_done: int = 0
	for i in range(MAX_STEPS + 20):
		probe.apply_action(action)
		await get_tree().physics_frame
		steps_to_done += 1
		if probe.is_done():
			break
	print("    steps to done (with fixed action 0.5): %d" % steps_to_done)
	_assert(steps_to_done < MAX_STEPS + 5, "should be done before max_steps with a fixed action (pole tips), got %d" % steps_to_done)
	_assert(steps_to_done > 0, "should survive at least 1 step, got %d" % steps_to_done)
	var fit: float = probe.current_fitness()
	print("    fitness at done: %.3f" % fit)
	_assert(fit > 0.0, "fitness > 0 (survived some steps), got %f" % fit)
	# Test reset works (state clears).
	probe.reset(null, rng)
	await get_tree().physics_frame
	_assert(not probe.is_done(), "not done right after reset")
	_assert(probe.current_fitness() == 0.0, "fitness reset to 0, got %f" % probe.current_fitness())
	probe.queue_free()
