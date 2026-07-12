## Classic Acrobot environment with custom physics.
## Two-link underactuated pendulum: actuate only the second joint, goal is to
## swing the tip of the second link above the height threshold.
##
## State: (theta1, theta2, theta1_dot, theta2_dot) — but networks receive
## (cos(theta1), sin(theta1), cos(theta2), sin(theta2), theta1_dot, theta2_dot)
## as inputs (6 inputs) per the standard Gym formulation.
## Action: torque on joint 2 in {-1, 0, +1} — 1 output with discretization.
## Done when tip y > 1.0 (height threshold) or step >= max_steps.
## Fitness = (max_steps - steps_taken) + 10 * (tip_y_at_end / 2) so that
## solutions that swing up faster and higher get more reward.
##
## Constants match OpenAI Gym's Acrobot.
class_name AcrobotEnvironment
extends NeatEnvironment

# Physics constants.
const LINK_MASS_1: float = 1.0
const LINK_MASS_2: float = 1.0
const LINK_LENGTH_1: float = 1.0  # full length of link 1
const LINK_LENGTH_2: float = 1.0  # full length of link 2
const LINK_COM_POS_1: float = 0.5  # center of mass position of link 1 (half-length)
const LINK_COM_POS_2: float = 0.5
const LINK_MOI: float = 1.0  # moment of inertia of each link
const MAX_VEL_1: float = 4.0 * PI
const MAX_VEL_2: float = 9.0 * PI
const G: float = 9.8
const DT: float = 0.2  # seconds per step (with 4 RK4 substeps of 0.05)
const SUBSTEPS: int = 4
const SUB_DT: float = DT / float(SUBSTEPS)
const TORQUE_MAG: float = 1.0
# Tip height threshold for "solved" (1 - link_length_2 - link_length_1 + small margin).
const HEIGHT_THRESHOLD: float = 1.0

# State: theta1, theta2, theta1_dot, theta2_dot.
var _state: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _steps: int = 0
var _done: bool = false
var _max_steps: int = 500
var _max_tip_y: float = -1e9

# Network IO config.
var input_node_ids: Array[int] = []  # 6 inputs
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
			rng.randf_range(-0.1, 0.1),
			rng.randf_range(-0.1, 0.1),
			0.0,
			0.0,
		]
	else:
		_state = [0.0, 0.0, 0.0, 0.0]
	_steps = 0
	_done = false
	_max_tip_y = -1e9

func initial_state() -> Dictionary:
	return _state_to_dict(_state)

func interpret_output(output: Dictionary) -> Dictionary:
	# Discretize: +1 if out > 0.33, -1 if out < -0.33, else 0.
	var v: float = float(output.get(output_node_id, 0.0))
	var a: int = 0
	if v > 0.33:
		a = 1
	elif v < -0.33:
		a = -1
	return {"action": a}

func step(action: Dictionary) -> Dictionary:
	var a: int = int(action.get("action", 0))
	var torque: float = float(a) * TORQUE_MAG
	# RK4 integration over SUBSTEPS substeps.
	var s: Array[float] = _state.duplicate()
	for _i in range(SUBSTEPS):
		s = _rk4_step(s, torque)
	# Clip velocities.
	s[2] = clampf(s[2], -MAX_VEL_1, MAX_VEL_1)
	s[3] = clampf(s[3], -MAX_VEL_2, MAX_VEL_2)
	_state = s
	_steps += 1
	# Compute tip y; if above threshold -> done.
	var tip_y: float = _tip_y(s)
	if tip_y > _max_tip_y:
		_max_tip_y = tip_y
	if tip_y > HEIGHT_THRESHOLD:
		_done = true
	if _steps >= _max_steps:
		_done = true
	return _state_to_dict(_state)

func is_done() -> bool:
	return _done

func current_fitness() -> float:
	# Reward: higher tip + fewer steps to get there.
	# Max tip_y is roughly 2.0 (both links straight up).
	# Range: roughly [-2, 2].
	var tip_component: float = _max_tip_y  # in [-2, 2]
	# Reward also for finishing early.
	var step_component: float = float(_max_steps - _steps) / float(_max_steps)  # in [0, 1]
	return tip_component + step_component

func is_solved() -> bool:
	return _max_tip_y > HEIGHT_THRESHOLD

func state() -> Array[float]:
	return _state

func _tip_y(s: Array[float]) -> float:
	# Both links hang from origin (0,0). theta1 measured from straight down (negative y).
	# When theta1=0, link 1 points down. Tip y = -l1*cos(theta1) - l2*cos(theta1+theta2).
	return -LINK_LENGTH_1 * cos(s[0]) - LINK_LENGTH_2 * cos(s[0] + s[1])

func _state_to_dict(s: Array[float]) -> Dictionary:
	var d: Dictionary = {}
	d[input_node_ids[0]] = cos(s[0])
	d[input_node_ids[1]] = sin(s[0])
	d[input_node_ids[2]] = cos(s[1])
	d[input_node_ids[3]] = sin(s[1])
	d[input_node_ids[4]] = s[2]
	d[input_node_ids[5]] = s[3]
	return d

# One RK4 substep. Returns the new state.
func _rk4_step(s: Array[float], torque: float) -> Array[float]:
	var k1 := _dsdt(s, torque)
	var s2: Array[float] = [
		s[0] + 0.5 * SUB_DT * k1[0],
		s[1] + 0.5 * SUB_DT * k1[1],
		s[2] + 0.5 * SUB_DT * k1[2],
		s[3] + 0.5 * SUB_DT * k1[3],
	]
	var k2 := _dsdt(s2, torque)
	var s3: Array[float] = [
		s[0] + 0.5 * SUB_DT * k2[0],
		s[1] + 0.5 * SUB_DT * k2[1],
		s[2] + 0.5 * SUB_DT * k2[2],
		s[3] + 0.5 * SUB_DT * k2[3],
	]
	var k3 := _dsdt(s3, torque)
	var s4: Array[float] = [
		s[0] + SUB_DT * k3[0],
		s[1] + SUB_DT * k3[1],
		s[2] + SUB_DT * k3[2],
		s[3] + SUB_DT * k3[3],
	]
	var k4 := _dsdt(s4, torque)
	return [
		s[0] + SUB_DT / 6.0 * (k1[0] + 2.0 * k2[0] + 2.0 * k3[0] + k4[0]),
		s[1] + SUB_DT / 6.0 * (k1[1] + 2.0 * k2[1] + 2.0 * k3[1] + k4[1]),
		s[2] + SUB_DT / 6.0 * (k1[2] + 2.0 * k2[2] + 2.0 * k3[2] + k4[2]),
		s[3] + SUB_DT / 6.0 * (k1[3] + 2.0 * k2[3] + 2.0 * k3[3] + k4[3]),
	]

# Returns the derivative (dtheta1, dtheta2, ddtheta1, ddtheta2) given state and torque.
func _dsdt(s: Array[float], torque: float) -> Array[float]:
	var theta1: float = s[0]
	var theta2: float = s[1]
	var dtheta1: float = s[2]
	var dtheta2: float = s[3]
	var m1: float = LINK_MASS_1
	var m2: float = LINK_MASS_2
	var l1: float = LINK_LENGTH_1
	var lc1: float = LINK_COM_POS_1
	var lc2: float = LINK_COM_POS_2
	var I1: float = LINK_MOI
	var I2: float = LINK_MOI
	var d1: float = m1 * lc1 * lc1 + m2 * (l1 * l1 + lc2 * lc2 + 2.0 * l1 * lc2 * cos(theta2)) + I1 + I2
	var d2: float = m2 * (lc2 * lc2 + l1 * lc2 * cos(theta2)) + I2
	var phi2: float = m2 * lc2 * G * cos(theta1 + theta2 - PI / 2.0)
	var phi1: float = -m2 * l1 * lc2 * dtheta2 * dtheta2 * sin(theta2) \
			- 2.0 * m2 * l1 * lc2 * dtheta2 * dtheta1 * sin(theta2) \
			+ (m1 * lc1 + m2 * l1) * G * cos(theta1 - PI / 2.0) + phi2
	var ddtheta2: float = (torque + d2 / d1 * phi1 - m2 * l1 * lc2 * dtheta1 * dtheta1 * sin(theta2) - phi2) / (m2 * lc2 * lc2 + I2 - d2 * d2 / d1)
	var ddtheta1: float = -(d2 * ddtheta2 + phi1) / d1
	return [dtheta1, dtheta2, ddtheta1, ddtheta2]
