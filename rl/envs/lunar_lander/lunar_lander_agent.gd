## Lunar Lander agent: a lander that fires thrusters to land safely.
##
## Observation (6):
##   0  lander x       (normalized by ARENA_WIDTH/2)
##   1  lander y       (normalized by ARENA_HEIGHT/2)
##   2  lander vx      (normalized)
##   3  lander vy      (normalized)
##   4  lander angle   (normalized by PI)
##   5  lander ang vel (normalized)
##
## Action (3): [main_thrust, left_thrust, right_thrust] in [-1, 1]
##   main_thrust > 0: fires main engine (upward force)
##   left_thrust > 0: fires right-side thruster (pushes left, CCW torque)
##   right_thrust > 0: fires left-side thruster (pushes right, CW torque)
##
## Reward: +100 for landing safely, -100 for crashing, -0.3 per step
##   (fuel cost), + proximity bonus when near pad.
##
## Done: landed safely, crashed, or out of bounds.
##
## Note: is_done() and get_reward() compute from LIVE physics state
## to avoid one-frame lag between physics step and Academy read.
class_name LunarLanderAgent
extends RLAgent

const OBS_DIM := 6
const ACTION_DIM := 3

const ARENA_WIDTH := 400.0
const ARENA_HEIGHT := 300.0
const MAIN_THRUST_FORCE := 800.0
const SIDE_THRUST_FORCE := 200.0
const SAFE_LANDING_VEL := 50.0
const SAFE_LANDING_ANGLE := deg_to_rad(15.0)
const PAD_X := 0.0
const PAD_Y := 130.0
const PAD_HALF_WIDTH := 40.0
const NEAR_GROUND_Y := 110.0  # y > this = near ground

@export var lander_path: NodePath = ^"../Lander"

var lander: RLResettableBody2D
var _initial_pos: Vector2


func _setup() -> void:
	lander = get_node(lander_path) as RLResettableBody2D
	_initial_pos = lander.position


func get_observation() -> PackedFloat32Array:
	var obs := PackedFloat32Array()
	obs.resize(OBS_DIM)
	obs[0] = clampf(lander.position.x / (ARENA_WIDTH / 2.0), -1.0, 1.0)
	obs[1] = clampf(lander.position.y / (ARENA_HEIGHT / 2.0), -1.0, 1.0)
	obs[2] = clampf(lander.linear_velocity.x / 200.0, -1.0, 1.0)
	obs[3] = clampf(lander.linear_velocity.y / 200.0, -1.0, 1.0)
	obs[4] = clampf(lander.rotation / PI, -1.0, 1.0)
	obs[5] = clampf(lander.angular_velocity / 5.0, -1.0, 1.0)
	return obs


func set_action(action: PackedFloat32Array) -> void:
	if action.is_empty() or action.size() < 3:
		return
	var main: float = maxf(0.0, action[0])
	var left: float = maxf(0.0, action[1])
	var right: float = maxf(0.0, action[2])

	if main > 0.0:
		var thrust_dir: Vector2 = Vector2(0.0, -1.0).rotated(lander.rotation)
		lander.apply_central_force(thrust_dir * main * MAIN_THRUST_FORCE)

	if left > 0.0:
		lander.apply_torque(-left * SIDE_THRUST_FORCE * 10.0)
	if right > 0.0:
		lander.apply_torque(right * SIDE_THRUST_FORCE * 10.0)


func _is_near_ground() -> bool:
	return lander.position.y > NEAR_GROUND_Y


func _is_out_of_bounds() -> bool:
	return abs(lander.position.x) > ARENA_WIDTH / 2.0 or lander.position.y < -ARENA_HEIGHT / 2.0


func _is_safe_landing() -> bool:
	var on_pad: bool = abs(lander.position.x - PAD_X) < PAD_HALF_WIDTH
	var slow: bool = lander.linear_velocity.length() < SAFE_LANDING_VEL
	var upright: bool = abs(lander.rotation) < SAFE_LANDING_ANGLE
	return on_pad and slow and upright


func get_reward() -> float:
	if _is_out_of_bounds():
		return -100.0
	if _is_near_ground():
		return 100.0 if _is_safe_landing() else -100.0
	# Per-step: fuel cost + proximity bonus
	var dist_to_pad: float = abs(lander.position.x - PAD_X)
	var prox_bonus: float = 0.0
	if dist_to_pad < PAD_HALF_WIDTH * 2.0:
		prox_bonus = 0.5 * (1.0 - dist_to_pad / (PAD_HALF_WIDTH * 2.0))
	return -0.3 + prox_bonus


func is_done() -> bool:
	return _is_near_ground() or _is_out_of_bounds()


func reset() -> void:
	var start_x: float = randf_range(-100.0, 100.0)
	var start_angle: float = randf_range(-0.2, 0.2)
	lander.request_reset(
		Transform2D(start_angle, Vector2(start_x, -100.0)),
		Vector2(randf_range(-30.0, 30.0), 0.0),
		0.0
	)


func get_action_dim() -> int:
	return ACTION_DIM


func get_obs_dim() -> int:
	return OBS_DIM
