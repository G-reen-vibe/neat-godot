## Pong environment: ball + 2 paddles + scoring.
##
## Scene graph (see pong_env.tscn):
##   PongEnv (Node2D, RLEnvironment)
##     ├── TopWall (StaticBody2D)
##     ├── BottomWall (StaticBody2D)
##     ├── LeftPaddle (RLResettableBody2D, kinematic)
##     ├── RightPaddle (RLResettableBody2D, kinematic)
##     ├── Ball (RLResettableBody2D, dynamic)
##     ├── LeftAgent (Node2D, PongAgent)
##     ├── RightAgent (Node2D, PongAgent)
##     └── Camera2D
##
## Coordinate convention:
##   Arena is 320 wide (x: -160 to 160) and 200 tall (y: -100 to 100).
##   Left paddle at x=-150, right paddle at x=+150.
##   Ball spawns at center (0, 0).
class_name PongEnv
extends RLEnvironment

const OBS_DIM := 5
const ACTION_DIM := 1
const ARENA_WIDTH := 320.0
const ARENA_HEIGHT := 200.0
const PADDLE_SPEED := 400.0
const BALL_SPEED := 200.0
const PADDLE_HALF_HEIGHT := 40.0

var _left_agent: PongAgent
var _right_agent: PongAgent
var _ball: RLResettableBody2D


func _ready() -> void:
	env_name = "pong"
	super._ready()


func _setup() -> void:
	_left_agent = get_node("LeftAgent") as PongAgent
	_right_agent = get_node("RightAgent") as PongAgent
	_left_agent._setup()
	_right_agent._setup()
	_ball = get_node("Ball") as RLResettableBody2D


func _on_reset() -> void:
	# Ball starts at center with random direction
	var angle: float = randf_range(-PI / 4.0, PI / 4.0)
	var dir: Vector2 = Vector2(cos(angle), sin(angle))
	if randf() < 0.5:
		dir.x = -dir.x
	var vel: Vector2 = dir * BALL_SPEED
	_ball.request_reset(
		Transform2D(0.0, Vector2.ZERO),
		vel,
		0.0
	)


func _on_physics_step(_delta: float) -> void:
	# B8 fix: maintain constant ball speed. Physics materials with
	# bounce=1.0 still lose energy in practice; renormalize velocity
	# each step to keep the game from stalling.
	var vel := _ball.linear_velocity
	var speed := vel.length()
	if speed > 1.0 and absf(speed - BALL_SPEED) > 5.0:
		_ball.linear_velocity = vel.normalized() * BALL_SPEED

	# Check for scoring
	var ball_x: float = _ball.position.x
	if ball_x < -ARENA_WIDTH / 2.0:
		# Right scores
		_left_agent.on_score(PongAgent.Side.RIGHT)
		_right_agent.on_score(PongAgent.Side.RIGHT)
	elif ball_x > ARENA_WIDTH / 2.0:
		# Left scores
		_left_agent.on_score(PongAgent.Side.LEFT)
		_right_agent.on_score(PongAgent.Side.LEFT)


func get_action_dim() -> int:
	return ACTION_DIM


func get_obs_dim() -> int:
	return OBS_DIM
