## CartPole agent: owns the cart + pole bodies, exposes obs/action/reward.
##
## Observation (4):
##   0  cart x       (normalized to [-1, 1] by X_LIMIT)
##   1  cart vx      (normalized)
##   2  pole angle   (normalized by ANGLE_LIMIT)
##   3  pole ang vel (normalized)
##
## Action (1): force on cart in [-1, 1], scaled by FORCE_SCALE.
##
## Reward: +1 per step while upright.
## Done: |angle| > 12 deg, or |x| > X_LIMIT.
##
## Note: is_done() and get_reward() compute from LIVE physics state
## rather than a cached flag, to avoid one-frame lag between the
## physics server stepping and the Academy reading the result.
class_name CartPoleAgent
extends RLAgent

const OBS_DIM := 4
const ACTION_DIM := 1
const FORCE_SCALE := 800.0
const ANGLE_LIMIT := deg_to_rad(12.0)
const X_LIMIT_PX := 2.4 * 80.0
const POLE_HALF_LEN_PX := 60.0

@export var cart_path: NodePath = ^"../Cart"
@export var pole_path: NodePath = ^"../Pole"

var cart: RLResettableBody2D
var pole: RLResettableBody2D

var _initial_cart_pos: Vector2
var _initial_pole_pos: Vector2
var _initial_pole_rot: float


func _setup() -> void:
        cart = get_node(cart_path) as RLResettableBody2D
        pole = get_node(pole_path) as RLResettableBody2D
        _initial_cart_pos = cart.position
        _initial_pole_pos = pole.position
        _initial_pole_rot = pole.rotation


func get_observation() -> PackedFloat32Array:
        var obs := PackedFloat32Array()
        obs.resize(OBS_DIM)
        obs[0] = clampf(cart.position.x / X_LIMIT_PX, -1.0, 1.0)
        obs[1] = clampf(cart.linear_velocity.x / 500.0, -1.0, 1.0)
        obs[2] = clampf(pole.rotation / ANGLE_LIMIT, -1.0, 1.0)
        obs[3] = clampf(pole.angular_velocity / 5.0, -1.0, 1.0)
        return obs


func set_action(action: PackedFloat32Array) -> void:
        if action.is_empty():
                return
        var force: float = clampf(action[0], -1.0, 1.0) * FORCE_SCALE
        cart.apply_central_force(Vector2(force, 0.0))


func _is_upright() -> bool:
        return abs(pole.rotation) < ANGLE_LIMIT and abs(cart.position.x) < X_LIMIT_PX


func get_reward() -> float:
        return 1.0 if _is_upright() else 0.0


func is_done() -> bool:
        return not _is_upright()


func reset() -> void:
        var cart_x_jitter: float = randf_range(-5.0, 5.0)
        var pole_angle_jitter: float = randf_range(-0.05, 0.05)
        cart.request_reset(
                Transform2D(0.0, _initial_cart_pos + Vector2(cart_x_jitter, 0.0)),
                Vector2.ZERO,
                0.0
        )
        pole.request_reset(
                Transform2D(_initial_pole_rot + pole_angle_jitter, _initial_pole_pos),
                Vector2.ZERO,
                0.0
        )


func get_action_dim() -> int:
        return ACTION_DIM


func get_obs_dim() -> int:
        return OBS_DIM
