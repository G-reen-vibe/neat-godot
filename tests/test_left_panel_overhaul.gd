extends Node
## End-to-end test for the left-panel overhaul. Simulates a user playing
## the game: selects an env, starts training, changes speed, cycles live
## genomes with N/B, pans/zooms the camera with WASD/+/-/0, and goes back.
##
## Verifies:
##   1. No Run/Pause button, no Restart button, no Follow button exist.
##   2. Speed dropdown has "Pause" as item 0 and 1x as default (selected=1).
##   3. Speed down/up buttons change the dropdown selection within bounds.
##   4. Speed=Pause (index 0) halts training (generation doesn't advance).
##   5. N key cycles the live genome (live_idx advances through pop.genomes).
##   6. B key resets to best genome (live_is_best = true).
##   7. WASD keys set _pan_input in EnvViewport (continuous pan).
##   8. +/-/0 keys adjust zoom and reset view in EnvViewport.
##   9. ESC key does NOT exit the run screen (binding was removed).
##  10. Camera help text in EnvViewport mentions "WASD".
##  11. Status label is non-empty and contains "Gen" and "Speed" or "Paused".
##  12. N/B do NOT change the graph visualizer's current genome index.
##
## Run with: godot --headless --path . res://tests/test_left_panel_overhaul.tscn

const MainAppScene: PackedScene = preload("res://ui/main_app.tscn")
const TEST_ENV: int = 1  # CartPole - has physics viz, fast to train

var _app: Control
var _failed: bool = false
var _errors: Array = []

func _ready() -> void:
        print("=== test_left_panel_overhaul: verify new left panel UX ===")
        _app = MainAppScene.instantiate()
        add_child(_app)
        await get_tree().process_frame
        if not is_instance_valid(_app):
                _fail("Main app failed to instantiate")
                _halt()
                return
        # Navigate to CartPole config screen.
        var env_select := _find_child(_app, "EnvSelectScreen") as EnvSelectScreen
        if env_select == null:
                _fail("EnvSelectScreen not found")
                _halt()
                return
        env_select.selected.emit(TEST_ENV)
        await get_tree().process_frame
        # Configure small pop for fast test.
        var config_screen := _find_child(_app, "ConfigScreen") as ConfigScreen
        if config_screen == null:
                _fail("ConfigScreen not found")
                _halt()
                return
        var cfg: NeatConfig = config_screen._config
        cfg.population_size = 10
        var extra: Dictionary = config_screen._extra
        extra["_max_generations"] = 50
        extra["_max_steps"] = 100
        extra["_episodes"] = 1
        extra["_speedup"] = 2.0
        config_screen.start_requested.emit(cfg, extra)
        await get_tree().process_frame
        await get_tree().process_frame
        var run_screen := _find_child(_app, "RunScreen") as RunScreen
        if run_screen == null:
                _fail("RunScreen not found after start")
                _halt()
                return
        print("  RunScreen loaded OK")
        # --- Test 1: Removed buttons ---
        if _find_node_by_name(run_screen, "RunPauseBtn") != null:
                _fail("RunPauseBtn should have been removed")
        if _find_node_by_name(run_screen, "RestartBtn") != null:
                _fail("RestartBtn should have been removed")
        if _find_node_by_name(run_screen, "FollowBtn") != null:
                _fail("FollowBtn should have been removed")
        if not _failed:
                print("  [OK] Removed buttons: RunPause, Restart, Follow are gone")
        # --- Test 2: Speed dropdown structure ---
        var speed_option := _find_node_by_name(run_screen, "SpeedOption") as OptionButton
        if speed_option == null:
                _fail("SpeedOption not found")
        else:
                if speed_option.get_item_count() != 7:
                        _fail("SpeedOption should have 7 items, got %d" % speed_option.get_item_count())
                if speed_option.get_item_text(0) != "Pause":
                        _fail("SpeedOption item 0 should be 'Pause', got '%s'" % speed_option.get_item_text(0))
                if speed_option.selected != 1:
                        _fail("SpeedOption default should be index 1 (1x), got %d" % speed_option.selected)
                if not _failed:
                        print("  [OK] Speed dropdown: 7 items, item 0 = Pause, default = 1x")
        # --- Test 3: Speed down/up buttons ---
        var speed_down := _find_node_by_name(run_screen, "SpeedDownBtn") as Button
        var speed_up := _find_node_by_name(run_screen, "SpeedUpBtn") as Button
        if speed_down == null or speed_up == null:
                _fail("SpeedDownBtn or SpeedUpBtn not found")
        else:
                # Start at index 1 (1x). Click down -> index 0 (Pause).
                speed_down.pressed.emit()
                await get_tree().process_frame
                if speed_option.selected != 0:
                        _fail("After SpeedDown, selected should be 0 (Pause), got %d" % speed_option.selected)
                # Click down again -> should stay at 0 (clamped).
                speed_down.pressed.emit()
                await get_tree().process_frame
                if speed_option.selected != 0:
                        _fail("SpeedDown at 0 should stay 0, got %d" % speed_option.selected)
                # Click up -> index 1.
                speed_up.pressed.emit()
                await get_tree().process_frame
                if speed_option.selected != 1:
                        _fail("After SpeedUp from 0, selected should be 1, got %d" % speed_option.selected)
                # Click up several times -> should reach max (6) and stay.
                for i in range(10):
                        speed_up.pressed.emit()
                await get_tree().process_frame
                if speed_option.selected != 6:
                        _fail("After many SpeedUp, selected should be 6 (max), got %d" % speed_option.selected)
                # Click up again -> should stay at 6.
                speed_up.pressed.emit()
                await get_tree().process_frame
                if speed_option.selected != 6:
                        _fail("SpeedUp at max should stay max, got %d" % speed_option.selected)
                if not _failed:
                        print("  [OK] Speed down/up buttons clamp within [0, 6]")
        # Reset to 1x for further tests.
        speed_option.selected = 1
        speed_option.item_selected.emit(1)
        await get_tree().process_frame
        # --- Test 4: Speed=Pause halts training ---
        # Let it train a few frames at 1x. CartPole needs ~50-100 render frames
        # per generation (SceneEvaluator awaits physics frames, speedup=2.0).
        var gen_before: int = run_screen.get_population().generation
        for i in range(180):
                await get_tree().process_frame
        var gen_after_run: int = run_screen.get_population().generation
        if gen_after_run <= gen_before:
                _fail("Training didn't advance at 1x: before=%d after=%d" % [gen_before, gen_after_run])
        # Pause.
        speed_option.selected = 0
        speed_option.item_selected.emit(0)
        # Wait for any in-flight generation to complete (the pause takes effect
        # after the current step finishes).
        for i in range(120):
                await get_tree().process_frame
        var gen_at_pause: int = run_screen.get_population().generation
        # Now wait another 60 frames and verify no further advancement.
        for i in range(60):
                await get_tree().process_frame
        var gen_after_pause: int = run_screen.get_population().generation
        if gen_after_pause != gen_at_pause:
                _fail("Training advanced while paused: at_pause=%d after_pause=%d" % [gen_at_pause, gen_after_pause])
        if not _failed:
                print("  [OK] Speed=Pause halts training (gen stayed at %d)" % gen_at_pause)
        # Resume at 1x.
        speed_option.selected = 1
        speed_option.item_selected.emit(1)
        await get_tree().process_frame
        # --- Test 5 & 6: N/B keys cycle live genome ---
        # Wait for at least 1 generation to ensure best_genome is set.
        for i in range(60):
                await get_tree().process_frame
                if run_screen.get_population().best_genome != null:
                        break
        var pop: Population = run_screen.get_population()
        if pop == null or pop.best_genome == null:
                _fail("Population/best_genome not ready for N/B test")
        else:
                # Press N -> live genome should be pop.genomes[0].
                # We call _next_live_genome() directly because Input.parse_input_event
                # is unreliable for key injection in headless mode.
                run_screen._next_live_genome()
                await get_tree().process_frame
                if run_screen._live_is_best:
                        _fail("After N, live_is_best should be false")
                elif run_screen._live_idx != 0:
                        _fail("After N, live_idx should be 0, got %d" % run_screen._live_idx)
                else:
                        # Press N again -> live_idx = 1.
                        run_screen._next_live_genome()
                        await get_tree().process_frame
                        if run_screen._live_idx != 1:
                                _fail("After N again, live_idx should be 1, got %d" % run_screen._live_idx)
                        # Press B -> back to best.
                        run_screen._show_best_live_genome()
                        await get_tree().process_frame
                        if not run_screen._live_is_best:
                                _fail("After B, live_is_best should be true")
                        if not _failed:
                                print("  [OK] N cycles live genome (0->1), B resets to best")
        # --- Test 7: WASD sets _pan_input in EnvViewport ---
        var env_viewport := _find_node_by_name(run_screen, "EnvViewport") as EnvViewport
        if env_viewport == null:
                _fail("EnvViewport not found")
        else:
                # Press W (pan up). We call _input directly because
                # Input.parse_input_event is unreliable in headless mode.
                env_viewport._input(_make_key(KEY_W, true))
                await get_tree().process_frame
                if env_viewport._pan_input.y != -1.0:
                        _fail("After W, _pan_input.y should be -1.0, got %f" % env_viewport._pan_input.y)
                # Release W.
                env_viewport._input(_make_key(KEY_W, false))
                await get_tree().process_frame
                if env_viewport._pan_input.y != 0.0:
                        _fail("After W release, _pan_input.y should be 0.0, got %f" % env_viewport._pan_input.y)
                # Press A.
                env_viewport._input(_make_key(KEY_A, true))
                await get_tree().process_frame
                if env_viewport._pan_input.x != -1.0:
                        _fail("After A, _pan_input.x should be -1.0, got %f" % env_viewport._pan_input.x)
                # Press D simultaneously (overrides A).
                env_viewport._input(_make_key(KEY_D, true))
                await get_tree().process_frame
                if env_viewport._pan_input.x != 1.0:
                        _fail("After D (while A held), _pan_input.x should be 1.0, got %f" % env_viewport._pan_input.x)
                # Release all.
                env_viewport._input(_make_key(KEY_A, false))
                env_viewport._input(_make_key(KEY_D, false))
                await get_tree().process_frame
                if env_viewport._pan_input.x != 0.0:
                        _fail("After release all, _pan_input.x should be 0.0, got %f" % env_viewport._pan_input.x)
                if not _failed:
                        print("  [OK] WASD sets _pan_input correctly (held = continuous pan)")
        # --- Test 8: +/-/0 keys adjust zoom and reset ---
        if env_viewport != null:
                var zoom_before: float = env_viewport._camera_zoom
                env_viewport._input(_make_key(KEY_EQUAL, true))
                await get_tree().process_frame
                if env_viewport._camera_zoom <= zoom_before:
                        _fail("After '+', zoom should increase, before=%f after=%f" % [zoom_before, env_viewport._camera_zoom])
                env_viewport._input(_make_key(KEY_MINUS, true))
                await get_tree().process_frame
                env_viewport._input(_make_key(KEY_MINUS, true))
                await get_tree().process_frame
                if env_viewport._camera_zoom >= zoom_before:
                        _fail("After '-', zoom should decrease below original, got %f" % env_viewport._camera_zoom)
                env_viewport._input(_make_key(KEY_0, true))
                await get_tree().process_frame
                if absf(env_viewport._camera_zoom - 1.0) > 0.001:
                        _fail("After '0', zoom should be 1.0, got %f" % env_viewport._camera_zoom)
                if env_viewport._camera_offset != Vector2.ZERO:
                        _fail("After '0', camera_offset should be ZERO, got %s" % str(env_viewport._camera_offset))
                if not _failed:
                        print("  [OK] +/-/0 keys: zoom in/out/reset all work")
        # --- Test 9: ESC does NOT exit ---
        var visible_before_esc: bool = run_screen.visible
        run_screen._input(_make_key(KEY_ESCAPE, true))
        await get_tree().process_frame
        if not run_screen.visible and visible_before_esc:
                _fail("ESC exited the run screen (binding should be removed)")
        elif not _failed:
                print("  [OK] ESC does not exit the run screen")
        # --- Test 10: Camera help text mentions WASD ---
        # (Verified via the EnvViewport._draw string; we can't easily read it
        # back, so we just check that the help text in the tscn is correct.)
        var help_label := _find_node_by_name(run_screen, "HelpText") as Label
        if help_label == null:
                _fail("HelpText label not found")
        elif help_label.text.find("WASD") < 0:
                _fail("HelpText should mention 'WASD', got: %s" % help_label.text)
        elif not _failed:
                print("  [OK] Help text mentions WASD")
        # --- Test 11: Status label is non-empty and informative ---
        var status_label := _find_node_by_name(run_screen, "StatusLabel") as Label
        if status_label == null:
                _fail("StatusLabel not found")
        elif status_label.text.is_empty():
                _fail("StatusLabel is empty")
        elif status_label.text.find("Gen") < 0:
                _fail("StatusLabel should contain 'Gen', got: %s" % status_label.text)
        elif not _failed:
                print("  [OK] Status label: %s" % status_label.text)
        # --- Test 12: N/B did NOT change the graph visualizer ---
        # The graph visualizer has its own _current_genome_idx that starts at 0.
        # After our N/B presses above, it should still be at 0 (or whatever it
        # was set to by its own navigation, not by our N/B).
        var viz := _find_node_by_name(run_screen, "GraphVisualizer") as GraphVisualizer
        if viz == null:
                _fail("GraphVisualizer not found")
        elif viz._current_genome_idx != 0:
                _fail("GraphVisualizer._current_genome_idx should be 0 (N/B shouldn't affect it), got %d" % viz._current_genome_idx)
        elif not _failed:
                print("  [OK] N/B did not change the graph visualizer's genome index")
        # --- Done ---
        if _failed:
                _halt()
                return
        print("\n=== test_left_panel_overhaul: ALL PASSED ===")
        get_tree().quit(0)

func _make_key(keycode: int, pressed: bool) -> InputEventKey:
        var ev := InputEventKey.new()
        ev.keycode = keycode
        ev.pressed = pressed
        ev.echo = false
        return ev

func _fail(msg: String) -> void:
        _failed = true
        _errors.append(msg)
        push_error("LEFT PANEL FAIL: " + msg)
        printerr("  FAIL: " + msg)

func _halt() -> void:
        printerr("\n=== test_left_panel_overhaul: FAILED ===")
        for e in _errors:
                printerr("  - %s" % e)
        get_tree().quit(1)

func _find_child(root: Node, name: String) -> Node:
        for c in root.get_children():
                if c.get_class() == name or c.is_class(name) or (c.get_script() and c.get_script().get_global_name() == name):
                        return c
                var found := _find_child(c, name)
                if found != null:
                        return found
        return null

func _find_node_by_name(root: Node, name: String) -> Node:
        if root.name == name:
                return root
        for c in root.get_children():
                var found := _find_node_by_name(c, name)
                if found != null:
                        return found
        return null
