extends Node
## Test that the config UI schema covers all NeatConfig fields and that
## _apply_config correctly writes values back.
## Run with: godot --headless --path . res://tests/test_config_ui.tscn

var _failed: bool = false

func _ready() -> void:
        print("=== test_config_ui: comprehensive config schema test ===")
        _test_all_envs_schema_coverage()
        if _failed: _halt()
        _test_config_apply_roundtrip()
        if _failed: _halt()
        _test_activation_conversion()
        if _failed: _halt()
        print("\n=== test_config_ui: ALL PASSED ===")
        get_tree().quit()

func _assert(cond: bool, msg: String) -> void:
        if not cond:
                push_error("ASSERT FAILED: " + msg)
                _failed = true

func _halt() -> void:
        printerr("\n=== test_config_ui: FAILED ===")
        get_tree().quit(1)

func _test_all_envs_schema_coverage() -> void:
        # Build the main app so we can call its methods.
        var app = Control.new()
        app.set_script(load("res://ui/main_app.gd"))
        add_child(app)
        # Check that every NeatConfig field (except internal/script/num_inputs/
        # num_outputs/input_activation/initial_weight_range which are set per-env
        # and not user-configurable) appears in the schema for each env.
        var skip_fields: Array = [
                "num_inputs", "num_outputs", "input_activation", "initial_weight_range",
                "threshold_adjustment_speed",  # getter/setter alias
        ]
        for env_idx in range(6):
                app._env_idx = env_idx
                app._config = app._make_config(env_idx)
                app._extra = app._make_extra(env_idx)
                var schema: Array = app._get_config_schema()
                var schema_keys: Dictionary = {}
                for entry: Dictionary in schema:
                        if entry.has("key"):
                                schema_keys[entry["key"]] = true
                # Check all NeatConfig properties.
                var cfg: NeatConfig = app._config
                for prop in cfg.get_property_list():
                        var pname: String = prop.name
                        if pname.begins_with("_") or pname == "script" or pname.begins_with("num_"):
                                continue
                        if skip_fields.has(pname):
                                continue
                        var val: Variant = cfg.get(pname)
                        if not (val is int or val is float or val is bool or val is String):
                                continue
                        _assert(schema_keys.has(pname), "Env %d: NeatConfig field '%s' missing from schema" % [env_idx, pname])
                print("  env %d: schema covers all NeatConfig fields" % env_idx)
        app.queue_free()
        print("  schema coverage: OK")

func _test_config_apply_roundtrip() -> void:
        # Build app, select env, build controls, apply config, verify values match.
        var app = Control.new()
        app.set_script(load("res://ui/main_app.gd"))
        add_child(app)
        app._env_idx = 0  # XOR
        app._config = app._make_config(0)
        app._extra = app._make_extra(0)
        # We need to call _build_config_screen first (creates _config_scroll).
        app._build_config_screen()
        app._build_config_controls()
        # Now apply and check that key values are preserved.
        app._apply_config()
        _assert(app._config.population_size == 150, "population_size should be 150, got %d" % app._config.population_size)
        _assert(app._config.speciation_method == "purge", "speciation_method should be purge")
        _assert(app._config.generation_method == "asexual", "generation_method should be asexual")
        _assert(app._config.forward_mode == "topological", "forward_mode should be topological")
        _assert(app._config.use_bias == true, "use_bias should be true")
        _assert(app._config.mutation_policy_method == "general", "mutation_policy_method should be general")
        _assert(app._config.enable_weight_mutation == true, "enable_weight_mutation should be true")
        _assert(app._config.enable_connection_mutation == true, "enable_connection_mutation should be true")
        _assert(app._config.enable_neuron_mutation == true, "enable_neuron_mutation should be true")
        _assert(app._config.enable_enable_mutation == true, "enable_enable_mutation should be true")
        _assert(app._config.enable_prune_mutation == false, "enable_prune_mutation should be false")
        _assert(app._config.similarity_method == "standard", "similarity_method should be standard")
        _assert(app._config.evaluation_method == "equal", "evaluation_method should be equal")
        _assert(app._config.selection_method == "roulette", "selection_method should be roulette")
        app.queue_free()
        print("  config apply roundtrip: OK")

func _test_activation_conversion() -> void:
        # Test that activation int <-> string conversion works.
        for f in ActivationFunctions.all_ids():
                var name: String = ActivationFunctions.name_of(f)
                var back: int = ActivationFunctions.from_name(name)
                _assert(back == f, "Activation round-trip failed: %d -> %s -> %d" % [f, name, back])
        print("  activation conversion: OK")
