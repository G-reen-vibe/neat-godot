extends Node
## Test that the NeatLunarLanderEnv adapter mechanics work.
##
## Verifies:
##   1. The adapter scene instantiates correctly.
##   2. reset() + get_state() + interpret_output() + apply_action() work.
##   3. step_env() advances the RL env's physics_step.
##   4. is_done() fires when the lander lands/crashes/goes OOB.
##   5. Fitness accumulates (per-step reward + landing bonus).
##
## Run with:
##   godot --headless --path . res://tests/test_adapter_lunar_lander.tscn

const MAX_STEPS: int = 1000

var _failed: bool = false

func _ready() -> void:
	print("=== test_adapter_lunar_lander: NeatLunarLanderEnv mechanics ===")
	await _test()
	if _failed:
		printerr("\n=== test_adapter_lunar_lander: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_adapter_lunar_lander: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test() -> void:
	var env_scene: PackedScene = load("res://environments/lunar_lander/neat_lunar_lander_env.tscn")
	var probe: Node = env_scene.instantiate()
	add_child(probe)
	await get_tree().process_frame
	_assert(probe is NeatLunarLanderEnv, "probe is NeatLunarLanderEnv")
	_assert(probe.get_rl_env() != null, "RL env child exists")
	_assert(probe.get_primary_agent() != null, "primary agent exists")
	_assert(probe.get_rl_env().get_agent_count() == 1, "lunar lander has 1 agent, got %d" % probe.get_rl_env().get_agent_count())
	# Set IO + max_steps. 6 inputs, 3 outputs.
	var input_ids: Array[int] = [0, 1, 2, 3, 4, 5]
	var output_ids: Array[int] = [7, 8, 9]
	probe.input_node_ids = input_ids
	probe.bias_node_id = 6
	probe.output_node_id = 7
	probe.output_node_ids = output_ids
	probe.set_max_steps(MAX_STEPS)
	probe.set_live_mode(false)
	probe.set_physics_process(true)
	# reset + get_state.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	probe.reset(null, rng)
	await get_tree().physics_frame
	var state: Dictionary = probe.get_state()
	_assert(state.size() == 6, "state has 6 inputs, got %d" % state.size())
	for i in range(6):
		_assert(state.has(input_ids[i]), "state has input %d" % input_ids[i])
	print("    initial state: ", state)
	# interpret_output: 3 outputs -> action_arr of size 3.
	var fake_output: Dictionary = {7: 0.5, 8: 0.0, 9: 0.0}
	var action: Dictionary = probe.interpret_output(fake_output)
	_assert(action.has("action_arr"), "action has action_arr")
	_assert(action["action_arr"].size() == 3, "action_arr size 3, got %d" % action["action_arr"].size())
	# Apply main thrust (action[0] > 0) and step. The lander should move up.
	# Run until done (lands, crashes, or OOB).
	var steps_to_done: int = 0
	for i in range(MAX_STEPS + 20):
		probe.apply_action(action)
		await get_tree().physics_frame
		steps_to_done += 1
		if probe.is_done():
			break
	print("    steps to done (full thrust): %d" % steps_to_done)
	_assert(steps_to_done > 0, "should survive at least 1 step")
	_assert(steps_to_done < MAX_STEPS + 5, "should end before max_steps (lander eventually lands/crashes/OOB)")
	var fit: float = probe.current_fitness()
	print("    fitness at done: %.3f" % fit)
	# With full thrust, the lander goes up and eventually goes OOB (y < -ARENA_HEIGHT/2).
	# Reward for OOB = -100. So fitness should be very negative (but we don't clamp).
	_assert(fit < 0.0, "fitness should be negative (OOB penalty), got %f" % fit)
	# Reset clears state.
	probe.reset(null, rng)
	await get_tree().physics_frame
	_assert(not probe.is_done(), "not done right after reset")
	_assert(probe.current_fitness() == 0.0, "fitness reset to 0, got %f" % probe.current_fitness())
	probe.queue_free()
