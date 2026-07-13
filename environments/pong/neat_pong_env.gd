## NEAT adapter for the Pong RL env.
##
## Wraps res://rl/envs/pong/pong_env.tscn.
##
## The RL Pong env has 2 agents (LeftAgent, RightAgent). The NEAT genome
## controls the LeftAgent (primary). The RightAgent (secondary) receives a
## zero action (stationary paddle), so the genome learns to hit the ball
## past a non-moving opponent.
##
## Network IO:
##   Inputs (5): ball x, ball y, ball vx, ball vy, own paddle y
##     (all pre-normalized to [-1, 1] by the RL agent)
##   Outputs (1): paddle velocity in [-1, 1] (tanh), scaled by PADDLE_SPEED
##
## Fitness shaping (in the adapter; the RL env is unmodified):
##   The RL env's per-step reward is sparse: +1 when the opponent misses,
##   -1 when self misses, 0 otherwise. The episode ends on the first score.
##   To give NEAT a denser gradient, we add:
##     +1.0 per paddle hit (detected via ball vx sign change)
##     +0.01 per step survived
##     +5.0 * score_delta (from the RL reward accumulation)
##   All clamped at 0 (no negative fitness).
##
## Done: the RL env's is_done() (first score or max_steps).
class_name NeatPongEnv
extends NeatRLAdapter

const PONG_SCENE: PackedScene = preload("res://rl/envs/pong/pong_env.tscn")

# Drawing constants (in RL env pixel units).
const ARENA_WIDTH := 320.0
const ARENA_HEIGHT := 200.0
const PADDLE_HALF_HEIGHT := 40.0
const PADDLE_WIDTH := 8.0
const BALL_HALF_SIZE := 6.0

# Hit-detection state.
var _hits: int = 0
var _last_ball_vx_sign: float = 0.0
var _steps: int = 0


func _get_rl_env_scene() -> PackedScene:
	return PONG_SCENE


## Primary agent = LeftAgent (index 0). RightAgent (index 1) is secondary.
func _get_primary_agent_index() -> int:
	return 0


func reset(p_genome = null, rng: RandomNumberGenerator = null) -> void:
	super.reset(p_genome, rng)
	_hits = 0
	_last_ball_vx_sign = 0.0
	_steps = 0


func step_env() -> void:
	super.step_env()
	_steps += 1
	# Detect paddle hits via ball vx sign change. The ball only flips vx
	# when it hits a paddle (top/bottom walls flip vy, not vx). Within one
	# episode (which ends on first score), vx sign changes = paddle hits.
	var ball: RigidBody2D = _rl_env.get_node_or_null("Ball") if _rl_env != null else null
	if ball != null:
		var vx: float = ball.linear_velocity.x
		var sign_vx: float = 0.0
		if vx > 1.0:
			sign_vx = 1.0
		elif vx < -1.0:
			sign_vx = -1.0
		if sign_vx != 0.0 and _last_ball_vx_sign != 0.0 and sign_vx != _last_ball_vx_sign:
			_hits += 1
		if sign_vx != 0.0:
			_last_ball_vx_sign = sign_vx


func current_fitness() -> float:
	# _cumulative_fitness (from base adapter) = score delta:
	#   +1 if left scored, -1 if right scored, 0 if no score (time limit).
	var f: float = 0.0
	f += _cumulative_fitness * 5.0
	f += float(_hits) * 1.0
	f += float(_steps) * 0.01
	return maxf(0.0, f)


func get_visual_state() -> Dictionary:
	var ball: RigidBody2D = _rl_env.get_node_or_null("Ball") if _rl_env != null else null
	var left_paddle: RigidBody2D = _rl_env.get_node_or_null("LeftPaddle") if _rl_env != null else null
	var right_paddle: RigidBody2D = _rl_env.get_node_or_null("RightPaddle") if _rl_env != null else null
	var d: Dictionary = {
		"steps": _steps,
		"max_steps": _rl_env.max_steps if _rl_env != null else 0,
		"done": is_done(),
		"field_width": ARENA_WIDTH,
		"field_height": ARENA_HEIGHT,
		"paddle_height": PADDLE_HALF_HEIGHT * 2.0,
		"paddle_width": PADDLE_WIDTH,
		"paddle_margin": 10.0,
		"ball_radius": BALL_HALF_SIZE,
		"hits": _hits,
	}
	if ball != null:
		d["ball_x"] = ball.position.x
		d["ball_y"] = ball.position.y
		d["ball_vx"] = ball.linear_velocity.x
		d["ball_vy"] = ball.linear_velocity.y
	if left_paddle != null:
		d["paddle_a_y"] = left_paddle.position.y
	if right_paddle != null:
		d["paddle_b_y"] = right_paddle.position.y
	# Score approximation: _cumulative_fitness is +1 (left scored) or -1 (right
	# scored) at episode end. Show it as a 1-0 or 0-1 score.
	d["score_a"] = 1 if _cumulative_fitness > 0.5 else 0
	d["score_b"] = 1 if _cumulative_fitness < -0.5 else 0
	return d


func is_solved() -> bool:
	# Pong has no clear "solved" condition; training runs indefinitely.
	return false
