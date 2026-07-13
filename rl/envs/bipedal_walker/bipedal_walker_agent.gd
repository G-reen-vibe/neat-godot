## Bipedal Walker agent: a torso with two legs, each with hip + knee joints.
##
## Observation (8):
##   0  hip angle (left)    (normalized by PI)
##   1  knee angle (left)   (normalized by PI)
##   2  hip angle (right)   (normalized by PI)
##   3  knee angle (right)  (normalized by PI)
##   4  torso angle         (normalized by PI)
##   5  torso vx            (normalized)
##   6  torso vy            (normalized)
##   7  ground contact      (0 or 1, true if any foot is touching)
##
## Action (4): [left_hip_torque, left_knee_torque, right_hip_torque, right_knee_torque]
##   Each in [-1, 1], scaled by TORQUE_SCALE.
##
## Reward: +0.1 per step alive + 0.1 * forward_dx, -5 for falling.
## Done: torso falls below FALL_Y, or step cap reached.
class_name BipedalWalkerAgent
extends RLAgent

const OBS_DIM := 8
const ACTION_DIM := 4
const TORQUE_SCALE := 400.0
const FALL_Y := 100.0
const GROUND_Y := 111.0

@export var torso_path: NodePath = ^"../Torso"
@export var left_thigh_path: NodePath = ^"../LeftThigh"
@export var left_shin_path: NodePath = ^"../LeftShin"
@export var right_thigh_path: NodePath = ^"../RightThigh"
@export var right_shin_path: NodePath = ^"../RightShin"
@export var left_foot_path: NodePath = ^"../LeftFoot"
@export var right_foot_path: NodePath = ^"../RightFoot"

var torso: RLResettableBody2D
var left_thigh: RLResettableBody2D
var left_shin: RLResettableBody2D
var right_thigh: RLResettableBody2D
var right_shin: RLResettableBody2D
var left_foot: RLResettableBody2D
var right_foot: RLResettableBody2D

var _initial_torso: Transform2D
var _initial_left_thigh: Transform2D
var _initial_left_shin: Transform2D
var _initial_right_thigh: Transform2D
var _initial_right_shin: Transform2D
var _initial_left_foot: Transform2D
var _initial_right_foot: Transform2D

# B4 fix: reward is computed in _physics_process (after Godot steps
# physics), so get_reward() is a pure read of _cached_reward.
# _prev_x is updated here too, so dx reflects THIS step's movement.
var _cached_reward: float = 0.0
var _prev_x: float = 0.0


func _setup() -> void:
        torso = get_node(torso_path) as RLResettableBody2D
        left_thigh = get_node(left_thigh_path) as RLResettableBody2D
        left_shin = get_node(left_shin_path) as RLResettableBody2D
        right_thigh = get_node(right_thigh_path) as RLResettableBody2D
        right_shin = get_node(right_shin_path) as RLResettableBody2D
        left_foot = get_node(left_foot_path) as RLResettableBody2D
        right_foot = get_node(right_foot_path) as RLResettableBody2D
        _initial_torso = torso.transform
        _initial_left_thigh = left_thigh.transform
        _initial_left_shin = left_shin.transform
        _initial_right_thigh = right_thigh.transform
        _initial_right_shin = right_shin.transform
        _initial_left_foot = left_foot.transform
        _initial_right_foot = right_foot.transform
        _prev_x = torso.position.x


func get_observation() -> PackedFloat32Array:
        var obs := PackedFloat32Array()
        obs.resize(OBS_DIM)
        obs[0] = clampf(left_thigh.rotation / PI, -1.0, 1.0)
        obs[1] = clampf(left_shin.rotation / PI, -1.0, 1.0)
        obs[2] = clampf(right_thigh.rotation / PI, -1.0, 1.0)
        obs[3] = clampf(right_shin.rotation / PI, -1.0, 1.0)
        obs[4] = clampf(torso.rotation / PI, -1.0, 1.0)
        obs[5] = clampf(torso.linear_velocity.x / 100.0, -1.0, 1.0)
        obs[6] = clampf(torso.linear_velocity.y / 100.0, -1.0, 1.0)
        obs[7] = 1.0 if _has_ground_contact() else 0.0
        return obs


func set_action(action: PackedFloat32Array) -> void:
        if action.is_empty() or action.size() < 4:
                return
        left_thigh.apply_torque(clampf(action[0], -1.0, 1.0) * TORQUE_SCALE)
        left_shin.apply_torque(clampf(action[1], -1.0, 1.0) * TORQUE_SCALE)
        right_thigh.apply_torque(clampf(action[2], -1.0, 1.0) * TORQUE_SCALE)
        right_shin.apply_torque(clampf(action[3], -1.0, 1.0) * TORQUE_SCALE)


# B4 fix: compute reward AFTER physics has stepped (Godot calls
# _physics_process after integrating forces). This way _cached_reward
# reflects the actual movement caused by this step's action.
func _physics_process(_delta: float) -> void:
        if _is_fallen():
                _cached_reward = -5.0
        else:
                var dx: float = torso.position.x - _prev_x
                _cached_reward = dx * 0.1 + 0.1
        _prev_x = torso.position.x


func _has_ground_contact() -> bool:
        return left_foot.position.y > GROUND_Y - 15.0 or right_foot.position.y > GROUND_Y - 15.0


func _is_fallen() -> bool:
        return torso.position.y > FALL_Y or abs(torso.rotation) > deg_to_rad(60.0)


func get_reward() -> float:
        return _cached_reward


func is_done() -> bool:
        return _is_fallen()


func reset() -> void:
        _cached_reward = 0.0
        _prev_x = _initial_torso.origin.x
        torso.request_reset(_initial_torso, Vector2.ZERO, 0.0)
        left_thigh.request_reset(_initial_left_thigh, Vector2.ZERO, 0.0)
        left_shin.request_reset(_initial_left_shin, Vector2.ZERO, 0.0)
        right_thigh.request_reset(_initial_right_thigh, Vector2.ZERO, 0.0)
        right_shin.request_reset(_initial_right_shin, Vector2.ZERO, 0.0)
        left_foot.request_reset(_initial_left_foot, Vector2.ZERO, 0.0)
        right_foot.request_reset(_initial_right_foot, Vector2.ZERO, 0.0)


func get_action_dim() -> int:
        return ACTION_DIM


func get_obs_dim() -> int:
        return OBS_DIM
