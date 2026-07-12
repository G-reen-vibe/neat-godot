## 2D Spider Walker environment.
##
## A simple 2D physics creature with a body and 4 legs, each leg having an upper
## and lower segment connected by a knee joint. The genome controls target
## angles for each leg's hip and knee.
##
## Physics: simple Verlet-style integration. The body has mass; each foot
## applies a force to the body when touching the ground. Ground friction
## translates foot forces into horizontal body motion.
##
## Inputs (12): for each of 4 legs: (touch_sensor, hip_angle, knee_angle, body_x_vel)
## Outputs (8): for each of 4 legs: (hip_target_delta, knee_target_delta)
##
## Fitness: horizontal distance traveled.
class_name SpiderWalker2DEnvironment
extends NeatEnvironment

const NUM_LEGS: int = 4
const BODY_RADIUS: float = 0.4
const LEG_UPPER_LEN: float = 0.5
const LEG_LOWER_LEN: float = 0.5
const GRAVITY: float = 9.8
const GROUND_Y: float = 0.0
const DT: float = 0.05
const MAX_STEPS: int = 1000
const MUSCLE_TORQUE: float = 8.0
const GROUND_FRICTION: float = 0.7

# Network IO config.
var input_node_ids: Array[int] = []
var bias_node_id: int = -1
var output_node_ids: Array[int] = []

# State.
# Body position (x, y) and velocity (vx, vy).
var _body_x: float = 0.0
var _body_y: float = BODY_RADIUS + LEG_UPPER_LEN + LEG_LOWER_LEN  # standing on legs
var _body_vx: float = 0.0
var _body_vy: float = 0.0
# Per-leg state.
# Each leg has: hip_angle (relative to body down), knee_angle (relative to upper leg).
# Angles in radians. 0 = leg pointing straight down.
var _hip_angles: Array[float] = []
var _knee_angles: Array[float] = []
var _hip_targets: Array[float] = []
var _knee_targets: Array[float] = []
var _feet_touching: Array[bool] = []
# Legs are arranged at 90° intervals around the body (top-down view, body faces +x).
# Leg base angles (in body frame, 0 = forward, +pi/2 = left).
var _leg_base_angles: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
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
        for i in range(NUM_LEGS):
                _hip_angles[i] = 0.0
                _knee_angles[i] = 0.0
                _hip_targets[i] = 0.0
                _knee_targets[i] = 0.0
                _feet_touching[i] = false

func reset(rng: RandomNumberGenerator = null) -> void:
        _body_x = 0.0
        _body_y = BODY_RADIUS + LEG_UPPER_LEN + LEG_LOWER_LEN
        _body_vx = 0.0
        _body_vy = 0.0
        for i in range(NUM_LEGS):
                _hip_angles[i] = 0.0 if rng == null else rng.randf_range(-0.2, 0.2)
                _knee_angles[i] = 0.0 if rng == null else rng.randf_range(-0.2, 0.2)
                _hip_targets[i] = _hip_angles[i]
                _knee_targets[i] = _knee_angles[i]
                _feet_touching[i] = false
        _steps = 0
        _done = false
        _initial_x = 0.0

func initial_state() -> Dictionary:
        return _build_state_dict()

func _build_state_dict() -> Dictionary:
        var d: Dictionary = {}
        for i in range(NUM_LEGS):
                d[input_node_ids[i * 3 + 0]] = 1.0 if _feet_touching[i] else 0.0
                d[input_node_ids[i * 3 + 1]] = _hip_angles[i] / PI  # normalized to [-1, 1]
                d[input_node_ids[i * 3 + 2]] = _knee_angles[i] / PI
        # Body x velocity (shared input, used as the 12th).
        # Wait, the layout is 4 legs * 3 = 12 inputs.
        # Let me re-derive: input_ids[0..11] = leg0(t, h, k), leg1(t, h, k), leg2(t, h, k), leg3(t, h, k)
        # That's only 12 inputs, no body_vx. Let's keep it 12 and drop body_vx.
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
        # Update target angles based on outputs.
        for i in range(NUM_LEGS):
                var leg_action: Dictionary = action[i]
                # Each output is in [-1, 1]; scale to a delta per step.
                _hip_targets[i] += float(leg_action["hip"]) * 0.3
                _knee_targets[i] += float(leg_action["knee"]) * 0.3
                # Clamp targets.
                _hip_targets[i] = clampf(_hip_targets[i], -PI * 0.5, PI * 0.5)
                _knee_targets[i] = clampf(_knee_targets[i], -PI * 0.5, PI * 0.5)
        # Move angles toward targets (limited muscle speed).
        for i in range(NUM_LEGS):
                var hip_diff: float = _hip_targets[i] - _hip_angles[i]
                var knee_diff: float = _knee_targets[i] - _knee_angles[i]
                _hip_angles[i] += clampf(hip_diff, -0.2, 0.2)
                _knee_angles[i] += clampf(knee_diff, -0.2, 0.2)
        # Compute foot positions and ground contact.
        var foot_positions: Array = []
        var total_foot_force_x: float = 0.0
        var total_foot_force_y: float = 0.0
        var feet_on_ground: int = 0
        for i in range(NUM_LEGS):
                # Foot position in world space.
                var base_angle: float = _leg_base_angles[i]
                # Hip joint position (on body surface in direction of base_angle).
                var hip_x: float = _body_x + cos(base_angle) * BODY_RADIUS
                var hip_y: float = _body_y + sin(base_angle) * BODY_RADIUS * 0.3  # body is circular, mostly side-to-side
                # Upper leg end (knee): rotate from straight-down by hip_angle.
                # In 2D side view, leg goes down from hip. hip_angle=0 = straight down.
                # For top-down spider, this is a simplification: we project legs in 2D side view.
                # Upper leg goes from hip in direction (sin(hip_angle+base_angle), cos(hip_angle+base_angle)).
                var upper_angle: float = base_angle + _hip_angles[i]
                var knee_x: float = hip_x + sin(upper_angle) * LEG_UPPER_LEN
                var knee_y: float = hip_y - cos(upper_angle) * LEG_UPPER_LEN
                # Lower leg: rotate by knee_angle from upper leg direction.
                var lower_angle: float = upper_angle + _knee_angles[i]
                var foot_x: float = knee_x + sin(lower_angle) * LEG_LOWER_LEN
                var foot_y: float = knee_y - cos(lower_angle) * LEG_LOWER_LEN
                foot_positions.append(Vector2(foot_x, foot_y))
                # Ground contact.
                _feet_touching[i] = foot_y <= GROUND_Y + 0.05
                if _feet_touching[i]:
                        feet_on_ground += 1
        # Apply gravity to body.
        _body_vy -= GRAVITY * DT
        # Apply foot forces: each foot on ground pushes body up and (depending
        # on horizontal motion) forward/backward.
        if feet_on_ground > 0:
                # Vertical: counter gravity.
                var support_per_foot: float = GRAVITY / float(feet_on_ground)
                _body_vy += support_per_foot * DT * float(feet_on_ground)
                # Horizontal: feet that are moving relative to body apply friction force.
                for i in range(NUM_LEGS):
                        if _feet_touching[i]:
                                # Horizontal foot velocity = body vx + tangential leg motion.
                                # Approximate: foot moves opposite to body when leg angles change.
                                # Friction force opposes relative motion.
                                var foot_rel_vx: float = _body_vx  # rough: foot wants to stay (static friction)
                                var friction: float = -foot_rel_vx * GROUND_FRICTION
                                total_foot_force_x += friction
                _body_vx += total_foot_force_x * DT
        # Update body position.
        _body_x += _body_vx * DT
        _body_y += _body_vy * DT
        # Don't let body fall through ground.
        var min_body_y: float = BODY_RADIUS + 0.1
        if _body_y < min_body_y:
                _body_y = min_body_y
                _body_vy = 0.0
        # Body falls off the world = done.
        if _body_y < -1.0:
                _done = true
        _steps += 1
        if _steps >= MAX_STEPS:
                _done = true
        return _build_state_dict()

func is_done() -> bool:
        return _done

func current_fitness() -> float:
        # Distance traveled (positive forward = +x).
        return maxf(0.0, _body_x - _initial_x)

func is_solved() -> bool:
        return _body_x - _initial_x > 5.0

func view_type() -> String:
        return "2d"

func get_visual_state() -> Dictionary:
        var feet_pos: Array = []
        for i in range(NUM_LEGS):
                var base_angle: float = _leg_base_angles[i]
                var hip_x: float = _body_x + cos(base_angle) * BODY_RADIUS
                var hip_y: float = _body_y + sin(base_angle) * BODY_RADIUS * 0.3
                var upper_angle: float = base_angle + _hip_angles[i]
                var knee_x: float = hip_x + sin(upper_angle) * LEG_UPPER_LEN
                var knee_y: float = hip_y - cos(upper_angle) * LEG_UPPER_LEN
                var lower_angle: float = upper_angle + _knee_angles[i]
                var foot_x: float = knee_x + sin(lower_angle) * LEG_LOWER_LEN
                var foot_y: float = knee_y - cos(lower_angle) * LEG_LOWER_LEN
                feet_pos.append({"hip": Vector2(hip_x, hip_y), "knee": Vector2(knee_x, knee_y), "foot": Vector2(foot_x, foot_y), "touching": _feet_touching[i]})
        return {
                "body_x": _body_x,
                "body_y": _body_y,
                "body_vx": _body_vx,
                "body_vy": _body_vy,
                "steps": _steps,
                "max_steps": MAX_STEPS,
                "done": _done,
                "body_radius": BODY_RADIUS,
                "ground_y": GROUND_Y,
                "feet": feet_pos,
                "distance": _body_x - _initial_x,
        }
