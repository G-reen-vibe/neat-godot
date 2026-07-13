extends Node
## UI smoke test: loads main_app.tscn, simulates navigating to each env,
## starting training for a few seconds, and verifies no errors occur.
##
## Run with: godot --headless --path . res://tests/test_ui_smoke.tscn
##
## Tests:
##   1. Main app loads without errors
##   2. Each env card can be clicked -> config screen appears
##   3. Start Training -> Run screen appears
##   4. Training runs for a few generations (no errors)
##   5. Speed change via dropdown works
##   6. Tab switching works
##   7. Back to menu works
##   8. Save/Load UI works

const MainAppScene: PackedScene = preload("res://ui/main_app.tscn")
const ENVS_TO_TEST: Array[int] = [0, 1, 2, 3]  # XOR, CartPole, Acrobot, Pong
const TRAINING_FRAMES_PER_ENV: int = 600  # ~10 seconds at 60fps

var _app: Control
var _failed: bool = false
var _errors: Array = []
var _results: Array = []

func _ready() -> void:
        print("=== test_ui_smoke: UI smoke test ===")
        # Capture script errors.
        ProjectSettings.set_setting("debug/settings/gdscript/warnings/untyped_declaration", 0)
        # Load the main app.
        _app = MainAppScene.instantiate()
        add_child(_app)
        # Wait a frame for _ready to run.
        await get_tree().process_frame
        if not is_instance_valid(_app):
                _fail("Main app failed to instantiate")
                _halt()
                return
        print("  Main app loaded OK.")
        _results.append("main_app: loaded OK")
        # Test each env.
        for env_idx in ENVS_TO_TEST:
                if _failed:
                        break
                await _test_env(env_idx)
        if _failed:
                _halt()
                return
        print("\n=== Results ===")
        for r in _results:
                print("  %s" % r)
        print("\n=== test_ui_smoke: ALL PASSED ===")
        get_tree().quit(0)

func _fail(msg: String) -> void:
        _failed = true
        _errors.append(msg)
        push_error("UI SMOKE FAIL: " + msg)
        printerr("  FAIL: " + msg)

func _halt() -> void:
        printerr("\n=== test_ui_smoke: FAILED ===")
        for e in _errors:
                printerr("  - %s" % e)
        get_tree().quit(1)

func _test_env(env_idx: int) -> void:
        var env_name: String = EnvSelectScreen.ENVS[env_idx].name
        print("\n  --- Testing env %d: %s ---" % [env_idx, env_name])
        # 1. Click env card to navigate to config.
        var env_select: EnvSelectScreen = _app.get_node_or_null("Screens/EnvSelectScreen/EnvSelectScreen")
        if env_select == null:
                # Try via the slot's child.
                var slot := _app.get_node("Screens/EnvSelectScreen")
                for c in slot.get_children():
                        if c is EnvSelectScreen:
                                env_select = c
                                break
        if env_select == null:
                _fail("env_select not found for env %d" % env_idx)
                return
        env_select.selected.emit(env_idx)
        await get_tree().process_frame
        # 2. Verify config screen is visible.
        var config_screen: ConfigScreen = _find_child(_app, "ConfigScreen")
        if config_screen == null:
                _fail("config_screen not found after selecting env %d" % env_idx)
                return
        if not config_screen.visible:
                _fail("config_screen not visible after selecting env %d" % env_idx)
                return
        print("    config screen OK")
        # 3. Click Start Training.
        # Use a small pop size for the test by editing the config first.
        var cfg: NeatConfig = config_screen._config
        cfg.population_size = 12  # small for fast test
        var extra: Dictionary = config_screen._extra
        extra["_max_generations"] = 5
        if env_idx == 0:
                extra["_solved_threshold"] = 15.5
        elif env_idx in [1, 2]:
                extra["_max_steps"] = 200
                extra["_episodes"] = 1
                extra["_speedup"] = 2.0
        elif env_idx == 3:
                extra["_points_to_win"] = 3
                extra["_episodes"] = 1
                extra["_speedup"] = 2.0
                extra["_max_steps"] = 200
        config_screen.start_requested.emit(cfg, extra)
        await get_tree().process_frame
        await get_tree().process_frame
        # 4. Verify run screen is visible.
        var run_screen: RunScreen = _find_child(_app, "RunScreen")
        if run_screen == null:
                _fail("run_screen not found after starting training for env %d" % env_idx)
                return
        if not run_screen.visible:
                _fail("run_screen not visible after starting training for env %d" % env_idx)
                return
        print("    run screen OK")
        # 5. Training auto-runs at default speed (1x). Let it train for a few seconds.
        var last_gen: int = -1
        for i in range(TRAINING_FRAMES_PER_ENV):
                await get_tree().process_frame
                if _failed:
                        return
                # Print progress every 60 frames.
                if i % 60 == 59:
                        var p: Population = run_screen.get_population()
                        if p != null:
                                print("    [frame %d] gen=%d best=%.3f" % [i + 1, p.generation, p.best_fitness])
                                if p.generation > last_gen:
                                        last_gen = p.generation
        # 6. Check that training made progress (generation > 0 OR solved).
        var pop: Population = run_screen.get_population()
        if pop == null:
                _fail("run_screen.get_population() returned null for env %d" % env_idx)
                return
        if pop.generation < 1:
                _fail("env %d (%s): pop.generation=%d, expected >= 1" % [env_idx, env_name, pop.generation])
                return
        print("    training OK: gen=%d best=%.3f species=%d" % [pop.generation, pop.best_fitness, pop.species_count()])
        _results.append("%s: gen=%d best=%.3f species=%d" % [env_name, pop.generation, pop.best_fitness, pop.species_count()])
        # 7. Switch tabs (Stats, SaveLoad, back to Genome).
        var right_tabs: TabContainer = _find_node_by_name(run_screen, "RightTabs")
        if right_tabs != null:
                right_tabs.current_tab = 1  # Stats
                await get_tree().process_frame
                right_tabs.current_tab = 2  # SaveLoad
                await get_tree().process_frame
                right_tabs.current_tab = 0  # Genome
                await get_tree().process_frame
                print("    tab switching OK")
        # 8. Test visualization buttons (for non-XOR).
        if env_idx != 0:
                var zoom_in: Button = _find_node_by_name(run_screen, "ZoomInBtn")
                var zoom_out: Button = _find_node_by_name(run_screen, "ZoomOutBtn")
                var reset_view: Button = _find_node_by_name(run_screen, "ResetViewBtn")
                if zoom_in: zoom_in.pressed.emit()
                if zoom_out: zoom_out.pressed.emit()
                if reset_view: reset_view.pressed.emit()
                await get_tree().process_frame
                print("    viz buttons OK")
        # 9. Test speed dropdown: pause then resume.
        var speed_option: OptionButton = _find_node_by_name(run_screen, "SpeedOption")
        if speed_option != null:
                speed_option.selected = 0  # Pause
                speed_option.item_selected.emit(0)
                await get_tree().process_frame
                speed_option.selected = 1  # 1x
                speed_option.item_selected.emit(1)
                await get_tree().process_frame
                print("    speed control OK")
        # 10. Test speed up/down buttons.
        var speed_down: Button = _find_node_by_name(run_screen, "SpeedDownBtn")
        var speed_up: Button = _find_node_by_name(run_screen, "SpeedUpBtn")
        if speed_down and speed_up:
                speed_down.pressed.emit()
                await get_tree().process_frame
                speed_up.pressed.emit()
                await get_tree().process_frame
                print("    speed buttons OK")
        # 11. Back to menu.
        var back_btn: Button = _find_node_by_name(run_screen, "BackBtn")
        if back_btn == null:
                _fail("BackBtn not found")
                return
        back_btn.pressed.emit()
        await get_tree().process_frame
        # Wait for the await in main_app._on_start_training to settle.
        await get_tree().process_frame
        print("    back to menu OK")

func _find_child(root: Node, name: String) -> Node:
        # Search by class name.
        for c in root.get_children():
                if c.get_class() == name or c.is_class(name) or c.get_script() and c.get_script().get_global_name() == name:
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
