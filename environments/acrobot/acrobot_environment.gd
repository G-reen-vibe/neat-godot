## Acrobot environment using real Godot 2D physics.
##
## Scene structure (see acrobot_environment.tscn):
##   Node2D (root, this script)
##     StaticBody2D (anchor point at origin)
##     TeleportBody2D (Link1) - first link, hangs from anchor
##       CollisionShape2D (capsule, length 1.0)
##     TeleportBody2D (Link2) - second link, hangs from Link1's tip
##       CollisionShape2D (capsule, length 1.0)
##     PinJoint2D (anchor: between StaticBody2D and Link1)
##     PinJoint2D (joint1: between Link1 and Link2)
##
## State (network inputs): cos(theta1), sin(theta1), cos(theta2), sin(theta2),
## theta1_dot, theta2_dot (6 values).
## Action: torque on joint 2 in {-1, 0, +1} - 1 output with discretization.
## Done when tip y > 1.0 (height threshold) or step >= max_steps.
## Fitness: (max_steps - steps) + 10 * (max_tip_y / 2) so faster + higher = better.
##
## All RigidBody2D state resets go through [method TeleportBody2D.request_teleport].
class_name AcrobotEnvironment
extends NeatPhysicsEnvironment

const LINK_LENGTH_1: float = 1.0
const LINK_LENGTH_2: float = 1.0
const LINK_MASS: float = 1.0
const HEIGHT_THRESHOLD: float = 1.0
const TORQUE_MAG: float = 1.0
# Acrobot uses 4 substeps per env step (DT=0.2). In real physics we just step
# multiple physics frames per env step.
const SUBSTEPS_PER_ACTION: int = 4
const MAX_VEL_1: float = 4.0 * PI
const MAX_VEL_2: float = 9.0 * PI

@onready var _link1: TeleportBody2D = $Link1
@onready var _link2: TeleportBody2D = $Link2

var _steps: int = 0
var _done: bool = false
var _max_steps: int = 500
var _max_tip_y: float = -1e9

var _initial_link1_pos: Vector2
var _initial_link1_rot: float
var _initial_link2_pos: Vector2
var _initial_link2_rot: float

func _ready() -> void:
	_initial_link1_pos = _link1.position
	_initial_link1_rot = _link1.rotation
	_initial_link2_pos = _link2.position
	_initial_link2_rot = _link2.rotation

func set_max_steps(p_max_steps: int) -> void:
	_max_steps = p_max_steps

## Freeze/unfreeze the link RigidBody2Ds. See CartPoleEnvironment.set_bodies_frozen
## for the full rationale.
func set_bodies_frozen(frozen: bool) -> void:
	_link1.freeze = frozen
	_link2.freeze = frozen

func reset(p_genome = null, rng: RandomNumberGenerator = null) -> void:
	super.reset(p_genome, rng)
	_steps = 0
	_done = false
	_max_tip_y = -1e9
	var link1_rot: float = _initial_link1_rot
	var link2_rot: float = _initial_link2_rot
	if rng != null:
		link1_rot = rng.randf_range(-0.1, 0.1)
		link2_rot = rng.randf_range(-0.1, 0.1)
	# Queue teleports for reliable reset.
	_link1.request_teleport(Transform2D(link1_rot, _initial_link1_pos), Vector2.ZERO, 0.0)
	_link2.request_teleport(Transform2D(link2_rot, _initial_link2_pos), Vector2.ZERO, 0.0)

func get_state() -> Dictionary:
	var theta1: float = _link1.rotation
	var theta2: float = _link2.rotation - _link1.rotation
	var d: Dictionary = {}
	d[input_node_ids[0]] = cos(theta1)
	d[input_node_ids[1]] = sin(theta1)
	d[input_node_ids[2]] = cos(theta2)
	d[input_node_ids[3]] = sin(theta2)
	d[input_node_ids[4]] = _link1.angular_velocity
	d[input_node_ids[5]] = _link2.angular_velocity - _link1.angular_velocity
	return d

func interpret_output(output: Dictionary) -> Dictionary:
	var v: float = float(output.get(output_node_id, 0.0))
	var a: int = 0
	if v > 0.33:
		a = 1
	elif v < -0.33:
		a = -1
	return {"action": a}

func apply_action(action: Dictionary) -> void:
	if _done:
		return
	var a: int = int(action.get("action", 0))
	var torque: float = float(a) * TORQUE_MAG
	# Apply torque to link2 (and reaction to link1).
	# In Godot 2D, apply_torque_impulse adds an instantaneous angular impulse.
	# We use apply_torque for continuous torque (applied over next physics step).
	_link2.apply_torque(torque * SUBSTEPS_PER_ACTION)
	_link1.apply_torque(-torque * SUBSTEPS_PER_ACTION)

func is_done() -> bool:
	return _done

## Step the env's game logic. Called from _physics_process.
func step_env() -> void:
	if _done:
		return
	_steps += 1
	# Clip angular velocities.
	_link1.angular_velocity = clampf(_link1.angular_velocity, -MAX_VEL_1, MAX_VEL_1)
	_link2.angular_velocity = clampf(_link2.angular_velocity, -MAX_VEL_2, MAX_VEL_2)
	var theta1: float = _link1.rotation
	var theta2: float = _link2.rotation - _link1.rotation
	var tip_y_world: float = position.y + cos(theta1) * LINK_LENGTH_1 + cos(theta1 + theta2) * LINK_LENGTH_2
	var height_above: float = position.y - tip_y_world
	if height_above > _max_tip_y:
		_max_tip_y = height_above
	if height_above > HEIGHT_THRESHOLD:
		_done = true
	elif _steps >= _max_steps:
		_done = true

func _physics_process(_delta: float) -> void:
	step_env()

func current_fitness() -> float:
	var step_component: float = float(_max_steps - _steps) / float(_max_steps)
	return _max_tip_y + step_component

func is_solved() -> bool:
	return _max_tip_y > HEIGHT_THRESHOLD

func state() -> Array[float]:
	var theta1: float = _link1.rotation
	var theta2: float = _link2.rotation - _link1.rotation
	return [theta1, theta2, _link1.angular_velocity, _link2.angular_velocity - _link1.angular_velocity]

func get_visual_state() -> Dictionary:
	var theta1: float = _link1.rotation
	var theta2: float = _link2.rotation - _link1.rotation
	var tip_y_world: float = position.y + cos(theta1) * LINK_LENGTH_1 + cos(theta1 + theta2) * LINK_LENGTH_2
	return {
		"theta1": theta1,
		"theta2": theta2,
		"theta1_dot": _link1.angular_velocity,
		"theta2_dot": _link2.angular_velocity - _link1.angular_velocity,
		"steps": _steps,
		"max_steps": _max_steps,
		"done": _done,
		"tip_y": position.y - tip_y_world,
		"max_tip_y": _max_tip_y,
		"height_threshold": HEIGHT_THRESHOLD,
		"link_length_1": LINK_LENGTH_1,
		"link_length_2": LINK_LENGTH_2,
		"link1_pos": _link1.position,
		"link2_pos": _link2.position,
		"link1_rot": _link1.rotation,
		"link2_rot": _link2.rotation,
	}
