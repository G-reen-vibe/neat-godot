## Classic CartPole environment with custom physics (no Godot physics engine).
## State: (x, x_dot, theta, theta_dot) -- 4 inputs.
## Action: discrete 0 (push left) or 1 (push right) -- 1 binary output.
## Done when |x| > x_threshold or |theta| > theta_threshold or step >= max_steps.
## Fitness = total steps survived (capped at max_steps).
##
## Standard CartPole constants from OpenAI Gym's implementation.
class_name CartPoleEnvironment
extends NeatEnvironment

# Physics constants.
const GRAVITY: float = 9.8
const MASS_CART: float = 1.0
const MASS_POLE: float = 0.1
const TOTAL_MASS: float = MASS_CART + MASS_POLE
const POLE_HALF_LENGTH: float = 0.5  # half the pole's actual length
const POLEMASS_LENGTH: float = MASS_POLE * POLE_HALF_LENGTH
const FORCE_MAG: float = 10.0
const TAU: float = 0.02  # seconds per step
const THETA_THRESHOLD: float = 0.20943951  # 12 degrees in radians
const X_THRESHOLD: float = 2.4

# State (x, x_dot, theta, theta_dot).
var _state: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _steps: int = 0
var _done: bool = false
var _max_steps: int = 500

# Network IO config.
var input_node_ids: Array[int] = []  # 4 inputs: x, x_dot, theta, theta_dot
var bias_node_id: int = -1
var output_node_id: int = -1  # 1 output

func _init(p_input_ids: Array[int] = [], p_bias_id: int = -1, p_output_id: int = -1, p_max_steps: int = 500) -> void:
	input_node_ids = p_input_ids
	bias_node_id = p_bias_id
	output_node_id = p_output_id
	_max_steps = p_max_steps

func reset(rng: RandomNumberGenerator = null) -> void:
	if rng != null:
		_state = [
			rng.randf_range(-0.05, 0.05),
			rng.randf_range(-0.05, 0.05),
			rng.randf_range(-0.05, 0.05),
			rng.randf_range(-0.05, 0.05),
		]
	else:
		_state = [0.0, 0.0, 0.0, 0.0]
	_steps = 0
	_done = false

func initial_state() -> Dictionary:
	var d: Dictionary = {}
	for i in range(input_node_ids.size()):
		d[input_node_ids[i]] = _state[i]
	return d

func interpret_output(output: Dictionary) -> Dictionary:
	# Discretize: action 1 if out > 0 else 0 (works for tanh or sigmoid).
	var v: float = float(output.get(output_node_id, 0.0))
	return {"action": 1 if v > 0.0 else 0}

func step(action: Dictionary) -> Dictionary:
	var a: int = int(action.get("action", 0))
	var force: float = FORCE_MAG if a == 1 else -FORCE_MAG
	var x: float = _state[0]
	var x_dot: float = _state[1]
	var theta: float = _state[2]
	var theta_dot: float = _state[3]
	var sintheta: float = sin(theta)
	var costheta: float = cos(theta)
	var temp: float = (force + POLEMASS_LENGTH * theta_dot * theta_dot * sintheta) / TOTAL_MASS
	var thetaacc: float = (GRAVITY * sintheta - costheta * temp) / (POLE_HALF_LENGTH * (4.0 / 3.0 - MASS_POLE * costheta * costheta / TOTAL_MASS))
	var xacc: float = temp - POLEMASS_LENGTH * thetaacc * costheta / TOTAL_MASS
	# Euler integration.
	x = x + TAU * x_dot
	x_dot = x_dot + TAU * xacc
	theta = theta + TAU * theta_dot
	theta_dot = theta_dot + TAU * thetaacc
	_state = [x, x_dot, theta, theta_dot]
	_steps += 1
	# Check termination.
	if absf(x) > X_THRESHOLD or absf(theta) > THETA_THRESHOLD:
		_done = true
	if _steps >= _max_steps:
		_done = true
	# Build next state input.
	var d: Dictionary = {}
	for i in range(input_node_ids.size()):
		d[input_node_ids[i]] = _state[i]
	return d

func is_done() -> bool:
	return _done

func current_fitness() -> float:
	return float(_steps)

func is_solved() -> bool:
	return _steps >= _max_steps

func state() -> Array[float]:
	return _state

func get_visual_state() -> Dictionary:
	return {
		"x": _state[0],
		"x_dot": _state[1],
		"theta": _state[2],
		"theta_dot": _state[3],
		"steps": _steps,
		"max_steps": _max_steps,
		"done": _done,
		"x_threshold": X_THRESHOLD,
		"theta_threshold": THETA_THRESHOLD,
		"track_half_length": X_THRESHOLD,
		"pole_half_length": POLE_HALF_LENGTH,
	}
