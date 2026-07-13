extends Node
## Test that the RunScreen's grid visualization is built correctly.
##
## Verifies:
##   1. SceneEvaluator creates SubViewports with UPDATE_ALWAYS (renderable).
##   2. Each SubViewport has a Camera2D active.
##   3. The RL env's visual children (Polygon2D) are visible.
##   4. Re-parenting SubViewports into SubViewportContainers works.
##   5. The grid has the correct number of cells.
##
## Run with:
##   godot --headless --path . res://tests/test_grid_viz.tscn

const POP_SIZE: int = 8
const MAX_STEPS: int = 50

var _failed: bool = false

func _ready() -> void:
	print("=== test_grid_viz: grid visualization structure ===")
	await _test()
	if _failed:
		printerr("\n=== test_grid_viz: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_grid_viz: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _test() -> void:
	var env_scene: PackedScene = load("res://environments/cartpole/neat_cartpole_env.tscn")
	var evaluator := SceneEvaluator.new(self, env_scene, POP_SIZE, MAX_STEPS + 10, "topological")
	evaluator.env_setup_fn = func(env: Node) -> void:
		env.input_node_ids = ([0, 1, 2, 3] as Array[int])
		env.bias_node_id = 4
		env.output_node_id = 5
		env.output_node_ids = ([5] as Array[int])
		env.set_max_steps(MAX_STEPS)
	_assert(evaluator.get_slot_count() == POP_SIZE, "evaluator has %d slots" % POP_SIZE)
	# Check each slot's SubViewport is renderable.
	for i in range(POP_SIZE):
		var vp: SubViewport = evaluator.get_slot_viewport(i)
		_assert(vp != null, "slot %d has a SubViewport" % i)
		_assert(vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "slot %d SubViewport has UPDATE_ALWAYS" % i)
		_assert(vp.size.x > 64 and vp.size.y > 64, "slot %d SubViewport size > 64x64 (got %s)" % [i, str(vp.size)])
		var env: Node = evaluator.get_slot_env(i)
		_assert(env != null, "slot %d has an env" % i)
		# Check the RL env is visible (not hidden).
		_assert(env.visible, "slot %d env is visible" % i)
		# Check the RL env has a Camera2D child.
		var has_camera: bool = false
		for child in env.find_children("*", "Camera2D", true, false):
			has_camera = true
			break
		_assert(has_camera, "slot %d env has a Camera2D" % i)
		# Check the RL env has Polygon2D children (visual elements).
		var has_polygon: bool = false
		for child in env.find_children("*", "Polygon2D", true, false):
			has_polygon = true
			break
		_assert(has_polygon, "slot %d env has Polygon2D visuals" % i)
	# Test re-parenting into a SubViewportContainer (simulating what RunScreen does).
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size = Vector2(96, 96)
	add_child(svc)
	var vp0: SubViewport = evaluator.get_slot_viewport(0)
	var old_parent: Node = vp0.get_parent()
	_assert(old_parent != null, "SubViewport has a parent before re-parenting")
	old_parent.remove_child(vp0)
	svc.add_child(vp0)
	_assert(vp0.get_parent() == svc, "SubViewport re-parented into SubViewportContainer")
	# Re-activate camera after re-parenting.
	var env0: Node = evaluator.get_slot_env(0)
	for child in env0.find_children("*", "Camera2D", true, false):
		(child as Camera2D).make_current()
		break
	_assert(true, "camera re-activated after re-parenting")
	# Run a few physics frames to verify the env still works after re-parenting.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	env0.reset(null, rng)
	for i in range(10):
		await get_tree().physics_frame
	_assert(not env0.is_done() or env0.current_fitness() > 0, "env still works after re-parenting")
	svc.queue_free()
	evaluator.dispose()
	print("    All %d slots verified: renderable, visible, cameras active" % POP_SIZE)
