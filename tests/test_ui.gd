extends Node
## Test the new main_app UI: verify screen transitions, config building,
## and training startup for all 6 environments.
## Run with: godot --headless --path . res://tests/test_ui.tscn

var app: Control

func _ready() -> void:
	print("=== test_ui: main_app screen transitions ===")
	app = Control.new()
	app.set_script(load("res://ui/main_app.gd"))
	add_child(app)
	# _ready was called when added. Check we start on env select.
	assert(app._screen == app.ScreenState.ENV_SELECT, "Should start on ENV_SELECT")
	print("  env select: OK")

	# Test selecting each env → config screen → start training.
	for env_idx in range(6):
		_test_env_flow(env_idx)

	print("\n=== test_ui: ALL PASSED ===")
	get_tree().quit()

func _test_env_flow(env_idx: int) -> void:
	var env_name: String = app.ENVS[env_idx]["name"]
	# Select env.
	app._select_env(env_idx)
	assert(app._screen == app.ScreenState.CONFIG, "Should be on CONFIG after selecting %s" % env_name)
	assert(app._config != null, "Config should be set for %s" % env_name)
	assert(app._env_idx == env_idx, "Env idx should be %d" % env_idx)
	# Config controls should be built.
	assert(not app._config_controls.is_empty(), "Config controls should be built for %s" % env_name)
	# Apply config and start training.
	app._start_training()
	assert(app._screen == app.ScreenState.RUNNING, "Should be on RUNNING after start for %s" % env_name)
	assert(app._pop != null, "Population should be initialized for %s" % env_name)
	assert(app._pop.size() == app._config.population_size, "Pop size should match config for %s" % env_name)
	# Step one generation.
	app._step_generation()
	assert(app._pop.generation == 1, "Generation should be 1 after step for %s" % env_name)
	# Go back to env select.
	app._show_screen(app.ScreenState.ENV_SELECT)
	assert(app._screen == app.ScreenState.ENV_SELECT, "Should return to ENV_SELECT from %s" % env_name)
	print("  %s: OK (gen=1, pop=%d, species=%d)" % [env_name, app._pop.size(), app._pop.species_count()])
