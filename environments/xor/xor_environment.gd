## XOR environment: 2 inputs + 1 bias, 1 output.
## Fitness = (4 - total_error)² so max = 16 when error = 0.
## Considered solved when fitness >= 15.5 (total error <= ~0.12).
class_name XorEnvironment
extends NeatEnvironment

const INPUTS: Array = [
	[0.0, 0.0],
	[0.0, 1.0],
	[1.0, 0.0],
	[1.0, 1.0],
]
const TARGETS: Array = [0.0, 1.0, 1.0, 0.0]

var _idx: int = 0
var _total_error: float = 0.0
var _solved_threshold: float = 15.5

# Input/output node ids (set by evaluator).
var input_node_ids: Array[int] = []
var bias_node_id: int = -1
var output_node_id: int = -1

func _init(p_input_ids: Array[int] = [0, 1], p_bias_id: int = 2, p_output_id: int = 3) -> void:
	input_node_ids = p_input_ids
	bias_node_id = p_bias_id
	output_node_id = p_output_id

func reset(rng: RandomNumberGenerator = null) -> void:
	_idx = 0
	_total_error = 0.0

func initial_state() -> Dictionary:
	var pair: Array = INPUTS[_idx]
	return {input_node_ids[0]: pair[0], input_node_ids[1]: pair[1]}

func interpret_output(output: Dictionary) -> Dictionary:
	return output

func step(action: Dictionary) -> Dictionary:
	# Compute error for the current input.
	var out_val: float = float(action.get(output_node_id, 0.0))
	var target: float = TARGETS[_idx]
	_total_error += absf(out_val - target)
	_idx += 1
	if _idx >= INPUTS.size():
		return {}  # done
	var pair: Array = INPUTS[_idx]
	return {input_node_ids[0]: pair[0], input_node_ids[1]: pair[1]}

func is_done() -> bool:
	return _idx >= INPUTS.size()

func current_fitness() -> float:
	# Clamp at 0 so that high error doesn't get squared into a high fitness.
	# Max fitness = 16 (when total_error = 0). Min = 0.
	return pow(maxf(0.0, 4.0 - _total_error), 2.0)

func is_solved() -> bool:
	return current_fitness() >= _solved_threshold
