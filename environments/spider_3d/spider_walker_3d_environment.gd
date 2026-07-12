## 3D Spider Walker environment using a custom verlet physics simulation.
##
## Same approach as SpiderWalker2D but extended to 3D. The creature has a
## spherical body and 4 legs arranged around it (front, back, left, right).
## Each leg has a hip joint (yaw + pitch) and a knee joint. The genome controls
## target angles for each joint. Foot-pinning + friction propels the body.
##
## Inputs (16): for each of 4 legs: (touch, hip_yaw, hip_pitch, knee_angle)
## Outputs (12): for each of 4 legs: (hip_yaw_delta, hip_pitch_delta, knee_delta)
##
## Fitness: horizontal distance from start (forward in +x).
class_name SpiderWalker3DEnvironment
extends NeatEnvironment

const NUM_LEGS: int = 4
const BODY_RADIUS: float = 0.4
const LEG_UPPER_LEN: float = 0.5
const LEG_LOWER_LEN: float = 0.5
const GROUND_Y: float = 0.0
const DT: float = 0.02
const MAX_STEPS: int = 1000
const GRAVITY: float = 9.8
const FRICTION: float = 4.0
const MUSCLE_SPEED: float = 8.0

var _leg_base_angles: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]  # yaw around Y

# Network IO config.
var input_node_ids: Array[int] = []
var bias_node_id: int = -1
var output_node_ids: Array[int] = []

# Body state: position (Vector3), velocity (Vector3).
var _body_pos: Vector3 = Vector3.ZERO
var _body_vel: Vector3 = Vector3.ZERO
# Per-leg joint angles: hip_yaw, hip_pitch, knee.
var _hip_yaw: Array[float] = []
var _hip_pitch: Array[float] = []
var _knee: Array[float] = []
var _hip_yaw_target: Array[float] = []
var _hip_pitch_target: Array[float] = []
var _knee_target: Array[float] = []
var _feet_touching: Array[bool] = []
var _prev_foot_world: Array = []  # Array[Vector3]

var _steps: int = 0
var _done: bool = false
var _initial_pos: Vector3 = Vector3.ZERO

func _init(p_input_ids: Array[int] = [], p_bias_id: int = -1, p_output_ids: Array[int] = []) -> void:
        input_node_ids = p_input_ids
        bias_node_id = p_bias_id
        output_node_ids = p_output_ids
        _hip_yaw.resize(NUM_LEGS)
        _hip_pitch.resize(NUM_LEGS)
        _knee.resize(NUM_LEGS)
        _hip_yaw_target.resize(NUM_LEGS)
        _hip_pitch_target.resize(NUM_LEGS)
        _knee_target.resize(NUM_LEGS)
        _feet_touching.resize(NUM_LEGS)
        _prev_foot_world.resize(NUM_LEGS)
        for i in range(NUM_LEGS):
                _hip_yaw[i] = 0.0
                _hip_pitch[i] = 0.0
                _knee[i] = 0.0
                _hip_yaw_target[i] = 0.0
                _hip_pitch_target[i] = 0.0
                _knee_target[i] = 0.0
                _feet_touching[i] = false
                _prev_foot_world[i] = Vector3.ZERO

func reset(rng: RandomNumberGenerator = null) -> void:
        _body_pos = Vector3.ZERO
        _body_pos.y = BODY_RADIUS + LEG_UPPER_LEN + LEG_LOWER_LEN
        _body_vel = Vector3.ZERO
        for i in range(NUM_LEGS):
                if rng != null:
                        _hip_yaw[i] = rng.randf_range(-0.2, 0.2)
                        _hip_pitch[i] = rng.randf_range(-0.2, 0.2)
                        _knee[i] = rng.randf_range(-0.2, 0.2)
                else:
                        _hip_yaw[i] = 0.0
                        _hip_pitch[i] = 0.0
                        _knee[i] = 0.0
                _hip_yaw_target[i] = _hip_yaw[i]
                _hip_pitch_target[i] = _hip_pitch[i]
                _knee_target[i] = _knee[i]
                _feet_touching[i] = false
                _prev_foot_world[i] = _compute_foot_world(i)
        _steps = 0
        _done = false
        _initial_pos = _body_pos

func _compute_hip_world(leg_idx: int) -> Vector3:
        var base: float = _leg_base_angles[leg_idx]
        var offset := Vector3(cos(base) * BODY_RADIUS, 0.0, sin(base) * BODY_RADIUS)
        return _body_pos + offset

func _compute_knee_world(leg_idx: int) -> Vector3:
        var hip := _compute_hip_world(leg_idx)
        var base: float = _leg_base_angles[leg_idx]
        var yaw: float = base + _hip_yaw[leg_idx]
        # Pitch=0 means leg points straight DOWN. pitch=π/2 means horizontal.
        # This matches a natural resting pose where legs reach the ground.
        var pitch: float = _hip_pitch[leg_idx]
        var dir := Vector3(cos(yaw) * sin(pitch), -cos(pitch), sin(yaw) * sin(pitch)).normalized()
        return hip + dir * LEG_UPPER_LEN

func _compute_foot_world(leg_idx: int) -> Vector3:
        var knee := _compute_knee_world(leg_idx)
        var base: float = _leg_base_angles[leg_idx]
        var yaw: float = base + _hip_yaw[leg_idx]
        var lower_pitch: float = _hip_pitch[leg_idx] + _knee[leg_idx]
        var dir := Vector3(cos(yaw) * sin(lower_pitch), -cos(lower_pitch), sin(yaw) * sin(lower_pitch)).normalized()
        return knee + dir * LEG_LOWER_LEN

func initial_state() -> Dictionary:
        return _build_state_dict()

func _build_state_dict() -> Dictionary:
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

func step(action: Dictionary) -> Dictionary:
        for i in range(NUM_LEGS):
                var leg_action: Dictionary = action[i]
                _hip_yaw_target[i] += float(leg_action["yaw"]) * 0.3
                _hip_pitch_target[i] += float(leg_action["pitch"]) * 0.3
                _knee_target[i] += float(leg_action["knee"]) * 0.3
                _hip_yaw_target[i] = clampf(_hip_yaw_target[i], -PI * 0.5, PI * 0.5)
                _hip_pitch_target[i] = clampf(_hip_pitch_target[i], -PI * 0.5, PI * 0.5)
                _knee_target[i] = clampf(_knee_target[i], -PI * 0.5, PI * 0.5)
        # Move angles toward targets.
        for i in range(NUM_LEGS):
                var yaw_diff: float = _hip_yaw_target[i] - _hip_yaw[i]
                var pitch_diff: float = _hip_pitch_target[i] - _hip_pitch[i]
                var knee_diff: float = _knee_target[i] - _knee[i]
                _hip_yaw[i] += clampf(yaw_diff * MUSCLE_SPEED * DT, -0.3, 0.3)
                _hip_pitch[i] += clampf(pitch_diff * MUSCLE_SPEED * DT, -0.3, 0.3)
                _knee[i] += clampf(knee_diff * MUSCLE_SPEED * DT, -0.3, 0.3)
        # Compute new foot positions.
        var new_foot_world: Array = []
        new_foot_world.resize(NUM_LEGS)
        for i in range(NUM_LEGS):
                new_foot_world[i] = _compute_foot_world(i)
        # Determine touching.
        var touching_threshold: float = 0.05
        for i in range(NUM_LEGS):
                _feet_touching[i] = (new_foot_world[i] as Vector3).y <= GROUND_Y + touching_threshold
        # Apply gravity.
        _body_vel.y -= GRAVITY * DT
        # Foot-pinning.
        var feet_on_ground: int = 0
        var body_dx: float = 0.0
        var body_dy: float = 0.0
        var body_dz: float = 0.0
        for i in range(NUM_LEGS):
                if _feet_touching[i]:
                        var prev_foot: Vector3 = _prev_foot_world[i]
                        var new_foot: Vector3 = new_foot_world[i]
                        var leg_delta: Vector3 = new_foot - prev_foot
                        body_dx -= leg_delta.x
                        body_dy -= leg_delta.y
                        body_dz -= leg_delta.z
                        feet_on_ground += 1
        if feet_on_ground > 0:
                body_dx /= float(feet_on_ground)
                body_dy /= float(feet_on_ground)
                body_dz /= float(feet_on_ground)
                _body_vel.x = body_dx / DT
                _body_vel.y = body_dy / DT
                _body_vel.z = body_dz / DT
                # Horizontal friction.
                _body_vel.x *= 1.0 - FRICTION * DT
                _body_vel.z *= 1.0 - FRICTION * DT
        # Update body position.
        _body_pos += _body_vel * DT
        var min_body_y: float = BODY_RADIUS + 0.05
        if _body_pos.y < min_body_y:
                _body_pos.y = min_body_y
                _body_vel.y = 0.0
        _prev_foot_world = new_foot_world.duplicate()
        _steps += 1
        if _steps >= MAX_STEPS:
                _done = true
        if _body_pos.y < -1.0:
                _done = true
        return _build_state_dict()

func is_done() -> bool:
        return _done

func current_fitness() -> float:
        var d := _body_pos - _initial_pos
        var horiz: float = sqrt(d.x * d.x + d.z * d.z)
        var forward: float = maxf(0.0, d.x)
        return forward + 0.05 * horiz

func is_solved() -> bool:
        var d := _body_pos - _initial_pos
        return sqrt(d.x * d.x + d.z * d.z) > 5.0

func view_type() -> String:
        return "3d"

func get_visual_state() -> Dictionary:
        var feet: Array = []
        for i in range(NUM_LEGS):
                var hip := _compute_hip_world(i)
                var knee := _compute_knee_world(i)
                var foot := _compute_foot_world(i)
                feet.append({"hip": hip, "knee": knee, "foot": foot, "touching": _feet_touching[i]})
        return {
                "body_pos": _body_pos,
                "body_vel": _body_vel,
                "steps": _steps,
                "max_steps": MAX_STEPS,
                "done": _done,
                "body_radius": BODY_RADIUS,
                "ground_y": GROUND_Y,
                "feet": feet,
                "distance": current_fitness(),
                "initial_pos": _initial_pos,
        }
