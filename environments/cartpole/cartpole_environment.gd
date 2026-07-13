## CartPole environment using real Godot 2D physics.
##
## Scene structure (see cartpole_environment.tscn):
##   Node2D (root, this script)
##     StaticBody2D (ground track)
##       CollisionShape2D
##     RigidBody2D (cart) - moves horizontally on a SliderJoint2D
##       CollisionShape2D
##     RigidBody2D (pole) - pinned to cart via PinJoint2D
##       CollisionShape2D
##     Node (joints)
##       SliderJoint2D (cart confined to x-axis relative to a static anchor)
##       PinJoint2D (cart-pole pivot)
##
## State (network inputs): x, x_dot, theta, theta_dot (4 values).
## Action: discrete 0 (push left) or 1 (push right) - 1 binary output.
## Done when |x| > x_threshold or |theta| > theta_threshold or step >= max_steps.
## Fitness = total steps survived.
##
## The physics bodies are driven via apply_impulse / apply_torque; we read
## their state via get_state() each frame after Godot steps the world.
class_name CartPoleEnvironment
extends NeatPhysicsEnvironment

# Physics constants (kept in sync with the body masses set in the .tscn).
const GRAVITY: float = 9.8
const FORCE_MAG: float = 10.0
const THETA_THRESHOLD: float = 0.20943951  # 12 degrees in radians
const X_THRESHOLD: float = 2.4

@onready var _cart: RigidBody2D = $Cart
@onready var _pole: RigidBody2D = $Pole

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

func reset(p_genome = null, rng: RandomNumberGenerator = null) -> void:
        super.reset(p_genome, rng)
        _steps = 0
        _done = false
        # Reset to exact initial state first so the PinJoint2D constraint is
        # satisfied (no "snap" on the first frame).
        _cart.position = _initial_cart_pos
        _cart.linear_velocity = Vector2.ZERO
        _cart.angular_velocity = 0.0
        _cart.rotation = 0.0
        _pole.position = _initial_pole_pos
        _pole.rotation = _initial_pole_rot
        _pole.linear_velocity = Vector2.ZERO
        _pole.angular_velocity = 0.0
        # Random initial perturbation (OpenAI Gym style). When perturbing the
        # cart position, we must move the pole by the same offset so the
        # PinJoint2D constraint stays satisfied. Otherwise the joint "snaps"
        # on the first physics frame, injecting a large angular impulse that
        # artificially slows the pole's fall.
        if rng != null:
                var cart_dx: float = rng.randf_range(-0.05, 0.05)
                _cart.position.x += cart_dx
                _cart.linear_velocity.x = rng.randf_range(-0.05, 0.05)
                _pole.position.x += cart_dx
                _pole.angular_velocity = rng.randf_range(-0.15, 0.15)

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
        # Use the actual physics step delta. This accounts for both
        # Engine.physics_ticks_per_second and Engine.time_scale (during
        # SceneEvaluator speedup), so the force is correct at any tick rate.
        var dt: float = get_physics_process_delta_time()
        _cart.apply_central_impulse(Vector2(force * dt * _cart.mass, 0.0))

func is_done() -> bool:
        return _done

func _physics_process(_delta: float) -> void:
        if _done:
                return
        _steps += 1
        var x: float = _cart.position.x - _initial_cart_pos.x
        var theta: float = _pole.rotation
        if absf(x) > X_THRESHOLD or absf(theta) > THETA_THRESHOLD:
                _done = true
                # Freeze bodies.
                _cart.linear_velocity = Vector2.ZERO
                _cart.angular_velocity = 0.0
                _pole.linear_velocity = Vector2.ZERO
                _pole.angular_velocity = 0.0
                _cart.sleeping = true
                _pole.sleeping = true
        elif _steps >= _max_steps:
                _done = true

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
