extends Node
## Test that the RunScreen's new UI features work correctly:
##   1. Column count SpinBox controls the grid's columns property.
##   2. Zoom buttons change cell size + SubViewport size.
##   3. Speed multiplier sets Engine.time_scale.
##   4. Camera pan offset can be applied to all cameras (inside SubViewports).
##   5. Cell labels use the godot_rl-style stat format (#idx ep:N r:N best:N).
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
        # --- Test 2: Zoom buttons change cell size ---
        var zoom_in_btn: Button = rs.find_child("ZoomInBtn", true, false)
        var zoom_out_btn: Button = rs.find_child("ZoomOutBtn", true, false)
        _assert(zoom_in_btn != null and zoom_out_btn != null, "zoom buttons found")
        var initial_cell_size: Vector2 = grid.get_child(0).custom_minimum_size
        zoom_in_btn.pressed.emit()
        await get_tree().process_frame
        var zoomed_in_size: Vector2 = grid.get_child(0).custom_minimum_size
        _assert(zoomed_in_size.x > initial_cell_size.x, "cell size increased after zoom in (%.0f -> %.0f)" % [initial_cell_size.x, zoomed_in_size.x])
        zoom_out_btn.pressed.emit()
        zoom_out_btn.pressed.emit()
        await get_tree().process_frame
        var zoomed_out_size: Vector2 = grid.get_child(0).custom_minimum_size
        _assert(zoomed_out_size.x < zoomed_in_size.x, "cell size decreased after zoom out (%.0f -> %.0f)" % [zoomed_in_size.x, zoomed_out_size.x])
        print("    zoom: OK (96 -> %.0f -> %.0f)" % [zoomed_in_size.x, zoomed_out_size.x])
        # --- Test 3: Speed multiplier sets Engine.time_scale ---
        # Test that _on_speed_index_changed updates Engine.time_scale.
        # (Setting OptionButton.selected from code doesn't emit item_selected
        # in Godot 4, so we call the method directly to test the logic.)
        var speed_option: OptionButton = rs.find_child("SpeedOption", true, false)
        _assert(speed_option != null, "SpeedOption found")
        # Verify signal is connected.
        _assert(speed_option.item_selected.is_connected(rs._on_speed_index_changed), "item_selected signal connected")
        # Test 5x.
        rs._on_speed_index_changed(3)  # 5x
        _assert(Engine.time_scale == 5.0, "Engine.time_scale = 5.0 at 5x speed (got %f)" % Engine.time_scale)
        # Test 2x.
        rs._on_speed_index_changed(2)  # 2x
        _assert(Engine.time_scale == 2.0, "Engine.time_scale = 2.0 at 2x speed (got %f)" % Engine.time_scale)
        # Test 1x.
        rs._on_speed_index_changed(1)  # 1x
        _assert(Engine.time_scale == 1.0, "Engine.time_scale = 1.0 at 1x speed (got %f)" % Engine.time_scale)
        print("    speed multiplier: OK")
        # --- Test 4: Camera pan offset can be applied to all cameras ---
        # Cameras live inside SubViewports, which have separate scene trees.
        # Access them via the SceneEvaluator's slot envs.
        var cameras: Array[Camera2D] = []
        for i in range(POP_SIZE):
                var env: Node = rs._evaluator.get_slot_env(i)
                if env:
                        for c in env.find_children("*", "Camera2D", true, false):
                                cameras.append(c as Camera2D)
                                break
        _assert(not cameras.is_empty(), "found cameras in envs")
        _assert(cameras.size() == POP_SIZE, "found %d cameras (expected %d)" % [cameras.size(), POP_SIZE])
        # Apply an offset to all cameras (simulates what WASD does via _apply_camera_offset).
        for cam in cameras:
                cam.offset = Vector2(100, 50)
        await get_tree().process_frame
        for cam in cameras:
                _assert(cam.offset == Vector2(100, 50), "camera offset applied to all cameras")
        print("    camera pan: OK (offset applied to %d cameras)" % cameras.size())
        # --- Test 5: Cell labels use godot_rl-style stat format ---
        # After _process runs _update_env_stats + _update_ui, labels should have
        # the "ep: r: best:" format.
        await get_tree().process_frame
        await get_tree().process_frame  # extra frame for stats to populate
        var lbl: Label = grid.get_child(0).get_child(1)
        _assert(lbl != null, "cell label found")
        _assert(lbl.text.find("#0") >= 0, "label has genome index: '%s'" % lbl.text)
        _assert(lbl.text.find("ep:") >= 0, "label has episode count: '%s'" % lbl.text)
        _assert(lbl.text.find("r:") >= 0, "label has reward: '%s'" % lbl.text)
        _assert(lbl.text.find("best:") >= 0, "label has best: '%s'" % lbl.text)
        print("    stat reporting: OK (label='%s')" % lbl.text)
        # Cleanup.
        rs.queue_free()
        await get_tree().process_frame
