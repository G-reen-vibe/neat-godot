extends Node
## Test that RunScreen.setup() doesn't crash (regression test for the
## transparent_bg crash on SubViewportContainer).
##
## Instantiates the actual RunScreen scene, calls setup() with a real
## Population + config, and verifies the grid is built without errors.
##
## Run with:
##   godot --headless --path . res://tests/test_run_screen_setup.tscn

const RunScreenScene: PackedScene = preload("res://ui/screens/run_screen.tscn")
const POP_SIZE: int = 8

var _failed: bool = false

func _ready() -> void:
	print("=== test_run_screen_setup: RunScreen.setup() regression test ===")
	await _test()
	if _failed:
		printerr("\n=== test_run_screen_setup: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_run_screen_setup: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test() -> void:
	# Build a minimal config for CartPole.
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
	var extra: Dictionary = {"_max_steps": 100, "_episodes": 1, "_max_generations": 999999}
	# Instantiate RunScreen and call setup().
	var rs: RunScreen = RunScreenScene.instantiate()
	add_child(rs)
	_assert(is_instance_valid(rs), "RunScreen instantiated")
	# This is the line that used to crash with:
	#   Invalid assignment of property or key 'transparent_bg' with value of
	#   type 'bool' on a base object of type 'SubViewportContainer'.
	await rs.setup(0, cfg, extra, pop)
	_assert(is_instance_valid(rs), "RunScreen still valid after setup()")
	# Verify the grid was built with the correct number of cells.
	# The RunScreen stores cells in _cells (private), but we can check the
	# GridContainer's child count.
	var grid: GridContainer = rs.find_child("GridContainer", true, false)
	_assert(grid != null, "GridContainer found")
	_assert(grid.get_child_count() == POP_SIZE, "grid has %d children (expected %d)" % [grid.get_child_count(), POP_SIZE])
	# Verify each cell has a SubViewportContainer with a SubViewport child.
	for i in range(grid.get_child_count()):
		var cell: Control = grid.get_child(i)
		var svc: SubViewportContainer = null
		for c in cell.get_children():
			if c is SubViewportContainer:
				svc = c
				break
		_assert(svc != null, "cell %d has a SubViewportContainer" % i)
		_assert(svc.get_child_count() >= 1, "cell %d SVC has a SubViewport child" % i)
		_assert(svc.get_child(0) is SubViewport, "cell %d SVC child is a SubViewport" % i)
	print("    grid: %d cells, each with SubViewportContainer + SubViewport" % grid.get_child_count())
	# Run one physics frame to verify no errors.
	await get_tree().physics_frame
	_assert(is_instance_valid(rs), "RunScreen valid after physics frame")
	# Cleanup.
	rs.queue_free()
	await get_tree().process_frame
	print("    RESULT: RunScreen.setup() completed without crash")
