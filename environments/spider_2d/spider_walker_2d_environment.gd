## 2D Spider Walker environment using REAL Godot 2D physics.
##
## Scene structure (see spider_walker_2d_environment.tscn):
##   Node2D (root, this script)
##     StaticBody2D (ground)
##     RigidBody2D (body) - the main torso
##     For each of 4 legs:
##       RigidBody2D (upper leg) - pinned to body via PinJoint2D
##       RigidBody2D (lower leg) - pinned to upper leg via PinJoint2D
##       Area2D (foot sensor) - on the lower leg's tip, detects ground contact
##
## The genome controls target angles for each hip and knee; we apply torque
## to push the joints toward those targets. Real friction + ground contact
## propel the body forward.
##
## Inputs (12): for each of 4 legs: (touch, hip_angle, knee_angle)
## Outputs (8): for each of 4 legs: (hip_target_delta, knee_target_delta)
##
## Fitness: horizontal distance traveled (forward).
class_name SpiderWalker2DEnvironment
extends NeatPhysicsEnvironment

const NUM_LEGS: int = 4
const BODY_RADIUS: float = 0.4
const LEG_UPPER_LEN: float = 0.5
const LEG_LOWER_LEN: float = 0.5
const GROUND_Y: float = 0.0
const MAX_STEPS: int = 1000
const MUSCLE_SPEED: float = 8.0
const MUSCLE_TORQUE: float = 50.0

# Leg base angles (radians from body-down direction).
var _leg_base_angles: Array[float] = [-0.6, -0.2, 0.2, 0.6]

# Per-leg joint state.
var _hip_targets: Array[float] = []
var _knee_targets: Array[float] = []

# Body and leg nodes (populated in _ready).
var _body: RigidBody2D
var _upper_legs: Array = []  # Array[RigidBody2D]
var _lower_legs: Array = []  # Array[RigidBody2D]
var _foot_areas: Array = []  # Array[Area2D]
var _feet_touching: Array = []  # Array[bool]

var _steps: int = 0
var _done: bool = false
var _initial_body_x: float = 0.0

# Cached initial transforms for reset.
var _initial_body_pos: Vector2
var _initial_body_rot: float
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
                        push_warning("Spider2D: missing node at index %d (upper=%s lower=%s foot=%s)" % [i, upper_name, lower_name, str(foot_node)])
                        _upper_legs.append(null)
                        _lower_legs.append(null)
                        _foot_areas.append(null)
                else:
                        _upper_legs.append(upper_node)
                        _lower_legs.append(lower_node)
                        _foot_areas.append(foot_node)
                _feet_touching.append(false)
                _initial_upper_pos.append(_upper_legs[i].position if _upper_legs[i] != null else Vector2.ZERO)
                _initial_upper_rot.append(_upper_legs[i].rotation if _upper_legs[i] != null else 0.0)
                _initial_lower_pos.append(_lower_legs[i].position if _lower_legs[i] != null else Vector2.ZERO)
                _initial_lower_rot.append(_lower_legs[i].rotation if _lower_legs[i] != null else 0.0)
        _initial_body_pos = _body.position
        _initial_body_rot = _body.rotation
        _hip_targets.resize(NUM_LEGS)
        _knee_targets.resize(NUM_LEGS)

func set_max_steps(_p: int) -> void:
        # Spider uses its own MAX_STEPS; ignore.
        pass

func reset(p_genome = null, rng: RandomNumberGenerator = null) -> void:
        super.reset(p_genome, rng)
        _steps = 0
        _done = false
        _initial_body_x = _initial_body_pos.x
        # Reset body.
        _body.position = _initial_body_pos
        _body.rotation = _initial_body_rot
        _body.linear_velocity = Vector2.ZERO
        _body.angular_velocity = 0.0
        # Reset legs.
        for i in range(NUM_LEGS):
                _upper_legs[i].position = _initial_upper_pos[i]
                _upper_legs[i].rotation = _initial_upper_rot[i]
                _upper_legs[i].linear_velocity = Vector2.ZERO
                _upper_legs[i].angular_velocity = 0.0
                _lower_legs[i].position = _initial_lower_pos[i]
                _lower_legs[i].rotation = _initial_lower_rot[i]
                _lower_legs[i].linear_velocity = Vector2.ZERO
                _lower_legs[i].angular_velocity = 0.0
                _hip_targets[i] = 0.0
                _knee_targets[i] = 0.0
                _feet_touching[i] = false

func get_state() -> Dictionary:
        var d: Dictionary = {}
        for i in range(NUM_LEGS):
                # Touch sensor.
                d[input_node_ids[i * 3 + 0]] = 1.0 if _feet_touching[i] else 0.0
                # Hip angle (relative to body).
                var hip_angle: float = _upper_legs[i].rotation - _body.rotation
                d[input_node_ids[i * 3 + 1]] = clampf(hip_angle / PI, -1.0, 1.0)
                # Knee angle (relative to upper leg).
                var knee_angle: float = _lower_legs[i].rotation - _upper_legs[i].rotation
                d[input_node_ids[i * 3 + 2]] = clampf(knee_angle / PI, -1.0, 1.0)
        return d

func interpret_output(output: Dictionary) -> Dictionary:
        var d: Dictionary = {}
        for i in range(NUM_LEGS):
                d[i] = {
                        "hip": float(output.get(output_node_ids[i * 2 + 0], 0.0)),
                        "knee": float(output.get(output_node_ids[i * 2 + 1], 0.0)),
                }
        return d

func apply_action(action: Dictionary) -> void:
        if _done:
                return
        for i in range(NUM_LEGS):
                var leg_action: Dictionary = action[i]
                _hip_targets[i] += float(leg_action["hip"]) * 0.3
                _knee_targets[i] += float(leg_action["knee"]) * 0.3
                _hip_targets[i] = clampf(_hip_targets[i], -PI * 0.5, PI * 0.5)
                _knee_targets[i] = clampf(_knee_targets[i], -PI * 0.5, PI * 0.5)
        # Apply torques to push joints toward targets.
        var dt: float = 1.0 / 60.0  # approximate physics step
        for i in range(NUM_LEGS):
                var upper: RigidBody2D = _upper_legs[i]
                var lower: RigidBody2D = _lower_legs[i]
                # Hip: rotate upper leg relative to body.
                var hip_diff: float = _hip_targets[i] - (upper.rotation - _body.rotation)
                var hip_torque: float = clampf(hip_diff * MUSCLE_SPEED, -1.0, 1.0) * MUSCLE_TORQUE
                upper.apply_torque(hip_torque)
                _body.apply_torque(-hip_torque * 0.5)  # reaction on body (damped)
                # Knee: rotate lower leg relative to upper leg.
                var knee_diff: float = _knee_targets[i] - (lower.rotation - upper.rotation)
                var knee_torque: float = clampf(knee_diff * MUSCLE_SPEED, -1.0, 1.0) * MUSCLE_TORQUE
                lower.apply_torque(knee_torque)
                upper.apply_torque(-knee_torque * 0.5)

func _physics_process(_delta: float) -> void:
        if _done:
                return
        _steps += 1
        # Update foot contact sensors.
        for i in range(NUM_LEGS):
                _feet_touching[i] = false
                for body in _foot_areas[i].get_overlapping_bodies():
                        if body is StaticBody2D:
                                _feet_touching[i] = true
                                break
        # Done check.
        if _steps >= MAX_STEPS:
                _done = true
        if _body.position.y < -2.0:
                _done = true

func is_done() -> bool:
        return _done

func current_fitness() -> float:
        var forward: float = _body.position.x - _initial_body_x
        return maxf(0.0, forward) + 0.05 * absf(forward)

func is_solved() -> bool:
        return _body.position.x - _initial_body_x > 5.0

func view_type() -> String:
        return "2d"

func get_visual_state() -> Dictionary:
        var feet: Array = []
        for i in range(NUM_LEGS):
                var upper: RigidBody2D = _upper_legs[i]
                var lower: RigidBody2D = _lower_legs[i]
                feet.append({
                        "hip": _body.position + Vector2(cos(_leg_base_angles[i] + _body.rotation), sin(_leg_base_angles[i] + _body.rotation)) * BODY_RADIUS,
                        "knee": upper.position,
                        "foot": lower.position + Vector2(0, LEG_LOWER_LEN * 0.5).rotated(lower.rotation),
                        "touching": _feet_touching[i],
                })
        return {
                "body_x": _body.position.x,
                "body_y": _body.position.y,
                "body_vx": _body.linear_velocity.x,
                "body_vy": _body.linear_velocity.y,
                "body_angle": _body.rotation,
                "steps": _steps,
                "max_steps": MAX_STEPS,
                "done": _done,
                "body_radius": BODY_RADIUS,
                "ground_y": GROUND_Y,
                "feet": feet,
                "distance": _body.position.x - _initial_body_x,
        }
