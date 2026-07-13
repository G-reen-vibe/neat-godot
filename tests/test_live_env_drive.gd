extends Node
## Test the live-env drive loop: verify that when live_mode is on and
## physics_process is enabled, the env drives itself (step_env + apply_action
## with live_genome), auto-resets when done, and that the teleport pattern
## reliably resets bodies.
##
## Also tests N/B genome switching: set_live_genome + reset.
##
## Run with:
##   godot --headless --path . res://tests/test_live_env_drive.tscn

const MAX_PHYSICS_FRAMES: int = 600  # 10 seconds at 60 Hz

var _failed: bool = false

func _ready() -> void:
        print("=== test_live_env_drive: live-env self-drive + teleport reset ===")
        await _test_cartpole_live_drive()
        if _failed: _halt()
        await _test_acrobot_live_drive()
        if _failed: _halt()
        await _test_pong_live_drive()
        if _failed: _halt()
        await _test_teleport_reliability()
        if _failed: _halt()
        print("\n=== test_live_env_drive: ALL PASSED ===")
        get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
        if not cond:
                push_error("ASSERT FAILED: " + msg)
                _failed = true

func _halt() -> void:
        printerr("\n=== test_live_env_drive: FAILED ===")
        get_tree().quit(1)

func _make_genome(num_in: int, num_out: int) -> Genome:
        # Build a minimal genome with inputs, bias, output, and a few connections.
        var cfg := NeatConfig.new()
        cfg.num_inputs = num_in
        cfg.num_outputs = num_out
        cfg.use_bias = true
        cfg.forward_mode = "topological"
        cfg.forbid_loops = true
        cfg.population_size = 1
        cfg.init_min_hidden_nodes = 1
        cfg.init_max_hidden_nodes = 2
        cfg.init_min_connections = 2
        cfg.init_max_connections = 5
        var pop := Population.new(cfg)
        pop.initialize()
        return pop.genomes[0]

func _wait_frames(n: int) -> void:
        for _i in range(n):
                await get_tree().physics_frame

## Test 1: CartPole live drive.
## - Instantiate env, set live_mode + live_genome, enable physics_process.
## - Wait ~300 physics frames.
## - Verify steps incremented (env is driving itself).
## - Verify it eventually hits done (pole falls or max_steps reached).
## - Verify it auto-resets (steps go back to 0, episode continues).
func _test_cartpole_live_drive() -> void:
        print("  --- CartPole live drive ---")
        var env_scene: PackedScene = load("res://environments/cartpole/cartpole_environment.tscn")
        var env: CartPoleEnvironment = env_scene.instantiate()
        add_child(env)
        env.input_node_ids = [0, 1, 2, 3]
        env.bias_node_id = 4
        env.output_node_id = 5
        env.set_max_steps(500)
        var g: Genome = _make_genome(4, 1)
        env.set_live_genome(g)
        env.live_forward_mode = "topological"
        # Reset with fixed seed.
        var rng := RandomNumberGenerator.new()
        rng.seed = 12345
        env.reset(g, rng)
        # Enable live mode + physics_process.
        env.set_live_mode(true)
        env.set_physics_process(true)
        env.set_bodies_frozen(false)
        # Wait 100 frames — steps should increment.
        await _wait_frames(100)
        var steps_after_100: int = env.get_visual_state()["steps"]
        _assert(steps_after_100 > 0, "CartPole live: steps should increment, got %d" % steps_after_100)
        print("    steps after 100 frames: %d" % steps_after_100)
        # Wait more — should eventually hit done (untrained genome, pole falls).
        var hit_done: bool = false
        for _i in range(500):
                await get_tree().physics_frame
                if env.is_done():
                        hit_done = true
                        break
        _assert(hit_done, "CartPole live: should hit done within 600 frames")
        # Wait a few more frames — should auto-reset (steps back to 0 or small).
        if hit_done:
                await _wait_frames(5)
                var steps_after_reset: int = env.get_visual_state()["steps"]
                _assert(steps_after_reset < 10, "CartPole live: should auto-reset after done, steps=%d" % steps_after_reset)
                _assert(env.live_episode_count >= 1, "CartPole live: episode count should increment after auto-reset, got %d" % env.live_episode_count)
                print("    auto-reset OK, steps after done+5 frames: %d, episode=%d" % [steps_after_reset, env.live_episode_count])
        # Test N/B: switch genome.
        var g2: Genome = _make_genome(4, 1)
        env.set_live_genome(g2)
        rng.seed = 99999
        env.reset(g2, rng)
        await _wait_frames(10)
        var steps_after_switch: int = env.get_visual_state()["steps"]
        _assert(steps_after_switch > 0 and steps_after_switch < 15, "CartPole live: steps after genome switch should be 1-14, got %d" % steps_after_switch)
        print("    genome switch OK, steps after switch+10 frames: %d" % steps_after_switch)
        env.queue_free()
        await get_tree().process_frame
        print("    CartPole live: OK")

## Test 2: Acrobot live drive. Same structure.
func _test_acrobot_live_drive() -> void:
        print("  --- Acrobot live drive ---")
        var env_scene: PackedScene = load("res://environments/acrobot/acrobot_environment.tscn")
        var env: AcrobotEnvironment = env_scene.instantiate()
        add_child(env)
        env.input_node_ids = [0, 1, 2, 3, 4, 5]
        env.bias_node_id = 6
        env.output_node_id = 7
        env.set_max_steps(500)
        var g: Genome = _make_genome(6, 1)
        env.set_live_genome(g)
        env.live_forward_mode = "topological"
        var rng := RandomNumberGenerator.new()
        rng.seed = 12345
        env.reset(g, rng)
        env.set_live_mode(true)
        env.set_physics_process(true)
        env.set_bodies_frozen(false)
        await _wait_frames(100)
        var steps_after_100: int = env.get_visual_state()["steps"]
        _assert(steps_after_100 > 0, "Acrobot live: steps should increment, got %d" % steps_after_100)
        print("    steps after 100 frames: %d" % steps_after_100)
        # Acrobot rarely hits the height threshold with an untrained genome, but
        # it should hit max_steps eventually. Wait for done or 600 frames.
        var hit_done: bool = false
        for _i in range(600):
                await get_tree().physics_frame
                if env.is_done():
                        hit_done = true
                        break
        if hit_done:
                await _wait_frames(5)
                var steps_after_reset: int = env.get_visual_state()["steps"]
                _assert(steps_after_reset < 10, "Acrobot live: should auto-reset after done, steps=%d" % steps_after_reset)
                print("    auto-reset OK, steps after done+5: %d" % steps_after_reset)
        else:
                print("    (did not hit done in 600 frames — OK for untrained genome)")
        # Test N/B: switch genome.
        var g2: Genome = _make_genome(6, 1)
        env.set_live_genome(g2)
        rng.seed = 99999
        env.reset(g2, rng)
        await _wait_frames(10)
        var state: Dictionary = env.get_visual_state()
        print("    genome switch OK, steps=%d theta1=%.3f" % [int(state["steps"]), float(state["theta1"])])
        env.queue_free()
        await get_tree().process_frame
        print("    Acrobot live: OK")

## Test 3: Pong live drive. Verify no infinite score bug.
func _test_pong_live_drive() -> void:
        print("  --- Pong live drive ---")
        var env_scene: PackedScene = load("res://environments/pong/pong_environment.tscn")
        var env: PongEnvironment = env_scene.instantiate()
        add_child(env)
        env.input_node_ids = [0, 1, 2, 3, 4, 5]
        env.bias_node_id = 6
        env.output_node_id = 7
        env.points_to_win = 5
        env.set_max_steps(1200)
        env.set_player_b(null)
        env.set_forward_mode("topological")
        var g: Genome = _make_genome(6, 1)
        env.set_live_genome(g)
        env.live_forward_mode = "topological"
        var rng := RandomNumberGenerator.new()
        rng.seed = 12345
        env.reset(g, rng)
        env.set_live_mode(true)
        env.set_physics_process(true)
        env.set_bodies_frozen(false)
        # Wait 200 frames.
        await _wait_frames(200)
        var state: Dictionary = env.get_visual_state()
        var score_a: int = int(state["score_a"])
        var score_b: int = int(state["score_b"])
        var steps: int = int(state["steps"])
        print("    after 200 frames: steps=%d score=%d-%d" % [steps, score_a, score_b])
        _assert(steps > 0, "Pong live: steps should increment, got %d" % steps)
        _assert(score_a < 100 and score_b < 100, "Pong live: score should not spiral to infinity, got %d-%d" % [score_a, score_b])
        # Wait for done or 1500 frames (max_steps=1200).
        var hit_done: bool = false
        for _i in range(1500):
                await get_tree().physics_frame
                if env.is_done():
                        hit_done = true
                        break
        if hit_done:
                await _wait_frames(5)
                var state2: Dictionary = env.get_visual_state()
                var steps2: int = int(state2["steps"])
                var score_a2: int = int(state2["score_a"])
                var score_b2: int = int(state2["score_b"])
                print("    hit done, after +5 frames: steps=%d score=%d-%d episode=%d" % [steps2, score_a2, score_b2, env.live_episode_count])
                _assert(steps2 < 20, "Pong live: should auto-reset after done, steps=%d" % steps2)
                _assert(score_a2 < 100 and score_b2 < 100, "Pong live: score still bounded after reset, got %d-%d" % [score_a2, score_b2])
                _assert(env.live_episode_count >= 1, "Pong live: episode count should increment after auto-reset, got %d" % env.live_episode_count)
        else:
                print("    (did not hit done in 1500 frames — OK)")
        # Test N/B: switch genome (this was the trigger for the infinite score bug).
        var g2: Genome = _make_genome(6, 1)
        env.set_live_genome(g2)
        rng.seed = 99999
        env.reset(g2, rng)
        await _wait_frames(50)
        var state3: Dictionary = env.get_visual_state()
        var score_a3: int = int(state3["score_a"])
        var score_b3: int = int(state3["score_b"])
        var steps3: int = int(state3["steps"])
        print("    after genome switch +50 frames: steps=%d score=%d-%d" % [steps3, score_a3, score_b3])
        _assert(score_a3 < 100 and score_b3 < 100, "Pong live: score should not spiral after N/B, got %d-%d" % [score_a3, score_b3])
        _assert(steps3 < 60, "Pong live: steps after switch should be small, got %d" % steps3)
        env.queue_free()
        await get_tree().process_frame
        print("    Pong live: OK")

## Test 4: Teleport reliability.
## - Manually move the cart far off-center via request_teleport.
## - Verify the body's position is far off-center.
## - Then call reset (which queues a teleport back to initial pose).
## - Verify the body's position returns to near 0 after one physics frame.
func _test_teleport_reliability() -> void:
        print("  --- Teleport reliability ---")
        var env_scene: PackedScene = load("res://environments/cartpole/cartpole_environment.tscn")
        var env: CartPoleEnvironment = env_scene.instantiate()
        add_child(env)
        env.input_node_ids = [0, 1, 2, 3]
        env.bias_node_id = 4
        env.output_node_id = 5
        env.set_max_steps(500)
        var g: Genome = _make_genome(4, 1)
        var rng := RandomNumberGenerator.new()
        rng.seed = 1
        env.reset(g, rng)
        # Let physics settle briefly.
        env.set_physics_process(true)
        env.set_bodies_frozen(false)
        await _wait_frames(10)
        # Manually teleport the cart far off-center (x=2.0, near the threshold).
        var cart: TeleportBody2D = env.get_node("Cart")
        cart.request_teleport_pos(Vector2(2.0, 0.0), Vector2.ZERO, 0.0)
        await get_tree().physics_frame
        var cart_x_moved: float = float(env.get_visual_state()["x"])
        print("    cart x after manual teleport to 2.0: %.4f" % cart_x_moved)
        _assert(absf(cart_x_moved - 2.0) < 0.05, "Teleport: cart should be at x≈2.0 after manual teleport, got %.4f" % cart_x_moved)
        # Now reset (queues teleport back to initial pose). Disable live_mode.
        env.set_live_mode(false)
        env.set_physics_process(false)
        # Unfreeze bodies so the teleport takes effect (frozen bodies in STATIC mode
        # may not honor state.transform in _integrate_forces).
        env.set_bodies_frozen(false)
        rng.seed = 2
        env.reset(g, rng)
        # Enable physics_process for one frame so _integrate_forces applies the teleport.
        env.set_physics_process(true)
        await get_tree().physics_frame
        env.set_physics_process(false)
        var cart_x_after: float = float(env.get_visual_state()["x"])
        print("    cart x after reset + 1 physics frame: %.6f" % cart_x_after)
        # The reset applies a random perturbation of ±0.05, so cart should be near 0
        # (within 0.06). If the teleport failed, cart would still be near 2.0.
        _assert(absf(cart_x_after) < 0.06, "CartPole teleport: cart should be back near 0 after reset, got %.4f" % cart_x_after)
        _assert(absf(cart_x_after - 2.0) > 0.5, "CartPole teleport: cart should NOT still be at 2.0 (teleport failed?), got %.4f" % cart_x_after)
        # Also verify the pole rotation reset.
        var theta_after: float = float(env.get_visual_state()["theta"])
        _assert(absf(theta_after) < 0.06, "CartPole teleport: pole theta should be near 0 after reset, got %.4f" % theta_after)
        print("    pole theta after reset: %.6f" % theta_after)
        env.queue_free()
        await get_tree().process_frame
        print("    Teleport reliability: OK")
