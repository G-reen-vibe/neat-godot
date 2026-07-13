## Pong agent: one paddle (left or right).
##
## Observation (5):
##   0  ball x       (normalized by ARENA_WIDTH)
##   1  ball y       (normalized by ARENA_HEIGHT)
##   2  ball vx      (normalized by MAX_BALL_SPEED)
##   3  ball vy      (normalized by MAX_BALL_SPEED)
##   4  own paddle y (normalized by ARENA_HEIGHT)
##
## Action (1): paddle velocity in [-1, 1], scaled by PADDLE_SPEED.
##
## Reward: +1 when opponent misses, -1 when self misses.
## Done: either side scores.
##
## Note: in self-play, two agents share one env. Each agent only
## sees the ball + its own paddle. The env is responsible for
## spawning the ball and tracking scores.
class_name PongAgent
extends RLAgent

const OBS_DIM := 5
const ACTION_DIM := 1
const PADDLE_SPEED := 400.0
const PADDLE_HALF_HEIGHT := 40.0
const ARENA_HEIGHT := 200.0
const ARENA_WIDTH := 320.0
# B5 fix: clamp paddle Y so it can't leave the arena
const PADDLE_Y_LIMIT := ARENA_HEIGHT / 2.0 - PADDLE_HALF_HEIGHT  # 100 - 40 = 60

@export var paddle_path: NodePath = ^"../LeftPaddle"
@export var ball_path: NodePath = ^"../Ball"

enum Side { LEFT, RIGHT }
@export var side: PongAgent.Side = PongAgent.Side.LEFT

var paddle: RLResettableBody2D
var ball: RigidBody2D

var _initial_paddle_pos: Vector2
var _reward: float = 0.0
var _done: bool = false


func _setup() -> void:
	paddle = get_node(paddle_path) as RLResettableBody2D
	ball = get_node(ball_path) as RigidBody2D
	_initial_paddle_pos = paddle.position


func get_observation() -> PackedFloat32Array:
	var obs := PackedFloat32Array()
	obs.resize(OBS_DIM)
	obs[0] = clampf(ball.position.x / ARENA_WIDTH, -1.0, 1.0)
	obs[1] = clampf(ball.position.y / ARENA_HEIGHT, -1.0, 1.0)
	obs[2] = clampf(ball.linear_velocity.x / 300.0, -1.0, 1.0)
	obs[3] = clampf(ball.linear_velocity.y / 300.0, -1.0, 1.0)
	obs[4] = clampf(paddle.position.y / ARENA_HEIGHT, -1.0, 1.0)
	return obs


func set_action(action: PackedFloat32Array) -> void:
	if action.is_empty():
		return
	var v: float = clampf(action[0], -1.0, 1.0) * PADDLE_SPEED
	# B5 fix: clamp paddle position so it can't leave the arena.
	# If at limit and trying to move further, zero the velocity.
	var current_y: float = paddle.position.y
	if current_y <= -PADDLE_Y_LIMIT and v < 0.0:
		v = 0.0
	elif current_y >= PADDLE_Y_LIMIT and v > 0.0:
		v = 0.0
	paddle.set_kinematic_velocity(Vector2(0.0, v))


func get_reward() -> float:
	return _reward


func is_done() -> bool:
	return _done


## Called by the env when a scoring event happens.
func on_score(scorer_side: int) -> void:
	if scorer_side == side:
		_reward = 1.0
	else:
		_reward = -1.0
	_done = true


func reset() -> void:
	_reward = 0.0
	_done = false
	paddle.request_reset(
		Transform2D(0.0, _initial_paddle_pos),
		Vector2.ZERO,
		0.0
	)


func get_action_dim() -> int:
	return ACTION_DIM


func get_obs_dim() -> int:
	return OBS_DIM
