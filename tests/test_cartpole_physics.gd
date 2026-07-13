extends Node
## Diagnostic test for CartPole physics: check if the pole actually falls
## under the current project gravity setting.
##
## Creates a CartPole env, applies NO action (just lets gravity work),
## and logs the pole rotation over 100 physics frames. If the pole barely
## moves, gravity is too weak.
##
## Run with: godot --headless --path . res://tests/test_cartpole_physics.tscn

const EnvScene: PackedScene = preload("res://environments/cartpole/cartpole_environment.tscn")

var _env: CartPoleEnvironment
var _frame: int = 0
var _log: Array = []

func _ready() -> void:
        print("=== test_cartpole_physics: pole fall diagnostic ===")
        print("  Project gravity: ", ProjectSettings.get_setting("physics/2d/default_gravity"))
        print("  Engine.physics_ticks_per_second: ", Engine.physics_ticks_per_second)
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
        await get_tree().process_frame  # let _ready run
        var rng := RandomNumberGenerator.new()
        rng.seed = 42
        _env.reset(null, rng)
        print("  Initial pole rotation: %.6f rad (%.2f deg)" % [_env._pole.rotation, rad_to_deg(_env._pole.rotation)])
        print("  Cart mass: ", _env._cart.mass, "  Pole mass: ", _env._pole.mass)
        print("  Pole gravity_scale: ", _env._pole.gravity_scale)
        print("  Cart gravity_scale: ", _env._cart.gravity_scale)
        set_physics_process(true)

func _physics_process(_delta: float) -> void:
        if _env == null or not is_instance_valid(_env):
                set_physics_process(false)
                _print_results()
                return
        _frame += 1
        # Apply NO action - just let gravity work.
        # _env._physics_process runs automatically and increments _steps.
        if _frame <= 100:
                if _frame % 10 == 0 or _frame <= 5:
                        var theta: float = _env._pole.rotation
                        var x: float = _env._cart.position.x - _env._initial_cart_pos.x
                        var theta_dot: float = _env._pole.angular_velocity
                        _log.append("  frame %3d: theta=%.6f rad (%.2f deg)  theta_dot=%.4f  x=%.4f  done=%s" % [
                                _frame, theta, rad_to_deg(theta), theta_dot, x, _env._done])
        if _env._done or _frame >= 100:
                set_physics_process(false)
                _print_results()

func _print_results() -> void:
        for line in _log:
                print(line)
        var final_theta: float = _env._pole.rotation
        print("\n  Final pole rotation: %.6f rad (%.2f deg)" % [final_theta, rad_to_deg(final_theta)])
        print("  Steps: %d  Done: %s" % [_env._steps, _env._done])
        if absf(final_theta) < 0.01:
                print("\n  *** FAIL: Pole barely moved in 100 frames. Gravity is too weak! ***")
        elif absf(final_theta) < 0.20943951:
                print("\n  *** WARN: Pole moved but didn't reach threshold (12 deg). May need more frames or stronger gravity. ***")
        else:
                print("\n  *** OK: Pole fell past threshold. Gravity is sufficient. ***")
        get_tree().quit(0)
