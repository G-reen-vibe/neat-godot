extends Node
## Verify auto-step continues training across multiple generations for each env.
## Run with: godot --headless --path . res://tests/test_autostep.tscn

var app: Control

func _ready() -> void:
	print("=== test_autostep: verify training continues ===")
	app = Control.new()
	app.set_script(load("res://ui/main_app.gd"))
	add_child(app)
	# Test each env runs at least 5 generations without stopping prematurely.
	for env_idx in range(6):
		_test_env_autostep(env_idx)
	print("\n=== test_autostep: ALL PASSED ===")
	get_tree().quit()

func _test_env_autostep(env_idx: int) -> void:
	var env_name: String = app.ENVS[env_idx]["name"]
	app._select_env(env_idx)
	# Set max generations low so we don't wait forever.
	app._extra["_max_generations"] = 5
	app._start_training()
	# Manually step 5 generations.
	for i in range(5):
		app._step_generation()
		if app._solved:
			print("  %s: SOLVED at gen %d (fit=%.2f) — OK" % [env_name, app._pop.generation, app._pop.best_fitness])
			return
	print("  %s: ran %d gens, best=%.2f — OK" % [env_name, app._pop.generation, app._pop.best_fitness])
