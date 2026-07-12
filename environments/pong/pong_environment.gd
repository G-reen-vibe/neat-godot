## Pong environment using real Godot 2D physics.
##
## Scene structure (see pong_environment.tscn):
##   Node2D (root, this script)
##     StaticBody2D (top wall)
##     StaticBody2D (bottom wall)
##     CharacterBody2D (paddle A - left, player-controlled)
##     CharacterBody2D (paddle B - right, opponent-controlled)
##     RigidBody2D (ball)
##     Area2D (left score zone)
##     Area2D (right score zone)
##
## Tournament mode: the genome controls paddle A. An optional opponent genome
## controls paddle B. If no opponent, paddle B does not move.
##
## State (6 inputs): ball_x, ball_y, ball_vx, ball_vy, own_paddle_y, opp_paddle_y
## Action (1 output): paddle direction (positive = down, negative = up; tanh).
##
## First to N points wins the match. Match ends at step cap if no winner.
class_name PongEnvironment
extends NeatPhysicsEnvironment

const FIELD_WIDTH: float = 4.0
const FIELD_HEIGHT: float = 3.0
const PADDLE_HEIGHT: float = 0.5
const PADDLE_WIDTH: float = 0.08
const PADDLE_SPEED: float = 4.0
const BALL_SPEED: float = 4.0
const BALL_RADIUS: float = 0.05
const PADDLE_MARGIN: float = 0.1
const MAX_STEPS: int = 1200

# Configurable: points needed to win a match.
var points_to_win: int = 5

# Player genomes (genome A is "us", genome B is the opponent). Either may be
# null (opponent null = nonmoving paddle).
var player_a: Genome = null
var player_b: Genome = null

@onready var _paddle_a: CharacterBody2D = $PaddleA
@onready var _paddle_b: CharacterBody2D = $PaddleB
@onready var _ball: RigidBody2D = $Ball
@onready var _left_zone: Area2D = $LeftScoreZone
@onready var _right_zone: Area2D = $RightScoreZone

var _score_a: int = 0
var _score_b: int = 0
var _steps: int = 0
var _done: bool = false
var _hits_a: int = 0
var _hits_b: int = 0

var _initial_ball_pos: Vector2
var _initial_paddle_a_pos: Vector2
var _initial_paddle_b_pos: Vector2
var _ball_pending_reset: bool = false
var _ball_reset_dir: float = 1.0

func _ready() -> void:
	_initial_ball_pos = _ball.position
	_initial_paddle_a_pos = _paddle_a.position
	_initial_paddle_b_pos = _paddle_b.position

func set_max_steps(_p: int) -> void:
	# Pong uses its own MAX_STEPS const; ignore.
	pass

func set_player_a(g: Genome) -> void:
	player_a = g

func set_player_b(g: Genome) -> void:
	player_b = g

func reset(p_genome = null, rng: RandomNumberGenerator = null) -> void:
	super.reset(p_genome, rng)
	player_a = p_genome
	_score_a = 0
	_score_b = 0
	_steps = 0
	_done = false
	_hits_a = 0
	_hits_b = 0
	_ball_pending_reset = false
	_paddle_a.position = _initial_paddle_a_pos
	_paddle_a.velocity = Vector2.ZERO
	_paddle_b.position = _initial_paddle_b_pos
	_paddle_b.velocity = Vector2.ZERO
	_ball.position = _initial_ball_pos
	_ball.linear_velocity = Vector2.ZERO
	_ball.angular_velocity = 0.0
	# Initial ball direction.
	var dir: float = 1.0
	if rng != null:
		dir = 1.0 if rng.randf() < 0.5 else -1.0
		_ball.linear_velocity = Vector2(dir * BALL_SPEED * 0.7, rng.randf_range(-0.8, 0.8))
	else:
		_ball.linear_velocity = Vector2(dir * BALL_SPEED * 0.7, randf_range(-0.8, 0.8))

func get_state() -> Dictionary:
	return _build_state_dict_for_a()

func _build_state_dict_for_a() -> Dictionary:
	var d: Dictionary = {}
	d[input_node_ids[0]] = _ball.position.x / (FIELD_WIDTH * 0.5)
	d[input_node_ids[1]] = _ball.position.y / (FIELD_HEIGHT * 0.5)
	d[input_node_ids[2]] = _ball.linear_velocity.x / BALL_SPEED
	d[input_node_ids[3]] = _ball.linear_velocity.y / BALL_SPEED
	d[input_node_ids[4]] = _paddle_a.position.y / (FIELD_HEIGHT * 0.5)
	d[input_node_ids[5]] = _paddle_b.position.y / (FIELD_HEIGHT * 0.5)
	return d

func _build_state_dict_for_b() -> Dictionary:
	var d: Dictionary = {}
	d[input_node_ids[0]] = -_ball.position.x / (FIELD_WIDTH * 0.5)
	d[input_node_ids[1]] = _ball.position.y / (FIELD_HEIGHT * 0.5)
	d[input_node_ids[2]] = -_ball.linear_velocity.x / BALL_SPEED
	d[input_node_ids[3]] = _ball.linear_velocity.y / BALL_SPEED
	d[input_node_ids[4]] = _paddle_b.position.y / (FIELD_HEIGHT * 0.5)
	d[input_node_ids[5]] = _paddle_a.position.y / (FIELD_HEIGHT * 0.5)
	return d

func get_state_for_player(player: int) -> Dictionary:
	if player == 1:
		return _build_state_dict_for_b()
	return _build_state_dict_for_a()

func interpret_output(output: Dictionary) -> Dictionary:
	var a_action: float = float(output.get(output_node_id, 0.0))
	return {"a": a_action}

## Apply both players' actions. If player_b is set, run its forward pass too.
func apply_action(action: Dictionary) -> void:
	if _done:
		return
	var a_action: float = float(action.get("a", 0.0))
	# Move paddle A.
	var a_vel: Vector2 = Vector2(0, clampf(a_action, -1.0, 1.0) * PADDLE_SPEED)
	_paddle_a.velocity = a_vel
	# Move paddle B (if opponent exists).
	if player_b != null:
		var state_b: Dictionary = _build_state_dict_for_b()
		var output_b: Dictionary = player_b.forward(state_b, "topological")
		var b_action: float = float(output_b.get(output_node_id, 0.0))
		_paddle_b.velocity = Vector2(0, clampf(b_action, -1.0, 1.0) * PADDLE_SPEED)
	else:
		_paddle_b.velocity = Vector2.ZERO

func _physics_process(_delta: float) -> void:
	if _done:
		return
	_steps += 1
	# Move CharacterBody2D paddles.
	_paddle_a.move_and_slide()
	_paddle_b.move_and_slide()
	# Clamp paddles to field.
	var half_p: float = FIELD_HEIGHT * 0.5 - PADDLE_HEIGHT * 0.5
	_paddle_a.position.y = clampf(_paddle_a.position.y, -half_p, half_p)
	_paddle_b.position.y = clampf(_paddle_b.position.y, -half_p, half_p)
	# Handle ball reset (after a goal).
	if _ball_pending_reset:
		_ball.position = _initial_ball_pos
		_ball.linear_velocity = Vector2(_ball_reset_dir * BALL_SPEED * 0.7, randf_range(-0.5, 0.5))
		_ball.angular_velocity = 0.0
		_ball_pending_reset = false
	# Check score zones.
	if _ball.position.x < -FIELD_WIDTH * 0.5:
		_score_b += 1
		_ball_pending_reset = true
		_ball_reset_dir = 1.0
	elif _ball.position.x > FIELD_WIDTH * 0.5:
		_score_a += 1
		_ball_pending_reset = true
		_ball_reset_dir = -1.0
	# Check win condition.
	if _score_a >= points_to_win or _score_b >= points_to_win:
		_done = true
	elif _steps >= MAX_STEPS:
		_done = true

func is_done() -> bool:
	return _done

func current_fitness() -> float:
	var score: float = 0.0
	score += float(_hits_a) * 1.0
	score += float(_score_a) * 5.0
	score -= float(_score_b) * 2.0
	if _score_a > _score_b:
		score += 10.0
	score += float(_steps) * 0.01
	return maxf(0.0, score)

func is_solved() -> bool:
	return _score_a >= points_to_win and _score_a > _score_b

func view_type() -> String:
	return "2d"

func get_visual_state() -> Dictionary:
	return {
		"ball_x": _ball.position.x,
		"ball_y": _ball.position.y,
		"ball_vx": _ball.linear_velocity.x,
		"ball_vy": _ball.linear_velocity.y,
		"paddle_a_y": _paddle_a.position.y,
		"paddle_b_y": _paddle_b.position.y,
		"score_a": _score_a,
		"score_b": _score_b,
		"steps": _steps,
		"max_steps": MAX_STEPS,
		"done": _done,
		"field_width": FIELD_WIDTH,
		"field_height": FIELD_HEIGHT,
		"paddle_height": PADDLE_HEIGHT,
		"paddle_width": PADDLE_WIDTH,
		"paddle_margin": PADDLE_MARGIN,
		"ball_radius": BALL_RADIUS,
		"points_to_win": points_to_win,
		"hits_a": _hits_a,
		"hits_b": _hits_b,
	}
