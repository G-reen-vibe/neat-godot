## 3D Spider Walker environment using REAL Godot 3D physics.
##
## Scene structure (see spider_walker_3d_environment.tscn):
##   Node3D (root, this script)
##     StaticBody3D (ground)
##     RigidBody3D (body) - the main torso
##     For each of 4 legs:
##       RigidBody3D (upper leg) - attached to body via ConeTwistJoint3D (hip)
##       RigidBody3D (lower leg) - attached to upper leg via HingeJoint3D (knee)
##       Area3D (foot sensor) - on the lower leg's tip
##
## Inputs (16): for each of 4 legs: (touch, hip_yaw, hip_pitch, knee_angle)
## Outputs (12): for each of 4 legs: (hip_yaw_delta, hip_pitch_delta, knee_delta)
##
## Fitness: horizontal distance from start (forward in +x).
class_name SpiderWalker3DEnvironment
extends NeatPhysicsEnvironment3D

const NUM_LEGS: int = 4
const BODY_RADIUS: float = 0.4
const LEG_UPPER_LEN: float = 0.5
const LEG_LOWER_LEN: float = 0.5
const GROUND_Y: float = 0.0
const MAX_STEPS: int = 1000
const MUSCLE_SPEED: float = 8.0
const MUSCLE_TORQUE: float = 5.0

# Leg base yaw angles (radians around Y axis).
var _leg_base_yaw: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]

var _hip_yaw_target: Array[float] = []
var _hip_pitch_target: Array[float] = []
var _knee_target: Array[float] = []
var _feet_touching: Array = []

var _body: RigidBody3D
var _upper_legs: Array = []  # Array[RigidBody3D]
var _lower_legs: Array = []  # Array[RigidBody3D]
var _foot_areas: Array = []  # Array[Area3D]
var _hip_yaw: Array[float] = []
var _hip_pitch: Array[float] = []
var _knee: Array[float] = []

var _steps: int = 0
var _done: bool = false
var _initial_body_pos: Vector3

var _initial_body_pos_cached: Vector3
var _initial_body_rot_cached: Vector3
var _initial_upper_pos: Array = []
var _initial_upper_rot: Array = []
var _initial_lower_pos: Array = []
var _initial_lower_rot: Array = []

func _ready() -> void:
	_body = $Body
	for i in range(NUM_LEGS):
		var upper_name: String = "UpperLeg%d" % i
		var lower_name: String = "LowerLeg%d" % i
		var upper_node = get_node_or_null(upper_name)
		var lower_node = get_node_or_null(lower_name)
		var foot_node = null
		if lower_node != null:
			foot_node = lower_node.get_node_or_null("FootArea")
		if upper_node == null or lower_node == null or foot_node == null:
			push_warning("Spider3D: missing node at index %d" % i)
			_upper_legs.append(null)
			_lower_legs.append(null)
			_foot_areas.append(null)
		else:
			_upper_legs.append(upper_node)
			_lower_legs.append(lower_node)
			_foot_areas.append(foot_node)
		_feet_touching.append(false)
		_hip_yaw.append(0.0)
		_hip_pitch.append(0.0)
		_knee.append(0.0)
		_hip_yaw_target.append(0.0)
		_hip_pitch_target.append(0.0)
		_knee_target.append(0.0)
		_initial_upper_pos.append(_upper_legs[i].position if _upper_legs[i] != null else Vector3.ZERO)
		_initial_upper_rot.append(_upper_legs[i].rotation if _upper_legs[i] != null else Vector3.ZERO)
		_initial_lower_pos.append(_lower_legs[i].position if _lower_legs[i] != null else Vector3.ZERO)
		_initial_lower_rot.append(_lower_legs[i].rotation if _lower_legs[i] != null else Vector3.ZERO)
	_initial_body_pos_cached = _body.position
	_initial_body_rot_cached = _body.rotation
	_initial_body_pos = _initial_body_pos_cached

func set_max_steps(_p: int) -> void:
	pass

func reset(p_genome = null, rng: RandomNumberGenerator = null) -> void:
	super.reset(p_genome, rng)
	_steps = 0
	_done = false
	_body.position = _initial_body_pos_cached
	_body.rotation = _initial_body_rot_cached
	_body.linear_velocity = Vector3.ZERO
	_body.angular_velocity = Vector3.ZERO
	for i in range(NUM_LEGS):
		_upper_legs[i].position = _initial_upper_pos[i]
		_upper_legs[i].rotation = _initial_upper_rot[i]
		_upper_legs[i].linear_velocity = Vector3.ZERO
		_upper_legs[i].angular_velocity = Vector3.ZERO
		_lower_legs[i].position = _initial_lower_pos[i]
		_lower_legs[i].rotation = _initial_lower_rot[i]
		_lower_legs[i].linear_velocity = Vector3.ZERO
		_lower_legs[i].angular_velocity = Vector3.ZERO
		_hip_yaw[i] = 0.0
		_hip_pitch[i] = 0.0
		_knee[i] = 0.0
		_hip_yaw_target[i] = 0.0
		_hip_pitch_target[i] = 0.0
		_knee_target[i] = 0.0
		_feet_touching[i] = false
	_initial_body_pos = _body.position

func get_state() -> Dictionary:
	var d: Dictionary = {}
	for i in range(NUM_LEGS):
		d[input_node_ids[i * 4 + 0]] = 1.0 if _feet_touching[i] else 0.0
		d[input_node_ids[i * 4 + 1]] = clampf(_hip_yaw[i] / PI, -1.0, 1.0)
		d[input_node_ids[i * 4 + 2]] = clampf(_hip_pitch[i] / PI, -1.0, 1.0)
		d[input_node_ids[i * 4 + 3]] = clampf(_knee[i] / PI, -1.0, 1.0)
	return d

func interpret_output(output: Dictionary) -> Dictionary:
	var d: Dictionary = {}
	for i in range(NUM_LEGS):
		d[i] = {
			"yaw": float(output.get(output_node_ids[i * 3 + 0], 0.0)),
			"pitch": float(output.get(output_node_ids[i * 3 + 1], 0.0)),
			"knee": float(output.get(output_node_ids[i * 3 + 2], 0.0)),
		}
	return d

func apply_action(action: Dictionary) -> void:
	if _done:
		return
	for i in range(NUM_LEGS):
		var leg_action: Dictionary = action[i]
		_hip_yaw_target[i] += float(leg_action["yaw"]) * 0.3
		_hip_pitch_target[i] += float(leg_action["pitch"]) * 0.3
		_knee_target[i] += float(leg_action["knee"]) * 0.3
		_hip_yaw_target[i] = clampf(_hip_yaw_target[i], -PI * 0.5, PI * 0.5)
		_hip_pitch_target[i] = clampf(_hip_pitch_target[i], -PI * 0.5, PI * 0.5)
		_knee_target[i] = clampf(_knee_target[i], -PI * 0.5, PI * 0.5)
	# Apply torques. We treat each joint as a hinge with a target angle.
	for i in range(NUM_LEGS):
		var upper: RigidBody3D = _upper_legs[i]
		var lower: RigidBody3D = _lower_legs[i]
		# Yaw torque on upper leg (around Y axis).
		var yaw_diff: float = _hip_yaw_target[i] - _hip_yaw[i]
		var yaw_torque: float = clampf(yaw_diff * MUSCLE_SPEED, -1.0, 1.0) * MUSCLE_TORQUE
		upper.apply_torque(Vector3(0, yaw_torque, 0))
		# Pitch torque on upper leg (around X axis).
		var pitch_diff: float = _hip_pitch_target[i] - _hip_pitch[i]
		var pitch_torque: float = clampf(pitch_diff * MUSCLE_SPEED, -1.0, 1.0) * MUSCLE_TORQUE
		upper.apply_torque(Vector3(pitch_torque, 0, 0))
		# Knee torque on lower leg.
		var knee_diff: float = _knee_target[i] - _knee[i]
		var knee_torque: float = clampf(knee_diff * MUSCLE_SPEED, -1.0, 1.0) * MUSCLE_TORQUE
		lower.apply_torque(Vector3(knee_torque, 0, 0))

func _physics_process(_delta: float) -> void:
	if _done:
		return
	_steps += 1
	# Update foot contact sensors.
	for i in range(NUM_LEGS):
		_feet_touching[i] = false
		if _foot_areas[i] == null:
			continue
		for body in _foot_areas[i].get_overlapping_bodies():
			if body is StaticBody3D:
				_feet_touching[i] = true
				break
	# Read joint angles from body rotations (relative to parent).
	for i in range(NUM_LEGS):
		if _upper_legs[i] == null or _lower_legs[i] == null:
			continue
		# Upper leg yaw/pitch relative to body.
		var upper_rot: Vector3 = _upper_legs[i].rotation - _body.rotation
		_hip_yaw[i] = upper_rot.y
		_hip_pitch[i] = upper_rot.x
		# Lower leg relative to upper leg.
		var lower_rot: Vector3 = _lower_legs[i].rotation - _upper_legs[i].rotation
		_knee[i] = lower_rot.x
	if _steps >= MAX_STEPS:
		_done = true
	if _body.position.y < -2.0:
		_done = true

func is_done() -> bool:
	return _done

func current_fitness() -> float:
	var d: Vector3 = _body.position - _initial_body_pos
	var horiz: float = sqrt(d.x * d.x + d.z * d.z)
	var forward: float = maxf(0.0, d.x)
	return forward + 0.05 * horiz

func is_solved() -> bool:
	var d: Vector3 = _body.position - _initial_body_pos
	return sqrt(d.x * d.x + d.z * d.z) > 5.0

func view_type() -> String:
	return "3d"

func get_visual_state() -> Dictionary:
	var feet: Array = []
	for i in range(NUM_LEGS):
		feet.append({
			"hip": _upper_legs[i].position if _upper_legs[i] != null else Vector3.ZERO,
			"knee": _lower_legs[i].position if _lower_legs[i] != null else Vector3.ZERO,
			"foot": _lower_legs[i].position + Vector3(0, -LEG_LOWER_LEN * 0.5, 0) if _lower_legs[i] != null else Vector3.ZERO,
			"touching": _feet_touching[i],
		})
	return {
		"body_pos": _body.position,
		"body_vel": _body.linear_velocity,
		"steps": _steps,
		"max_steps": MAX_STEPS,
		"done": _done,
		"body_radius": BODY_RADIUS,
		"ground_y": GROUND_Y,
		"feet": feet,
		"distance": current_fitness(),
		"initial_pos": _initial_body_pos,
	}
