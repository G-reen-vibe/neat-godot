## Pong environment using real Godot 2D physics.
##
## Scene structure (see pong_environment.tscn):
##   Node2D (root, this script)
##     StaticBody2D (top wall)
##     StaticBody2D (bottom wall)
##     AnimatableBody2D (paddle A - left, player-controlled, sync_to_physics=false)
##     AnimatableBody2D (paddle B - right, opponent-controlled, sync_to_physics=false)
##     TeleportBody2D (ball)  -- contact_monitor enabled for hit tracking
##     Area2D (left score zone)
##     Area2D (right score zone)
##
## Paddles are AnimatableBody2D with sync_to_physics=false. Setting position
## directly works reliably for AnimatableBody2D when sync_to_physics is off,
## and collisions use the current-frame transform (no 1-frame lag).
##
## The ball is a TeleportBody2D so resets are reliable (see teleport_body_2d.gd).
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
const DEFAULT_MAX_STEPS: int = 1200

# Configurable: points needed to win a match.
var points_to_win: int = 5
# Configurable: max steps per episode (set by env_setup_fn).
var _max_steps: int = DEFAULT_MAX_STEPS

# Player genomes (genome A is "us", genome B is the opponent). Either may be
# null (opponent null = nonmoving paddle).
var player_a: Genome = null
var player_b: Genome = null

@onready var _paddle_a: AnimatableBody2D = $PaddleA
@onready var _paddle_b: AnimatableBody2D = $PaddleB
@onready var _ball: TeleportBody2D = $Ball
@onready var _left_zone: Area2D = $LeftScoreZone
@onready var _right_zone: Area2D = $RightScoreZone

var _score_a: int = 0
var _score_b: int = 0
var _steps: int = 0
var _done: bool = false
var _hits_a: int = 0
var _hits_b: int = 0
# Forward mode used for player B's forward pass (set by env_setup_fn).
var forward_mode: String = "topological"

var _initial_ball_pos: Vector2
var _initial_paddle_a_pos: Vector2
var _initial_paddle_b_pos: Vector2
var _ball_pending_reset: bool = false
var _ball_reset_dir: float = 1.0
var _prev_ball_vx_sign: int = 0  # for hit detection backup

func _ready() -> void:
	_initial_ball_pos = _ball.position
	_initial_paddle_a_pos = _paddle_a.position
	_initial_paddle_b_pos = _paddle_b.position
	# Connect ball body_entered for hit tracking.
	if not _ball.body_entered.is_connected(_on_ball_body_entered):
		_ball.body_entered.connect(_on_ball_body_entered)

func set_max_steps(p: int) -> void:
	_max_steps = p

## Freeze/unfreeze the ball RigidBody2D. Paddles are AnimatableBody2D (don't
## have freeze; they don't move unless we set their position). Used by RunScreen
## to prevent the live env's ball from being affected by SceneEvaluator
## physics steps during training.
##
## NOTE: When frozen, [method request_teleport] still works, so [method reset]
## can be called on a frozen env and the ball will snap to center reliably.
func set_bodies_frozen(frozen: bool) -> void:
	_ball.freeze = frozen

func set_player_a(g: Genome) -> void:
	player_a = g

func set_player_b(g: Genome) -> void:
	player_b = g

func set_forward_mode(m: String) -> void:
	forward_mode = m

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
	_prev_ball_vx_sign = 0
	# Paddles are AnimatableBody2D — direct position assignment is reliable
	# when sync_to_physics=false.
	_paddle_a.position = _initial_paddle_a_pos
	_paddle_b.position = _initial_paddle_b_pos
	# Ball is a TeleportBody2D — use request_teleport for reliable reset.
	# Initial ball direction.
	var dir: float = 1.0
	var vel_y: float = 0.0
	if rng != null:
		dir = 1.0 if rng.randf() < 0.5 else -1.0
		vel_y = rng.randf_range(-0.8, 0.8)
	else:
		vel_y = randf_range(-0.8, 0.8)
	var initial_vel: Vector2 = Vector2(dir * BALL_SPEED * 0.7, vel_y)
	_ball.request_teleport(Transform2D(0.0, _initial_ball_pos), initial_vel, 0.0)
	_prev_ball_vx_sign = sign(initial_vel.x)

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
## Paddles are AnimatableBody2D, moved by setting position directly.
## Uses fixed dt = 1/60 (physics tick rate is always 60 Hz, no speedup).
func apply_action(action: Dictionary) -> void:
	if _done:
		return
	var dt: float = 1.0 / 60.0
	var a_action: float = float(action.get("a", 0.0))
	_paddle_a.position.y += clampf(a_action, -1.0, 1.0) * PADDLE_SPEED * dt
	# Move paddle B (if opponent exists).
	if player_b != null:
		var state_b: Dictionary = _build_state_dict_for_b()
		var output_b: Dictionary = player_b.forward(state_b, forward_mode)
		var b_action: float = float(output_b.get(output_node_id, 0.0))
		_paddle_b.position.y += clampf(b_action, -1.0, 1.0) * PADDLE_SPEED * dt
	# Clamp paddles to field.
	var half_p: float = FIELD_HEIGHT * 0.5 - PADDLE_HEIGHT * 0.5
	_paddle_a.position.y = clampf(_paddle_a.position.y, -half_p, half_p)
	_paddle_b.position.y = clampf(_paddle_b.position.y, -half_p, half_p)

func _on_ball_body_entered(body: Node) -> void:
	if _done:
		return
	if body == _paddle_a:
		_hits_a += 1
	elif body == _paddle_b:
		_hits_b += 1

func is_done() -> bool:
	return _done

## Step the env's game logic. Called from _physics_process.
func step_env() -> void:
	if _done:
		return
	_steps += 1
	# Handle ball reset (after a goal). Must happen BEFORE score check
	# to prevent multi-score in a single frame. The reset is done via
	# request_teleport so the physics server honors it reliably.
	if _ball_pending_reset:
		var reset_vel: Vector2 = Vector2(_ball_reset_dir * BALL_SPEED * 0.7, randf_range(-0.5, 0.5))
		_ball.request_teleport(Transform2D(0.0, _initial_ball_pos), reset_vel, 0.0)
		_ball_pending_reset = false
		_prev_ball_vx_sign = sign(reset_vel.x)
	# Backup hit detection: if ball vx sign flipped near a paddle, count a hit.
	var cur_vx_sign: int = sign(_ball.linear_velocity.x)
	if cur_vx_sign != 0 and _prev_ball_vx_sign != 0 and cur_vx_sign != _prev_ball_vx_sign:
		var abs_vx: float = absf(_ball.linear_velocity.x)
		if absf(_ball.position.x - _paddle_a.position.x) < PADDLE_WIDTH * 4.0 + abs_vx * 0.05:
			if cur_vx_sign > 0 and _prev_ball_vx_sign < 0:
				_hits_a += 1
		elif absf(_ball.position.x - _paddle_b.position.x) < PADDLE_WIDTH * 4.0 + abs_vx * 0.05:
			if cur_vx_sign < 0 and _prev_ball_vx_sign > 0:
				_hits_b += 1
	_prev_ball_vx_sign = cur_vx_sign
	# Check score zones. Setting _ball_pending_reset ensures the ball is
	# recentered on the NEXT frame (via teleport), preventing multi-score.
	if _ball.position.x < -FIELD_WIDTH * 0.5:
		_score_b += 1
		_ball_pending_reset = true
		_ball_reset_dir = 1.0
	elif _ball.position.x > FIELD_WIDTH * 0.5:
		_score_a += 1
		_ball_pending_reset = true
		_ball_reset_dir = -1.0
	# Clamp ball speed (avoid runaway from bouncy physics).
	var speed: float = _ball.linear_velocity.length()
	if speed > BALL_SPEED * 1.5:
		_ball.linear_velocity = _ball.linear_velocity.normalized() * BALL_SPEED * 1.5
	# Check win condition.
	if _score_a >= points_to_win or _score_b >= points_to_win:
		_done = true
	elif _steps >= _max_steps:
		_done = true

func _physics_process(_delta: float) -> void:
	step_env()

func current_fitness() -> float:
	# Reward hits heavily (the main skill), reward scoring, penalize being scored on.
	# Add small survival bonus so early generations still progress.
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
		"max_steps": _max_steps,
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
