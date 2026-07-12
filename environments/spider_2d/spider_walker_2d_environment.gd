## 2D Spider Walker environment.
##
## A 2D physics creature with a body and 4 legs, each leg having an upper
## and lower segment connected by a knee joint. The genome controls target
## angles for each leg's hip and knee.
##
## Physics: foot-pinning constraint. When a foot is on the ground, its world
## position is held fixed; the body moves opposite to the foot's body-frame
## motion. This naturally produces forward locomotion when legs swing backward
## while grounded and forward while lifted.
##
## Inputs (12): for each of 4 legs: (touch_sensor, hip_angle, knee_angle, foot_x_body)
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
# Legs arranged around the body. In top-down 2D, base angles spread the legs.
# We project to a side view for 2D: legs at base angles 0 (front), PI (back),
# and we use 4 legs at ±0.4 rad offsets to simulate a 4-legged creature.
var _leg_base_angles: Array[float] = [-0.6, -0.2, 0.2, 0.6]
# Standing body height = body_radius + max_leg_reach.
var _standing_body_y: float = BODY_RADIUS + LEG_UPPER_LEN + LEG_LOWER_LEN

# Network IO config.
var input_node_ids: Array[int] = []
var bias_node_id: int = -1
var output_node_ids: Array[int] = []

# State.
var _body_x: float = 0.0
var _body_y: float = 0.0
var _body_vx: float = 0.0
var _body_vy: float = 0.0
var _hip_angles: Array[float] = []
var _knee_angles: Array[float] = []
var _hip_targets: Array[float] = []
var _knee_targets: Array[float] = []
var _feet_touching: Array[bool] = []
# Previous foot offsets in body frame (for computing body motion via pinning).
var _prev_foot_offsets: Array = []  # Array[Vector2]
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
        _prev_foot_offsets.resize(NUM_LEGS)
        for i in range(NUM_LEGS):
                _hip_angles[i] = 0.0
                _knee_angles[i] = 0.0
                _hip_targets[i] = 0.0
                _knee_targets[i] = 0.0
                _feet_touching[i] = false
                _prev_foot_offsets[i] = Vector2.ZERO

func reset(rng: RandomNumberGenerator = null) -> void:
        _body_x = 0.0
        _body_y = _standing_body_y
        _body_vx = 0.0
        _body_vy = 0.0
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
                _prev_foot_offsets[i] = _compute_foot_offset(i)
        _steps = 0
        _done = false
        _initial_x = 0.0

func _compute_foot_offset(leg_idx: int) -> Vector2:
        # Returns foot position relative to body (in body frame).
        var base: float = _leg_base_angles[leg_idx]
        var hip_offset := Vector2(cos(base) * BODY_RADIUS, 0.0)
        var upper_angle: float = base + _hip_angles[leg_idx]
        # Upper leg goes from hip downward (negative y) rotated by upper_angle.
        # hip_angle=0 means leg points straight down.
        # In our 2D side view: leg extends from hip in direction (sin(upper_angle), -cos(upper_angle)).
        var knee_offset := hip_offset + Vector2(sin(upper_angle), -cos(upper_angle)) * LEG_UPPER_LEN
        var lower_angle: float = upper_angle + _knee_angles[leg_idx]
        var foot_offset := knee_offset + Vector2(sin(lower_angle), -cos(lower_angle)) * LEG_LOWER_LEN
        return foot_offset

func initial_state() -> Dictionary:
        return _build_state_dict()

func _build_state_dict() -> Dictionary:
        var d: Dictionary = {}
        for i in range(NUM_LEGS):
                d[input_node_ids[i * 3 + 0]] = 1.0 if _feet_touching[i] else 0.0
                d[input_node_ids[i * 3 + 1]] = _hip_angles[i] / PI
                d[input_node_ids[i * 3 + 2]] = _knee_angles[i] / PI
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
                _hip_targets[i] += float(leg_action["hip"]) * 0.3
                _knee_targets[i] += float(leg_action["knee"]) * 0.3
                _hip_targets[i] = clampf(_hip_targets[i], -PI * 0.5, PI * 0.5)
                _knee_targets[i] = clampf(_knee_targets[i], -PI * 0.5, PI * 0.5)
        # Move angles toward targets (limited muscle speed).
        for i in range(NUM_LEGS):
                _hip_angles[i] += clampf(_hip_targets[i] - _hip_angles[i], -0.2, 0.2)
                _knee_angles[i] += clampf(_knee_targets[i] - _knee_angles[i], -0.2, 0.2)
        # Compute new foot offsets.
        var new_foot_offsets: Array = []
        new_foot_offsets.resize(NUM_LEGS)
        for i in range(NUM_LEGS):
                new_foot_offsets[i] = _compute_foot_offset(i)
        # Determine which feet are touching the ground (in world space).
        # Foot world Y = body_y + foot_offset.y. Touching if <= ground + threshold.
        var touching_threshold: float = 0.05
        for i in range(NUM_LEGS):
                var foot_world_y: float = _body_y + (new_foot_offsets[i] as Vector2).y
                _feet_touching[i] = foot_world_y <= GROUND_Y + touching_threshold
        # Apply gravity.
        _body_vy -= GRAVITY * DT
        # Compute body motion from feet on ground (foot-pinning).
        var feet_on_ground: int = 0
        var body_dx: float = 0.0
        var body_dy: float = 0.0
        for i in range(NUM_LEGS):
                if _feet_touching[i]:
                        # Foot is pinned: world position should not change.
                        # foot_world = body + foot_offset, so Δfoot_world = Δbody + Δfoot_offset = 0.
                        # => Δbody = -Δfoot_offset.
                        var delta_offset: Vector2 = (new_foot_offsets[i] as Vector2) - (_prev_foot_offsets[i] as Vector2)
                        body_dx -= delta_offset.x
                        body_dy -= delta_offset.y
                        feet_on_ground += 1
        if feet_on_ground > 0:
                body_dx /= float(feet_on_ground)
                body_dy /= float(feet_on_ground)
                # Body horizontal velocity directly from feet pinning.
                _body_vx = body_dx / DT
                # Vertical: foot-pinning overrides gravity when feet are on ground.
                _body_vy = body_dy / DT
        # Update body position.
        _body_x += _body_vx * DT
        _body_y += _body_vy * DT
        # Don't let body fall through ground.
        var min_body_y: float = BODY_RADIUS + 0.1
        if _body_y < min_body_y:
                _body_y = min_body_y
                _body_vy = 0.0
        # Save prev offsets for next step.
        _prev_foot_offsets = new_foot_offsets.duplicate()
        # Done conditions.
        if _body_y < -1.0:
                _done = true
        _steps += 1
        if _steps >= MAX_STEPS:
                _done = true
        return _build_state_dict()

func is_done() -> bool:
        return _done

func current_fitness() -> float:
        # Reward forward motion primarily; small reward for any motion (so that
        # learning can bootstrap even if the spider initially just wiggles).
        var forward: float = _body_x - _initial_x
        var any_motion: float = absf(forward)
        return maxf(0.0, forward) + 0.1 * any_motion

func is_solved() -> bool:
        return _body_x - _initial_x > 5.0

func view_type() -> String:
        return "2d"

func get_visual_state() -> Dictionary:
        var feet_pos: Array = []
        for i in range(NUM_LEGS):
                var foot_offset: Vector2 = _compute_foot_offset(i)
                var hip_offset := Vector2(cos(_leg_base_angles[i]) * BODY_RADIUS, 0.0)
                var upper_angle: float = _leg_base_angles[i] + _hip_angles[i]
                var knee_offset := hip_offset + Vector2(sin(upper_angle), -cos(upper_angle)) * LEG_UPPER_LEN
                feet_pos.append({
                        "hip": Vector2(_body_x + hip_offset.x, _body_y + hip_offset.y),
                        "knee": Vector2(_body_x + knee_offset.x, _body_y + knee_offset.y),
                        "foot": Vector2(_body_x + foot_offset.x, _body_y + foot_offset.y),
                        "touching": _feet_touching[i],
                })
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
