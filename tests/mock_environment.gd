## Minimal NeatEnvironment for backend unit tests.
##
## This is NOT a user-facing env (not in the EnvSelectScreen list). It exists
## so the backend tests (test_perf, test_speciation_adapt, test_purge_debug)
## can exercise the Evaluator with a simple synchronous env that doesn't
## require physics. It implements a basic XOR-like task: 2 inputs, 1 output,
## fitness = (4 - total_error)^2 so max = 16 when error = 0.
class_name MockTestEnv
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

# Input/output node ids (set by tests; mirrors NeatPhysicsEnvironment's fields).
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
        var out_val: float = float(action.get(output_node_id, 0.0))
        var target: float = TARGETS[_idx]
        _total_error += absf(out_val - target)
        _idx += 1
        if _idx >= INPUTS.size():
                return {}
        var pair: Array = INPUTS[_idx]
        return {input_node_ids[0]: pair[0], input_node_ids[1]: pair[1]}

func is_done() -> bool:
        return _idx >= INPUTS.size()

func current_fitness() -> float:
        return pow(maxf(0.0, 4.0 - _total_error), 2.0)
