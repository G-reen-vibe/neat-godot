extends Node
## Diagnostic test for Pong: check if the ball bounces off the paddle.
## Forces the ball to move LEFT toward paddle A.
##
## Run with: godot --headless --path . res://tests/test_pong_collision.tscn

const EnvScene: PackedScene = preload("res://environments/pong/pong_environment.tscn")

var _env: PongEnvironment
var _frame: int = 0
var _log: Array = []

func _ready() -> void:
        print("=== test_pong_collision: ball-paddle collision diagnostic ===")
        var sv := SubViewport.new()
        sv.world_2d = World2D.new()
        sv.size = Vector2i(64, 64)
        sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
        add_child(sv)
        _env = EnvScene.instantiate()
        sv.add_child(_env)
        _env.input_node_ids = [0, 1, 2, 3, 4, 5]
        _env.bias_node_id = 6
        _env.output_node_id = 7
        _env.points_to_win = 5
        _env.set_player_b(null)
        _env.set_forward_mode("topological")
        await get_tree().process_frame
        var rng := RandomNumberGenerator.new()
        rng.seed = 42
        _env.reset(null, rng)
        # Force the ball to move LEFT toward paddle A.
        _env._ball.linear_velocity = Vector2(-3.0, 0.0)
        print("  Ball initial pos: ", _env._ball.position)
        print("  Ball initial vel (forced): ", _env._ball.linear_velocity)
        print("  Ball mass: ", _env._ball.mass)
        print("  PaddleA pos: ", _env._paddle_a.position)
        print("  PaddleA type: ", _env._paddle_a.get_class())
        set_physics_process(true)

func _physics_process(_delta: float) -> void:
        if _env == null or not is_instance_valid(_env):
                set_physics_process(false)
                _print_results()
                return
        _frame += 1
        if _frame <= 60:
                var bx: float = _env._ball.position.x
                var vx: float = _env._ball.linear_velocity.x
                if _frame % 3 == 0 or absf(bx - _env._paddle_a.position.x) < 0.3:
                        _log.append("  frame %3d: ball_x=%.4f  ball_vx=%.4f  hits_a=%d  score=%d-%d  done=%s" % [
                                _frame, bx, vx, _env._hits_a, _env._score_a, _env._score_b, _env._done])
        if _env._done or _frame >= 60:
                set_physics_process(false)
                _print_results()

func _print_results() -> void:
        for line in _log:
                print(line)
        print("\n  Final: ball_x=%.4f  ball_vx=%.4f  hits_a=%d  score=%d-%d  done=%s" % [
                _env._ball.position.x, _env._ball.linear_velocity.x,
                _env._hits_a, _env._score_a, _env._score_b, _env._done])
        if _env._hits_a > 0:
                print("  *** OK: Ball bounced off paddle A (hits_a=%d). ***" % _env._hits_a)
        elif _env._score_b > 0:
                print("  *** FAIL: Ball passed through paddle A and scored for B! ***")
        else:
                print("  *** WARN: Ball didn't reach paddle A yet. ***")
        get_tree().quit(0)
