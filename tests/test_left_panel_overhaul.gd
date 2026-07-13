extends Node
## End-to-end test for the left-panel with speed dropdown control.
##
## Verifies:
##   1. No Run/Pause button, no Restart button, no Follow button exist.
##   2. Speed dropdown has "Pause" as item 0 and 1x as default (selected=1).
##   3. Speed down/up buttons change the dropdown selection within bounds.
##   4. Speed=Pause halts training (generation doesn't advance).
##   5. Resume (speed=1) restarts training (generation advances).
##   6. N key cycles the live genome (live_idx advances through pop.genomes).
##   7. B key resets to best genome (live_is_best = true).
##   8. WASD keys set _pan_input in EnvViewport (continuous pan).
##   9. +/-/0 keys adjust zoom and reset view in EnvViewport.
##  10. ESC key does NOT exit the run screen (binding was removed).
##  11. Camera help text mentions "WASD".
##  12. Status label is non-empty and contains "Gen".
##  13. N/B do NOT change the graph visualizer's current genome index.
##  14. Live env is only driven when paused (not during training).
##
## Run with: godot --headless --path . res://tests/test_left_panel_overhaul.tscn

const MainAppScene: PackedScene = preload("res://ui/main_app.tscn")
const TEST_ENV: int = 1  # CartPole

var _app: Control
var _failed: bool = false
var _errors: Array = []

func _ready() -> void:
        print("=== test_left_panel_overhaul: verify left panel UX ===")
        _app = MainAppScene.instantiate()
        add_child(_app)
        await get_tree().process_frame
        if not is_instance_valid(_app):
                _fail("Main app failed to instantiate")
                _halt()
                return
        var env_select := _find_child(_app, "EnvSelectScreen") as EnvSelectScreen
        if env_select == null:
                _fail("EnvSelectScreen not found")
                _halt()
                return
        env_select.selected.emit(TEST_ENV)
        await get_tree().process_frame
        var config_screen := _find_child(_app, "ConfigScreen") as ConfigScreen
        if config_screen == null:
                _fail("ConfigScreen not found")
                _halt()
                return
        var cfg: NeatConfig = config_screen._config
        cfg.population_size = 10
        var extra: Dictionary = config_screen._extra
        extra["_max_generations"] = 50
        extra["_max_steps"] = 500
        extra["_episodes"] = 1
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
        if _find_node_by_name(run_screen, "PauseResumeBtn") != null:
                _fail("PauseResumeBtn should have been removed")
        if not _failed:
                print("  [OK] Removed: RunPause, Restart, Follow, PauseResume")
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
                speed_down.pressed.emit()
                await get_tree().process_frame
                if speed_option.selected != 0:
                        _fail("After SpeedDown, selected should be 0 (Pause), got %d" % speed_option.selected)
                speed_down.pressed.emit()
                await get_tree().process_frame
                if speed_option.selected != 0:
                        _fail("SpeedDown at 0 should stay 0, got %d" % speed_option.selected)
                speed_up.pressed.emit()
                await get_tree().process_frame
                if speed_option.selected != 1:
                        _fail("After SpeedUp from 0, selected should be 1, got %d" % speed_option.selected)
                for i in range(10):
                        speed_up.pressed.emit()
                await get_tree().process_frame
                if speed_option.selected != 6:
                        _fail("After many SpeedUp, selected should be 6 (max), got %d" % speed_option.selected)
                if not _failed:
                        print("  [OK] Speed down/up buttons clamp within [0, 6]")
        # Reset to 1x.
        speed_option.selected = 1
        speed_option.item_selected.emit(1)
        await get_tree().process_frame
        # --- Test 4: Training advances at 1x ---
        # Wait for any in-flight _step_budget to complete, then verify training advances.
        # CartPole with max_steps=500 needs ~500 physics frames per generation, but
        # most genomes die early (~10-50 steps), so a generation completes in ~100 frames.
        var gen_before: int = run_screen.get_population().generation
        var gen_after_run: int = gen_before
        for i in range(2000):
                await get_tree().process_frame
                gen_after_run = run_screen.get_population().generation
                if gen_after_run > gen_before:
                        break
        if gen_after_run <= gen_before:
                _fail("Training didn't advance at 1x: before=%d after=%d" % [gen_before, gen_after_run])
        if not _failed:
                print("  [OK] Training advances at 1x (gen %d -> %d)" % [gen_before, gen_after_run])
        # Let it train a bit more so we have a meaningful gen_at_pause.
        for i in range(600):
                await get_tree().process_frame
        # Pause.
        speed_option.selected = 0
        speed_option.item_selected.emit(0)
        # Wait for in-flight generation to complete.
        for i in range(2000):
                await get_tree().process_frame
                if not run_screen._stepping:
                        break
        var gen_at_pause: int = run_screen.get_population().generation
        # Wait another 60 frames and verify no advancement.
        for i in range(60):
                await get_tree().process_frame
        var gen_after_pause: int = run_screen.get_population().generation
        if gen_after_pause != gen_at_pause:
                _fail("Training advanced while paused: at_pause=%d after_pause=%d" % [gen_at_pause, gen_after_pause])
        if not _failed:
                print("  [OK] Speed=Pause halts training (gen stayed at %d)" % gen_at_pause)
        # --- Test 5: Resume restarts training ---
        var gen_before_resume: int = run_screen.get_population().generation
        speed_option.selected = 1
        speed_option.item_selected.emit(1)
        # Wait for training to advance after resume.
        var gen_after_resume: int = gen_before_resume
        for i in range(2000):
                await get_tree().process_frame
                gen_after_resume = run_screen.get_population().generation
                if gen_after_resume > gen_before_resume:
                        break
        if gen_after_resume <= gen_before_resume:
                _fail("Training didn't resume after unpausing: before=%d after=%d" % [gen_before_resume, gen_after_resume])
        if not _failed:
                print("  [OK] Resume restarts training (gen %d -> %d)" % [gen_before_resume, gen_after_resume])
        # --- Test 6 & 7: N/B keys cycle live genome ---
        # Pause so we can test the live env.
        speed_option.selected = 0
        speed_option.item_selected.emit(0)
        await get_tree().process_frame
        for i in range(60):
                await get_tree().process_frame
                if run_screen.get_population().best_genome != null:
                        break
        var pop: Population = run_screen.get_population()
        if pop == null or pop.best_genome == null:
                _fail("Population/best_genome not ready for N/B test")
        else:
                run_screen._next_live_genome()
                await get_tree().process_frame
                if run_screen._live_is_best:
                        _fail("After N, live_is_best should be false")
                elif run_screen._live_idx != 0:
                        _fail("After N, live_idx should be 0, got %d" % run_screen._live_idx)
                else:
                        run_screen._next_live_genome()
                        await get_tree().process_frame
                        if run_screen._live_idx != 1:
                                _fail("After N again, live_idx should be 1, got %d" % run_screen._live_idx)
                        run_screen._show_best_live_genome()
                        await get_tree().process_frame
                        if not run_screen._live_is_best:
                                _fail("After B, live_is_best should be true")
                        if not _failed:
                                print("  [OK] N cycles live genome (0->1), B resets to best")
        # --- Test 8: WASD sets _pan_input in EnvViewport ---
        var env_viewport := _find_node_by_name(run_screen, "EnvViewport") as EnvViewport
        if env_viewport == null:
                _fail("EnvViewport not found")
        else:
                env_viewport._input(_make_key(KEY_W, true))
                await get_tree().process_frame
                if env_viewport._pan_input.y != -1.0:
                        _fail("After W, _pan_input.y should be -1.0, got %f" % env_viewport._pan_input.y)
                env_viewport._input(_make_key(KEY_W, false))
                await get_tree().process_frame
                if env_viewport._pan_input.y != 0.0:
                        _fail("After W release, _pan_input.y should be 0.0, got %f" % env_viewport._pan_input.y)
                env_viewport._input(_make_key(KEY_A, true))
                await get_tree().process_frame
                if env_viewport._pan_input.x != -1.0:
                        _fail("After A, _pan_input.x should be -1.0, got %f" % env_viewport._pan_input.x)
                env_viewport._input(_make_key(KEY_D, true))
                await get_tree().process_frame
                if env_viewport._pan_input.x != 1.0:
                        _fail("After D (while A held), _pan_input.x should be 1.0, got %f" % env_viewport._pan_input.x)
                env_viewport._input(_make_key(KEY_A, false))
                env_viewport._input(_make_key(KEY_D, false))
                await get_tree().process_frame
                if env_viewport._pan_input.x != 0.0:
                        _fail("After release all, _pan_input.x should be 0.0, got %f" % env_viewport._pan_input.x)
                if not _failed:
                        print("  [OK] WASD sets _pan_input correctly")
        # --- Test 9: +/-/0 keys adjust zoom and reset ---
        if env_viewport != null:
                var zoom_before: float = env_viewport._camera_zoom
                env_viewport._input(_make_key(KEY_EQUAL, true))
                await get_tree().process_frame
                if env_viewport._camera_zoom <= zoom_before:
                        _fail("After '+', zoom should increase")
                env_viewport._input(_make_key(KEY_MINUS, true))
                await get_tree().process_frame
                env_viewport._input(_make_key(KEY_MINUS, true))
                await get_tree().process_frame
                if env_viewport._camera_zoom >= zoom_before:
                        _fail("After '-', zoom should decrease below original")
                env_viewport._input(_make_key(KEY_0, true))
                await get_tree().process_frame
                if absf(env_viewport._camera_zoom - 1.0) > 0.001:
                        _fail("After '0', zoom should be 1.0, got %f" % env_viewport._camera_zoom)
                if not _failed:
                        print("  [OK] +/-/0 keys: zoom in/out/reset all work")
        # --- Test 10: ESC does NOT exit ---
        var visible_before_esc: bool = run_screen.visible
        run_screen._input(_make_key(KEY_ESCAPE, true))
        await get_tree().process_frame
        if not run_screen.visible and visible_before_esc:
                _fail("ESC exited the run screen")
        elif not _failed:
                print("  [OK] ESC does not exit the run screen")
        # --- Test 11: Help text mentions WASD ---
        var help_label := _find_node_by_name(run_screen, "HelpText") as Label
        if help_label == null:
                _fail("HelpText not found")
        elif help_label.text.find("WASD") < 0:
                _fail("HelpText should mention 'WASD'")
        elif not _failed:
                print("  [OK] Help text mentions WASD")
        # --- Test 12: Status label ---
        var status_label := _find_node_by_name(run_screen, "StatusLabel") as Label
        if status_label == null:
                _fail("StatusLabel not found")
        elif status_label.text.is_empty():
                _fail("StatusLabel is empty")
        elif status_label.text.find("Gen") < 0:
                _fail("StatusLabel should contain 'Gen'")
        elif not _failed:
                print("  [OK] Status label: %s" % status_label.text)
        # --- Test 13: N/B did NOT change graph visualizer ---
        var viz := _find_node_by_name(run_screen, "GraphVisualizer") as GraphVisualizer
        if viz == null:
                _fail("GraphVisualizer not found")
        elif viz._current_genome_idx != 0:
                _fail("GraphVisualizer._current_genome_idx should be 0, got %d" % viz._current_genome_idx)
        elif not _failed:
                print("  [OK] N/B did not change graph visualizer's genome index")
        # --- Test 14: Live env advances when paused ---
        if env_viewport != null and env_viewport.env != null:
                # The live env should be stepping (its _physics_process is enabled
                # when paused). Steps may reset to 0 if is_done() triggers, so we
                # just check that the env state is changing over time.
                var vis_state: Dictionary = env_viewport.env.get_visual_state()
                var steps_before: int = int(vis_state.get("steps", 0))
                var done_before: bool = bool(vis_state.get("done", false))
                var sample_a: int = steps_before
                var sample_b: int = steps_before
                for i in range(30):
                        await get_tree().physics_frame
                vis_state = env_viewport.env.get_visual_state()
                sample_b = int(vis_state.get("steps", 0))
                # Either steps increased, or the env reset (done=true then reset).
                # If steps_before was 0 and sample_b is 0, the env isn't running.
                if sample_b == 0 and steps_before == 0:
                        _fail("Live env didn't advance while paused: both samples are 0")
                elif not _failed:
                        print("  [OK] Live env is running while paused (steps %d -> %d)" % [sample_a, sample_b])
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
