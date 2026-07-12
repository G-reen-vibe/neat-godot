## Pong environment where the genome controls the left paddle.
##
## Tournament mode: the genome plays against an opponent genome (the right
## paddle). If no opponent is provided, the right paddle is nonmoving.
##
## Fitness: scored per rally. +1 for hitting the ball back, +5 for winning
## a point (opponent misses), -2 for losing a point (you miss).
##
## State inputs (6): ball_x, ball_y, ball_vx, ball_vy, own_paddle_y, opp_paddle_y
## Output (1): paddle direction (positive = down, negative = up; tanh).
##
## First to N points wins the match (default 5). Match ends at step cap if no winner.
class_name PongEnvironment
extends NeatEnvironment

const FIELD_WIDTH: float = 4.0
const FIELD_HEIGHT: float = 3.0
const PADDLE_HEIGHT: float = 0.5
const PADDLE_WIDTH: float = 0.08
const PADDLE_SPEED: float = 4.0
const BALL_SPEED: float = 4.0
const BALL_RADIUS: float = 0.05
const PADDLE_MARGIN: float = 0.1
const POINTS_TO_WIN: int = 5
const MAX_STEPS: int = 1200

# Network IO config.
var input_node_ids: Array[int] = []
var bias_node_id: int = -1
var output_node_id: int = -1

# Player genomes (genome A is "us", genome B is the opponent). Either may be
# null (the opponent is null = nonmoving paddle; player A should never be null
# when used by the evaluator).
var player_a: Genome = null
var player_b: Genome = null

# State.
var _ball_x: float = 0.0
var _ball_y: float = 0.0
var _ball_vx: float = 0.0
var _ball_vy: float = 0.0
var _paddle_a_y: float = 0.0  # left paddle (player A)
var _paddle_b_y: float = 0.0  # right paddle (player B)
var _score_a: int = 0
var _score_b: int = 0
var _steps: int = 0
var _done: bool = false
var _hits_a: int = 0  # successful returns by A
var _hits_b: int = 0

func _init(p_input_ids: Array[int] = [], p_bias_id: int = -1, p_output_id: int = -1) -> void:
        input_node_ids = p_input_ids
        bias_node_id = p_bias_id
        output_node_id = p_output_id

func set_player_a(g: Genome) -> void:
        player_a = g

func set_player_b(g: Genome) -> void:
        player_b = g

func reset(rng: RandomNumberGenerator = null) -> void:
        _ball_x = 0.0
        _ball_y = 0.0
        # Random initial direction.
        var dir: float = 1.0
        if rng != null:
                dir = 1.0 if rng.randf() < 0.5 else -1.0
                _ball_vy = rng.randf_range(-0.8, 0.8)
        else:
                _ball_vy = randf_range(-0.8, 0.8)
        _ball_vx = dir * BALL_SPEED * 0.7
        _paddle_a_y = 0.0
        _paddle_b_y = 0.0
        _score_a = 0
        _score_b = 0
        _steps = 0
        _done = false
        _hits_a = 0
        _hits_b = 0

func initial_state() -> Dictionary:
        return _build_state_dict()

func _build_state_dict() -> Dictionary:
        # Normalize to [-1, 1] for the network.
        var d: Dictionary = {}
        d[input_node_ids[0]] = _ball_x / (FIELD_WIDTH * 0.5)
        d[input_node_ids[1]] = _ball_y / (FIELD_HEIGHT * 0.5)
        d[input_node_ids[2]] = _ball_vx / BALL_SPEED
        d[input_node_ids[3]] = _ball_vy / BALL_SPEED
        d[input_node_ids[4]] = _paddle_a_y / (FIELD_HEIGHT * 0.5)
        d[input_node_ids[5]] = _paddle_b_y / (FIELD_HEIGHT * 0.5)
        return d

func interpret_output(output_a: Dictionary, output_b: Dictionary = {}) -> Dictionary:
        var a_action: float = float(output_a.get(output_node_id, 0.0))
        var b_action: float = 0.0
        if not output_b.is_empty():
                b_action = float(output_b.get(output_node_id, 0.0))
        return {"a": a_action, "b": b_action}

func step(action: Dictionary) -> Dictionary:
        var a_action: float = float(action.get("a", 0.0))
        var b_action: float = float(action.get("b", 0.0))
        # Move paddles.
        _paddle_a_y += clampf(a_action, -1.0, 1.0) * PADDLE_SPEED * 0.016
        _paddle_b_y += clampf(b_action, -1.0, 1.0) * PADDLE_SPEED * 0.016
        # Clamp paddles.
        var half_p: float = FIELD_HEIGHT * 0.5 - PADDLE_HEIGHT * 0.5
        _paddle_a_y = clampf(_paddle_a_y, -half_p, half_p)
        _paddle_b_y = clampf(_paddle_b_y, -half_p, half_p)
        # Move ball.
        _ball_x += _ball_vx * 0.016
        _ball_y += _ball_vy * 0.016
        # Bounce off top/bottom walls.
        if _ball_y > FIELD_HEIGHT * 0.5 - BALL_RADIUS:
                _ball_y = FIELD_HEIGHT * 0.5 - BALL_RADIUS
                _ball_vy = -absf(_ball_vy)
        elif _ball_y < -FIELD_HEIGHT * 0.5 + BALL_RADIUS:
                _ball_y = -FIELD_HEIGHT * 0.5 + BALL_RADIUS
                _ball_vy = absf(_ball_vy)
        # Paddle A (left, x = -FIELD_WIDTH/2 + margin).
        var paddle_a_x: float = -FIELD_WIDTH * 0.5 + PADDLE_MARGIN
        if _ball_x < paddle_a_x + PADDLE_WIDTH and _ball_x > paddle_a_x - BALL_RADIUS and _ball_vx < 0:
                if absf(_ball_y - _paddle_a_y) < PADDLE_HEIGHT * 0.5 + BALL_RADIUS:
                        _ball_x = paddle_a_x + PADDLE_WIDTH
                        _ball_vx = absf(_ball_vx)
                        # Add some english based on where it hit.
                        _ball_vy += (_ball_y - _paddle_a_y) * 4.0
                        _ball_vy = clampf(_ball_vy, -BALL_SPEED, BALL_SPEED)
                        _hits_a += 1
        # Paddle B (right, x = +FIELD_WIDTH/2 - margin).
        var paddle_b_x: float = FIELD_WIDTH * 0.5 - PADDLE_MARGIN
        if _ball_x > paddle_b_x - PADDLE_WIDTH and _ball_x < paddle_b_x + BALL_RADIUS and _ball_vx > 0:
                if absf(_ball_y - _paddle_b_y) < PADDLE_HEIGHT * 0.5 + BALL_RADIUS:
                        _ball_x = paddle_b_x - PADDLE_WIDTH
                        _ball_vx = -absf(_ball_vx)
                        _ball_vy += (_ball_y - _paddle_b_y) * 4.0
                        _ball_vy = clampf(_ball_vy, -BALL_SPEED, BALL_SPEED)
                        _hits_b += 1
        # Scoring.
        if _ball_x < -FIELD_WIDTH * 0.5:
                # B scores.
                _score_b += 1
                _reset_ball(1.0)
        elif _ball_x > FIELD_WIDTH * 0.5:
                # A scores.
                _score_a += 1
                _reset_ball(-1.0)
        _steps += 1
        if _score_a >= POINTS_TO_WIN or _score_b >= POINTS_TO_WIN:
                _done = true
        if _steps >= MAX_STEPS:
                _done = true
        return _build_state_dict()

func _reset_ball(direction: float) -> void:
        _ball_x = 0.0
        _ball_y = 0.0
        _ball_vx = direction * BALL_SPEED * 0.7
        _ball_vy = randf_range(-0.5, 0.5)

func is_done() -> bool:
        return _done

func current_fitness() -> float:
        # Fitness from player A's perspective.
        var score: float = 0.0
        score += float(_hits_a) * 1.0
        score += float(_score_a) * 5.0
        score -= float(_score_b) * 2.0
        # Bonus for winning.
        if _score_a > _score_b:
                score += 10.0
        # Small bonus for lasting longer (rallies).
        score += float(_steps) * 0.01
        return maxf(0.0, score)

func is_solved() -> bool:
        return _score_a >= POINTS_TO_WIN and _score_a > _score_b

func view_type() -> String:
        return "2d"

func get_visual_state() -> Dictionary:
        return {
                "ball_x": _ball_x,
                "ball_y": _ball_y,
                "ball_vx": _ball_vx,
                "ball_vy": _ball_vy,
                "paddle_a_y": _paddle_a_y,
                "paddle_b_y": _paddle_b_y,
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
                "points_to_win": POINTS_TO_WIN,
                "hits_a": _hits_a,
                "hits_b": _hits_b,
        }
