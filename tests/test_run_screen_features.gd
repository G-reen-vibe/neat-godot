extends Node
## Test that the RunScreen's new UI features work correctly:
##   1. Column count SpinBox controls the grid's columns property.
##   2. Zoom buttons change Camera2D.zoom (not just cell size).
##   3. Speed multiplier sets Engine.time_scale + max_physics_steps_per_frame.
##   4. Camera pan offset can be applied to all cameras.
##   5. Cell labels use the godot_rl-style stat format.
##   6. 100x and 200x speed presets exist.
##   7. Engine settings are restored on exit.
##
## Run with:
##   godot --headless --path . res://tests/test_run_screen_features.tscn

const RunScreenScene: PackedScene = preload("res://ui/screens/run_screen.tscn")
const POP_SIZE: int = 6

var _failed: bool = false

func _ready() -> void:
        print("=== test_run_screen_features: grid UI mechanics ===")
        await _test()
        if _failed:
                printerr("\n=== test_run_screen_features: FAILED ===")
                get_tree().quit(1)
        else:
                print("\n=== test_run_screen_features: PASSED ===")
                get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
        if not cond:
                push_error("ASSERT FAILED: " + msg)
                _failed = true

func _test() -> void:
        var cfg := NeatConfig.new()
        cfg.num_inputs = 4
        cfg.num_outputs = 1
        cfg.use_bias = true
        cfg.output_activation = ActivationFunctions.Func.TANH
        cfg.population_size = POP_SIZE
        cfg.forward_mode = "topological"
        cfg.forbid_loops = true
        cfg.speciation_method = "standard"
        cfg.compatibility_threshold = 6.0
        cfg.target_species_count = 5
        cfg.generation_method = "asexual"
        cfg.elite_count = 1
        cfg.enable_weight_mutation = true
        cfg.weight_mutation_rate = 0.8
        cfg.enable_connection_mutation = true
        cfg.connection_mutation_rate = 0.1
        cfg.enable_neuron_mutation = true
        cfg.neuron_mutation_rate = 0.1
        cfg.enable_enable_mutation = true
        cfg.enable_mutation_rate = 0.1
        cfg.selection_method = "roulette"
        var pop := Population.new(cfg)
        pop.initialize()
        var extra: Dictionary = {"_max_steps": 50, "_episodes": 1, "_max_generations": 999999}
        var rs: RunScreen = RunScreenScene.instantiate()
        add_child(rs)
        await rs.setup(0, cfg, extra, pop)
        _assert(is_instance_valid(rs), "RunScreen instantiated")
        # --- Test 1: Column count SpinBox controls grid.columns ---
        var grid: GridContainer = rs.find_child("GridContainer", true, false)
        _assert(grid != null, "GridContainer found")
        var cols_spin: SpinBox = rs.find_child("ColumnsSpin", true, false)
        _assert(cols_spin != null, "ColumnsSpin found")
        cols_spin.value = 3
        await get_tree().process_frame
        _assert(grid.columns == 3, "grid.columns = 3 after SpinBox change (got %d)" % grid.columns)
        cols_spin.value = 5
        await get_tree().process_frame
        _assert(grid.columns == 5, "grid.columns = 5 after SpinBox change (got %d)" % grid.columns)
        print("    column count: OK")
        # --- Test 2: Zoom buttons change Camera2D.zoom ---
        var zoom_in_btn: Button = rs.find_child("ZoomInBtn", true, false)
        var zoom_out_btn: Button = rs.find_child("ZoomOutBtn", true, false)
        _assert(zoom_in_btn != null and zoom_out_btn != null, "zoom buttons found")
        # Get initial camera zoom from the first env's camera.
        var env0: Node = rs._evaluator.get_slot_env(0)
        var cam0: Camera2D = null
        for c in env0.find_children("*", "Camera2D", true, false):
                cam0 = c as Camera2D
                break
        _assert(cam0 != null, "found camera in env0")
        var initial_zoom: float = cam0.zoom.x
        zoom_in_btn.pressed.emit()
        await get_tree().process_frame
        var zoomed_in: float = cam0.zoom.x
        _assert(zoomed_in > initial_zoom, "camera zoom increased after zoom in (%.2f -> %.2f)" % [initial_zoom, zoomed_in])
        zoom_out_btn.pressed.emit()
        zoom_out_btn.pressed.emit()
        await get_tree().process_frame
        var zoomed_out: float = cam0.zoom.x
        _assert(zoomed_out < zoomed_in, "camera zoom decreased after zoom out (%.2f -> %.2f)" % [zoomed_in, zoomed_out])
        print("    camera zoom: OK (%.2f -> %.2f -> %.2f)" % [initial_zoom, zoomed_in, zoomed_out])
        # Verify all cameras have the same zoom.
        for i in range(POP_SIZE):
                var env: Node = rs._evaluator.get_slot_env(i)
                for c in env.find_children("*", "Camera2D", true, false):
                        var cam: Camera2D = c as Camera2D
                        _assert(absf(cam.zoom.x - zoomed_out) < 0.01, "camera %d zoom matches (%.2f vs %.2f)" % [i, cam.zoom.x, zoomed_out])
                        break
        print("    all cameras zoom together: OK")
        # --- Test 3: Speed multiplier sets Engine.physics_ticks_per_second ---
        var speed_option: OptionButton = rs.find_child("SpeedOption", true, false)
        _assert(speed_option != null, "SpeedOption found")
        _assert(speed_option.item_selected.is_connected(rs._on_speed_index_changed), "item_selected signal connected")
        # Test 5x.
        rs._on_speed_index_changed(3)  # 5x
        _assert(Engine.physics_ticks_per_second == 300, "physics_ticks = 300 at 5x (got %d)" % Engine.physics_ticks_per_second)
        _assert(Engine.max_physics_steps_per_frame >= 10, "max_physics_steps >= 10 at 5x (got %d)" % Engine.max_physics_steps_per_frame)
        # Test 100x.
        rs._on_speed_index_changed(7)  # 100x
        _assert(Engine.physics_ticks_per_second == 6000, "physics_ticks = 6000 at 100x (got %d)" % Engine.physics_ticks_per_second)
        _assert(Engine.max_physics_steps_per_frame >= 200, "max_physics_steps >= 200 at 100x (got %d)" % Engine.max_physics_steps_per_frame)
        # Test 200x.
        rs._on_speed_index_changed(8)  # 200x
        _assert(Engine.physics_ticks_per_second == 12000, "physics_ticks = 12000 at 200x (got %d)" % Engine.physics_ticks_per_second)
        _assert(Engine.max_physics_steps_per_frame >= 400, "max_physics_steps >= 400 at 200x (got %d)" % Engine.max_physics_steps_per_frame)
        # Restore to 1x.
        rs._on_speed_index_changed(1)  # 1x
        _assert(Engine.physics_ticks_per_second == 60, "physics_ticks = 60 at 1x (got %d)" % Engine.physics_ticks_per_second)
        print("    speed multiplier + physics_ticks: OK")
        # --- Test 4: 100x and 200x presets exist ---
        _assert(speed_option.item_count == 9, "speed option has 9 items (got %d)" % speed_option.item_count)
        _assert(speed_option.get_item_text(7) == "100x", "item 7 is '100x' (got '%s')" % speed_option.get_item_text(7))
        _assert(speed_option.get_item_text(8) == "200x", "item 8 is '200x' (got '%s')" % speed_option.get_item_text(8))
        print("    100x/200x presets: OK")
        # --- Test 5: Camera pan offset can be applied to all cameras ---
        var cameras: Array[Camera2D] = []
        for i in range(POP_SIZE):
                var env: Node = rs._evaluator.get_slot_env(i)
                if env:
                        for c in env.find_children("*", "Camera2D", true, false):
                                cameras.append(c as Camera2D)
                                break
        _assert(not cameras.is_empty(), "found cameras in envs")
        _assert(cameras.size() == POP_SIZE, "found %d cameras (expected %d)" % [cameras.size(), POP_SIZE])
        for cam in cameras:
                cam.offset = Vector2(100, 50)
        await get_tree().process_frame
        for cam in cameras:
                _assert(cam.offset == Vector2(100, 50), "camera offset applied to all cameras")
        print("    camera pan: OK (offset applied to %d cameras)" % cameras.size())
        # --- Test 6: Cell labels use godot_rl-style stat format ---
        await get_tree().process_frame
        await get_tree().process_frame
        var lbl: Label = grid.get_child(0).get_child(1)
        _assert(lbl != null, "cell label found")
        _assert(lbl.text.find("#0") >= 0, "label has genome index: '%s'" % lbl.text)
        _assert(lbl.text.find("ep:") >= 0, "label has episode count: '%s'" % lbl.text)
        _assert(lbl.text.find("r:") >= 0, "label has reward: '%s'" % lbl.text)
        _assert(lbl.text.find("best:") >= 0, "label has best: '%s'" % lbl.text)
        print("    stat reporting: OK (label='%s')" % lbl.text)
        # --- Test 7: Engine settings restored on exit ---
        rs.queue_free()
        await get_tree().process_frame
        # After freeing, _exit_tree should have restored the original settings.
        _assert(Engine.physics_ticks_per_second == 60, "physics_ticks restored to 60 after exit (got %d)" % Engine.physics_ticks_per_second)
        _assert(Engine.max_physics_steps_per_frame == 8, "max_physics_steps restored to 8 after exit (got %d)" % Engine.max_physics_steps_per_frame)
        _assert(Engine.time_scale == 1.0, "time_scale restored to 1.0 after exit (got %f)" % Engine.time_scale)
        print("    engine settings restored on exit: OK")
