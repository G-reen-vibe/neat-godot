## 3D Spider Walker environment.
##
## A 3D physics creature with a body and 4 legs, each leg having an upper and
## lower segment connected by a knee joint. The genome controls target angles
## for each leg's hip (yaw + pitch) and knee.
##
## Same simplified Verlet-style physics as the 2D version, but extended to 3D.
## The body moves in the XZ plane (Y is up).
##
## Inputs (16): for each of 4 legs: (touch, hip_yaw, hip_pitch, knee_angle)
## Outputs (12): for each of 4 legs: (hip_yaw_delta, hip_pitch_delta, knee_delta)
##
## Fitness: horizontal distance from start (sqrt(dx² + dz²)).
class_name SpiderWalker3DEnvironment
extends NeatEnvironment

const NUM_LEGS: int = 4
const BODY_RADIUS: float = 0.4
const LEG_UPPER_LEN: float = 0.5
const LEG_LOWER_LEN: float = 0.5
const GRAVITY: float = 9.8
const GROUND_Y: float = 0.0
const DT: float = 0.05
const MAX_STEPS: int = 1000
const GROUND_FRICTION: float = 0.7

# Network IO config.
var input_node_ids: Array[int] = []
var bias_node_id: int = -1
var output_node_ids: Array[int] = []

# State.
var _body_pos: Vector3 = Vector3.ZERO
var _body_vel: Vector3 = Vector3.ZERO
var _leg_base_angles: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]  # yaw around Y
# Per-leg joint angles: hip_yaw, hip_pitch, knee.
var _hip_yaw: Array[float] = []
var _hip_pitch: Array[float] = []
var _knee: Array[float] = []
var _hip_yaw_target: Array[float] = []
var _hip_pitch_target: Array[float] = []
var _knee_target: Array[float] = []
var _feet_touching: Array[bool] = []
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
        for i in range(NUM_LEGS):
                _hip_yaw[i] = 0.0
                _hip_pitch[i] = 0.0
                _knee[i] = 0.0
                _hip_yaw_target[i] = 0.0
                _hip_pitch_target[i] = 0.0
                _knee_target[i] = 0.0
                _feet_touching[i] = false

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
        _steps = 0
        _done = false
        _initial_pos = _body_pos

func initial_state() -> Dictionary:
        return _build_state_dict()

func _build_state_dict() -> Dictionary:
        var d: Dictionary = {}
        for i in range(NUM_LEGS):
                d[input_node_ids[i * 4 + 0]] = 1.0 if _feet_touching[i] else 0.0
                d[input_node_ids[i * 4 + 1]] = _hip_yaw[i] / PI
                d[input_node_ids[i * 4 + 2]] = _hip_pitch[i] / PI
                d[input_node_ids[i * 4 + 3]] = _knee[i] / PI
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
        for i in range(NUM_LEGS):
                _hip_yaw[i] += clampf(_hip_yaw_target[i] - _hip_yaw[i], -0.2, 0.2)
                _hip_pitch[i] += clampf(_hip_pitch_target[i] - _hip_pitch[i], -0.2, 0.2)
                _knee[i] += clampf(_knee_target[i] - _knee[i], -0.2, 0.2)
        # Compute foot positions.
        var feet_on_ground: int = 0
        var total_foot_force_x: float = 0.0
        var total_foot_force_z: float = 0.0
        for i in range(NUM_LEGS):
                var hip_pos := _compute_hip_pos(i)
                var knee_pos := _compute_knee_pos(i, hip_pos)
                var foot_pos := _compute_foot_pos(i, knee_pos)
                _feet_touching[i] = foot_pos.y <= GROUND_Y + 0.05
                if _feet_touching[i]:
                        feet_on_ground += 1
        # Apply gravity.
        _body_vel.y -= GRAVITY * DT
        # Foot support.
        if feet_on_ground > 0:
                var support_per_foot: float = GRAVITY / float(feet_on_ground)
                _body_vel.y += support_per_foot * DT * float(feet_on_ground)
                for i in range(NUM_LEGS):
                        if _feet_touching[i]:
                                var foot_rel_vx: float = _body_vel.x
                                var foot_rel_vz: float = _body_vel.z
                                total_foot_force_x += -foot_rel_vx * GROUND_FRICTION
                                total_foot_force_z += -foot_rel_vz * GROUND_FRICTION
                _body_vel.x += total_foot_force_x * DT
                _body_vel.z += total_foot_force_z * DT
        # Update body position.
        _body_pos += _body_vel * DT
        var min_body_y: float = BODY_RADIUS + 0.1
        if _body_pos.y < min_body_y:
                _body_pos.y = min_body_y
                _body_vel.y = 0.0
        if _body_pos.y < -1.0:
                _done = true
        _steps += 1
        if _steps >= MAX_STEPS:
                _done = true
        return _build_state_dict()

func _compute_hip_pos(leg_idx: int) -> Vector3:
        var base: float = _leg_base_angles[leg_idx]
        return Vector3(
                _body_pos.x + cos(base) * BODY_RADIUS,
                _body_pos.y,
                _body_pos.z + sin(base) * BODY_RADIUS,
        )

func _compute_knee_pos(leg_idx: int, hip_pos: Vector3) -> Vector3:
        var base: float = _leg_base_angles[leg_idx]
        var yaw: float = base + _hip_yaw[leg_idx]
        var pitch: float = _hip_pitch[leg_idx]
        # Upper leg direction: in XZ plane by yaw, then downward by pitch.
        var dir := Vector3(
                cos(yaw) * cos(pitch),
                -sin(pitch),
                sin(yaw) * cos(pitch),
        ).normalized()
        return hip_pos + dir * LEG_UPPER_LEN

func _compute_foot_pos(leg_idx: int, knee_pos: Vector3) -> Vector3:
        var base: float = _leg_base_angles[leg_idx]
        var yaw: float = base + _hip_yaw[leg_idx]
        var pitch: float = _hip_pitch[leg_idx] + _knee[leg_idx]
        var dir := Vector3(
                cos(yaw) * cos(pitch),
                -sin(pitch),
                sin(yaw) * cos(pitch),
        ).normalized()
        return knee_pos + dir * LEG_LOWER_LEN

func is_done() -> bool:
        return _done

func current_fitness() -> float:
        var d := _body_pos - _initial_pos
        return maxf(0.0, sqrt(d.x * d.x + d.z * d.z))

func is_solved() -> bool:
        var d := _body_pos - _initial_pos
        return sqrt(d.x * d.x + d.z * d.z) > 5.0

func view_type() -> String:
        return "3d"

func get_visual_state() -> Dictionary:
        var feet: Array = []
        for i in range(NUM_LEGS):
                var hip := _compute_hip_pos(i)
                var knee := _compute_knee_pos(i, hip)
                var foot := _compute_foot_pos(i, knee)
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
                "leg_base_angles": _leg_base_angles.duplicate(),
        }
