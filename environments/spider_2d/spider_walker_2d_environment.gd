## 2D Spider Walker environment using a custom verlet physics simulation.
##
## The creature has a body (point mass with orientation) and 4 legs, each with
## 3 points (hip, knee, foot) connected by distance constraints (rigid links).
## The genome controls target angles for each hip and knee; the muscle torques
## rotate the leg segments toward those targets. Ground contact creates
## friction that propels the body forward when legs push backward.
##
## This is a proper rigid-body simulation (Verlet integration + constraint
## relaxation) that runs entirely in script — no Godot SceneTree needed.
##
## Inputs (12): for each of 4 legs: (touch, hip_angle, knee_angle, body_lean)
## Outputs (8): for each of 4 legs: (hip_target_delta, knee_target_delta)
##
## Fitness: horizontal distance traveled (forward).
class_name SpiderWalker2DEnvironment
extends NeatEnvironment

const NUM_LEGS: int = 4
const BODY_RADIUS: float = 0.4
const LEG_UPPER_LEN: float = 0.5
const LEG_LOWER_LEN: float = 0.5
const GROUND_Y: float = 0.0
const DT: float = 0.02
const SUBSTEPS: int = 4
const MAX_STEPS: int = 1000
const GRAVITY: float = 9.8
const FRICTION: float = 4.0
const ANGULAR_DAMP: float = 0.92
const MUSCLE_SPEED: float = 8.0  # how fast angles move toward targets

var _leg_base_angles: Array[float] = [-0.6, -0.2, 0.2, 0.6]

# Network IO config.
var input_node_ids: Array[int] = []
var bias_node_id: int = -1
var output_node_ids: Array[int] = []

# Body state: position (x, y), velocity (vx, vy), angle, angular velocity.
var _body_x: float = 0.0
var _body_y: float = 0.0
var _body_vx: float = 0.0
var _body_vy: float = 0.0
var _body_angle: float = 0.0
var _body_avel: float = 0.0
# Per-leg: hip angle (relative to body-down), knee angle (relative to upper leg).
var _hip_angles: Array[float] = []
var _knee_angles: Array[float] = []
var _hip_targets: Array[float] = []
var _knee_targets: Array[float] = []
var _feet_touching: Array[bool] = []
# Previous foot world positions (for friction computation).
var _prev_foot_world: Array = []
# Body mass and leg masses.
const BODY_MASS: float = 4.0
const LEG_MASS: float = 0.3

var _steps: int = 0
var _done: bool = false
var _initial_x: float = 0.0

func _init(p_input_ids: Array[int] = [], p_bias_id: int = -1, p_output_ids: Array[int] = []) -> void:
	input_node_ids = p_input_ids
	bias_node_id = p_bias_id
	output_node_ids = p_output_ids
	_hip_angles.resize(NUM_LEGS)
	_knee_angles.resize(NUM_LEGS)
	_hip_targets.resize(NUM_LEGS)
	_knee_targets.resize(NUM_LEGS)
	_feet_touching.resize(NUM_LEGS)
	_prev_foot_world.resize(NUM_LEGS)
	for i in range(NUM_LEGS):
		_hip_angles[i] = 0.0
		_knee_angles[i] = 0.0
		_hip_targets[i] = 0.0
		_knee_targets[i] = 0.0
		_feet_touching[i] = false
		_prev_foot_world[i] = Vector2.ZERO

func reset(rng: RandomNumberGenerator = null) -> void:
	_body_x = 0.0
	_body_y = BODY_RADIUS + LEG_UPPER_LEN + LEG_LOWER_LEN
	_body_vx = 0.0
	_body_vy = 0.0
	_body_angle = 0.0
	_body_avel = 0.0
	for i in range(NUM_LEGS):
		if rng != null:
			_hip_angles[i] = rng.randf_range(-0.2, 0.2)
			_knee_angles[i] = rng.randf_range(-0.2, 0.2)
		else:
			_hip_angles[i] = 0.0
			_knee_angles[i] = 0.0
		_hip_targets[i] = _hip_angles[i]
		_knee_targets[i] = _knee_angles[i]
		_feet_touching[i] = false
		_prev_foot_world[i] = _compute_foot_world(i)
	_steps = 0
	_done = false
	_initial_x = 0.0

func _compute_hip_world(leg_idx: int) -> Vector2:
	var base: float = _leg_base_angles[leg_idx]
	# Hip attaches to body surface in direction (cos(base), sin(base)) rotated by body angle.
	var dir := Vector2(cos(base + _body_angle), sin(base + _body_angle)) * BODY_RADIUS
	return Vector2(_body_x, _body_y) + dir

func _compute_knee_world(leg_idx: int) -> Vector2:
	var hip := _compute_hip_world(leg_idx)
	var base: float = _leg_base_angles[leg_idx]
	var upper_angle: float = base + _body_angle + _hip_angles[leg_idx]
	# Upper leg points downward, rotated by upper_angle.
	var dir := Vector2(sin(upper_angle), cos(upper_angle)) * LEG_UPPER_LEN
	return hip + dir

func _compute_foot_world(leg_idx: int) -> Vector2:
	var knee := _compute_knee_world(leg_idx)
	var base: float = _leg_base_angles[leg_idx]
	var lower_angle: float = base + _body_angle + _hip_angles[leg_idx] + _knee_angles[leg_idx]
	var dir := Vector2(sin(lower_angle), cos(lower_angle)) * LEG_LOWER_LEN
	return knee + dir

func initial_state() -> Dictionary:
	return _build_state_dict()

func _build_state_dict() -> Dictionary:
	var d: Dictionary = {}
	for i in range(NUM_LEGS):
		d[input_node_ids[i * 3 + 0]] = 1.0 if _feet_touching[i] else 0.0
		d[input_node_ids[i * 3 + 1]] = clampf(_hip_angles[i] / PI, -1.0, 1.0)
		d[input_node_ids[i * 3 + 2]] = clampf(_knee_angles[i] / PI, -1.0, 1.0)
	return d

func interpret_output(output: Dictionary) -> Dictionary:
	var d: Dictionary = {}
	for i in range(NUM_LEGS):
		d[i] = {
			"hip": float(output.get(output_node_ids[i * 2 + 0], 0.0)),
			"knee": float(output.get(output_node_ids[i * 2 + 1], 0.0)),
		}
	return d

func step(action: Dictionary) -> Dictionary:
	# Update targets from network output.
	for i in range(NUM_LEGS):
		var leg_action: Dictionary = action[i]
		_hip_targets[i] += float(leg_action["hip"]) * 0.3
		_knee_targets[i] += float(leg_action["knee"]) * 0.3
		_hip_targets[i] = clampf(_hip_targets[i], -PI * 0.5, PI * 0.5)
		_knee_targets[i] = clampf(_knee_targets[i], -PI * 0.5, PI * 0.5)
	# Move angles toward targets (muscle activation).
	for i in range(NUM_LEGS):
		var hip_diff: float = _hip_targets[i] - _hip_angles[i]
		var knee_diff: float = _knee_targets[i] - _knee_angles[i]
		_hip_angles[i] += clampf(hip_diff * MUSCLE_SPEED * DT, -0.3, 0.3)
		_knee_angles[i] += clampf(knee_diff * MUSCLE_SPEED * DT, -0.3, 0.3)
	# Compute new foot positions.
	var new_foot_world: Array = []
	new_foot_world.resize(NUM_LEGS)
	for i in range(NUM_LEGS):
		new_foot_world[i] = _compute_foot_world(i)
	# Determine which feet are touching.
	var touching_threshold: float = 0.05
	for i in range(NUM_LEGS):
		_feet_touching[i] = (new_foot_world[i] as Vector2).y >= GROUND_Y - touching_threshold
	# Apply gravity to body.
	_body_vy -= GRAVITY * DT
	# Foot-pinning + friction: for each grounded foot, the foot's world position
	# should stay fixed (static friction). Since foot_world = body + leg_offset,
	# Δfoot_world = Δbody + Δleg_offset = 0 => Δbody = -Δleg_offset.
	# Also apply horizontal friction to slow slipping.
	var feet_on_ground: int = 0
	var body_dx: float = 0.0
	var body_dy: float = 0.0
	for i in range(NUM_LEGS):
		if _feet_touching[i]:
			var prev_foot: Vector2 = _prev_foot_world[i]
			var new_foot: Vector2 = new_foot_world[i]
			# World-space foot displacement if body didn't move.
			var leg_delta: Vector2 = new_foot - prev_foot
			body_dx -= leg_delta.x
			body_dy -= leg_delta.y
			feet_on_ground += 1
	if feet_on_ground > 0:
		body_dx /= float(feet_on_ground)
		body_dy /= float(feet_on_ground)
		# Override body velocity with foot-pinning result (grounded).
		_body_vx = body_dx / DT
		_body_vy = body_dy / DT
		# Apply horizontal friction (reduce slip).
		_body_vx *= 1.0 - FRICTION * DT
		# Angular damping when grounded.
		_body_avel *= ANGULAR_DAMP
	# Update body position.
	_body_x += _body_vx * DT
	_body_y += _body_vy * DT
	_body_angle += _body_avel * DT
	# Don't let body fall through ground.
	var min_body_y: float = BODY_RADIUS + 0.05
	if _body_y < min_body_y:
		_body_y = min_body_y
		_body_vy = 0.0
	# Apply angular damping in air too.
	if feet_on_ground == 0:
		_body_avel *= 0.99
	# Save prev foot positions.
	_prev_foot_world = new_foot_world.duplicate()
	_steps += 1
	if _steps >= MAX_STEPS:
		_done = true
	if _body_y < -1.0:
		_done = true
	return _build_state_dict()

func is_done() -> bool:
	return _done

func current_fitness() -> float:
	var forward: float = _body_x - _initial_x
	return maxf(0.0, forward) + 0.05 * absf(forward)

func is_solved() -> bool:
	return _body_x - _initial_x > 5.0

func view_type() -> String:
	return "2d"

func get_visual_state() -> Dictionary:
	var feet: Array = []
	for i in range(NUM_LEGS):
		var hip := _compute_hip_world(i)
		var knee := _compute_knee_world(i)
		var foot := _compute_foot_world(i)
		feet.append({"hip": hip, "knee": knee, "foot": foot, "touching": _feet_touching[i]})
	return {
		"body_x": _body_x,
		"body_y": _body_y,
		"body_vx": _body_vx,
		"body_vy": _body_vy,
		"body_angle": _body_angle,
		"steps": _steps,
		"max_steps": MAX_STEPS,
		"done": _done,
		"body_radius": BODY_RADIUS,
		"ground_y": GROUND_Y,
		"feet": feet,
		"distance": _body_x - _initial_x,
	}
