extends Node
## Diagnostic test: verify the live env's cart actually moves when driven
## from _physics_process (the same way RunScreen._physics_process drives it).
##
## This test catches the bug where apply_central_impulse is called from
## _process (render frame) instead of _physics_process (physics tick),
## causing the impulse to be silently lost and the cart to appear frozen.
##
## Run with: godot --headless --path . res://tests/test_live_env_drive.tscn

const EnvScene: PackedScene = preload("res://environments/cartpole/cartpole_environment.tscn")

var _env: CartPoleEnvironment
var _frame: int = 0
var _initial_x: float = 0.0
var _log: Array = []

func _ready() -> void:
        print("=== test_live_env_drive: verify cart moves when driven from _physics_process ===")
        var sv := SubViewport.new()
        sv.world_2d = World2D.new()
        sv.size = Vector2i(64, 64)
        sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
        add_child(sv)
        _env = EnvScene.instantiate()
        sv.add_child(_env)
        _env.input_node_ids = [0, 1, 2, 3]
        _env.bias_node_id = 4
        _env.output_node_id = 5
        _env.set_max_steps(500)
        await get_tree().process_frame
        var rng := RandomNumberGenerator.new()
        rng.seed = 42
        _env.reset(null, rng)
        _initial_x = _env._cart.position.x
        print("  Initial cart x: ", _initial_x)
        print("  Physics ticks/sec: ", Engine.physics_ticks_per_second)
        print("  Time scale: ", Engine.time_scale)
        set_physics_process(true)

func _physics_process(_delta: float) -> void:
        if _env == null or not is_instance_valid(_env):
                set_physics_process(false)
                _print_results()
                return
        _frame += 1
        # Drive the env the same way RunScreen._physics_process does:
        # check is_done, apply action every physics tick.
        if _env.is_done():
                var rng := RandomNumberGenerator.new()
                rng.seed = 42
                _env.reset(null, rng)
                return
        # Apply a constant "push right" action.
        _env.apply_action({"action": 1})
        if _frame % 20 == 0 or _frame <= 5:
                var x: float = _env._cart.position.x - _initial_x
                var theta: float = _env._pole.rotation
                _log.append("  frame %3d: x=%.4f  theta=%.4f  steps=%d  done=%s" % [
                        _frame, x, theta, _env._steps, _env._done])
        if _frame >= 200:
                set_physics_process(false)
                _print_results()

func _print_results() -> void:
        for line in _log:
                print(line)
        var final_x: float = _env._cart.position.x - _initial_x
        print("\n  Final cart x offset: %.4f" % final_x)
        print("  Final steps: %d" % _env._steps)
        if absf(final_x) > 0.01:
                print("  *** OK: Cart moved (offset=%.4f). Impulse is taking effect. ***" % final_x)
        else:
                print("  *** FAIL: Cart did not move! Impulse is being lost. ***")
        get_tree().quit(0)
