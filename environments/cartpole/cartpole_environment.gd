## CartPole environment using real Godot 2D physics.
##
## Scene structure (see cartpole_environment.tscn):
##   Node2D (root, this script)
##     TeleportBody2D (cart) - moves horizontally, axis-locked
##       CollisionShape2D
##     TeleportBody2D (pole) - pinned to cart via PinJoint2D
##       CollisionShape2D
##     PinJoint2D (cart-pole pivot)
##
## State (network inputs): x, x_dot, theta, theta_dot (4 values).
## Action: discrete 0 (push left) or 1 (push right) - 1 binary output.
## Done when |x| > x_threshold or |theta| > theta_threshold or step >= max_steps.
## Fitness = total steps survived.
##
## All RigidBody2D state resets go through [method TeleportBody2D.request_teleport],
## which is applied inside [method _integrate_forces] for reliability. Direct
## [member RigidBody2D.position] / [member RigidBody2D.linear_velocity] assignment
## is NOT used because the physics server may overwrite it.
class_name CartPoleEnvironment
extends NeatPhysicsEnvironment

# Physics constants (kept in sync with the body masses set in the .tscn).
const GRAVITY: float = 9.8
const FORCE_MAG: float = 10.0
const THETA_THRESHOLD: float = 0.20943951  # 12 degrees in radians
const X_THRESHOLD: float = 2.4

@onready var _cart: TeleportBody2D = $Cart
@onready var _pole: TeleportBody2D = $Pole

var _steps: int = 0
var _done: bool = false
var _max_steps: int = 500

# Cached initial state for reset.
var _initial_cart_pos: Vector2
var _initial_pole_pos: Vector2
var _initial_pole_rot: float

func _ready() -> void:
	# Cache initial positions for reset.
	_initial_cart_pos = _cart.position
	_initial_pole_pos = _pole.position
	_initial_pole_rot = _pole.rotation

func set_max_steps(p_max_steps: int) -> void:
	_max_steps = p_max_steps

## Freeze/unfreeze the cart and pole RigidBody2Ds. When frozen, the bodies
## won't move even when the physics server steps the world. This is used by the
## RunScreen to prevent the live env from being affected by the
## SceneEvaluator's physics_frame awaits during training.
##
## NOTE: When frozen, [method request_teleport] still works (the teleport is
## applied inside [method _integrate_forces], which runs even on frozen bodies).
## So [method reset] can be called on a frozen env and the bodies will snap to
## the initial pose reliably.
func set_bodies_frozen(frozen: bool) -> void:
	_cart.freeze = frozen
	_pole.freeze = frozen

func reset(p_genome = null, rng: RandomNumberGenerator = null) -> void:
	super.reset(p_genome, rng)
	_steps = 0
	_done = false
	# Build target transforms. Start from the cached initial pose.
	var cart_pos: Vector2 = _initial_cart_pos
	var pole_pos: Vector2 = _initial_pole_pos
	var cart_lin_vel: Vector2 = Vector2.ZERO
	var pole_ang_vel: float = 0.0
	# Random initial perturbation (OpenAI Gym style). When perturbing the
	# cart position, we move the pole by the same offset so the PinJoint2D
	# constraint stays satisfied.
	if rng != null:
		var cart_dx: float = rng.randf_range(-0.05, 0.05)
		cart_pos.x += cart_dx
		pole_pos.x += cart_dx
		cart_lin_vel.x = rng.randf_range(-0.05, 0.05)
		pole_ang_vel = rng.randf_range(-0.15, 0.15)
	# Queue teleports. These take effect on the next physics step (inside
	# _integrate_forces), so the physics server's internal state is updated
	# authoritatively — no "snap back" to a cached transform.
	_cart.request_teleport(Transform2D(0.0, cart_pos), cart_lin_vel, 0.0)
	_pole.request_teleport(Transform2D(_initial_pole_rot, pole_pos), Vector2.ZERO, pole_ang_vel)

func get_state() -> Dictionary:
	var x: float = _cart.position.x - _initial_cart_pos.x
	var x_dot: float = _cart.linear_velocity.x
	var theta: float = _pole.rotation
	var theta_dot: float = _pole.angular_velocity
	var d: Dictionary = {}
	d[input_node_ids[0]] = x
	d[input_node_ids[1]] = x_dot
	d[input_node_ids[2]] = theta
	d[input_node_ids[3]] = theta_dot
	return d

func interpret_output(output: Dictionary) -> Dictionary:
	var v: float = float(output.get(output_node_id, 0.0))
	return {"action": 1 if v > 0.0 else 0}

func apply_action(action: Dictionary) -> void:
	if _done:
		return
	var a: int = int(action.get("action", 0))
	var force: float = FORCE_MAG if a == 1 else -FORCE_MAG
	# Fixed dt = 1/60. The physics tick rate is always 60 Hz (no speedup).
	# Using get_physics_process_delta_time() would return stale values when
	# called from the SceneEvaluator's coroutine (which awaits physics frames
	# but isn't inside _physics_process).
	var dt: float = 1.0 / 60.0
	_cart.apply_central_impulse(Vector2(force * dt * _cart.mass, 0.0))

func is_done() -> bool:
	return _done

## Step the env's game logic (increment steps, check done conditions). This is
## called from _physics_process (for training envs). The live env is driven by
## its own _physics_process too (re-enabled when paused), so this method is the
## single source of truth for game logic.
func step_env() -> void:
	if _done:
		return
	_steps += 1
	var x: float = _cart.position.x - _initial_cart_pos.x
	var theta: float = _pole.rotation
	if absf(x) > X_THRESHOLD or absf(theta) > THETA_THRESHOLD:
		_done = true
		# Freeze velocities via teleport (reliable).
		_cart.request_teleport(Transform2D(_cart.rotation, _cart.position), Vector2.ZERO, 0.0)
		_pole.request_teleport(Transform2D(_pole.rotation, _pole.position), Vector2.ZERO, 0.0)
	elif _steps >= _max_steps:
		_done = true

func _physics_process(_delta: float) -> void:
	step_env()

func current_fitness() -> float:
	return float(_steps)

func is_solved() -> bool:
	return _steps >= _max_steps

func state() -> Array[float]:
	return [
		_cart.position.x - _initial_cart_pos.x,
		_cart.linear_velocity.x,
		_pole.rotation,
		_pole.angular_velocity,
	]

func get_visual_state() -> Dictionary:
	return {
		"x": _cart.position.x - _initial_cart_pos.x,
		"x_dot": _cart.linear_velocity.x,
		"theta": _pole.rotation,
		"theta_dot": _pole.angular_velocity,
		"steps": _steps,
		"max_steps": _max_steps,
		"done": _done,
		"x_threshold": X_THRESHOLD,
		"theta_threshold": THETA_THRESHOLD,
		"track_half_length": X_THRESHOLD,
		"pole_half_length": 0.5,
		"cart_pos": _cart.position,
		"pole_pos": _pole.position,
	}
