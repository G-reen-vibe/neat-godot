extends Node
## Test that the speed multiplier actually accelerates physics, not just
## sets a variable without effect.
##
## Measures how many physics frames fire in a fixed wall-clock period at
## different speed settings. Higher speed should yield more physics frames.
##
## Run with:
##   godot --headless --path . res://tests/test_speed_effective.tscn

const MEASURE_DURATION_SEC: float = 1.0

var _failed: bool = false
var _frame_count: int = 0
var _measuring: bool = false
var _measure_start: float = 0.0

func _ready() -> void:
	print("=== test_speed_effective: speed multiplier accelerates physics ===")
	await _test()
	if _failed:
		printerr("\n=== test_speed_effective: FAILED ===")
		get_tree().quit(1)
	else:
		print("\n=== test_speed_effective: PASSED ===")
		get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		_failed = true

func _physics_process(_delta: float) -> void:
	if _measuring:
		_frame_count += 1

func _test() -> void:
	# Measure physics frame count at 1x (60 ticks/sec).
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 200
	var frames_1x: int = await _measure_frames()
	print("    1x (60 tps): %d physics frames in %.1fs" % [frames_1x, MEASURE_DURATION_SEC])
	# Measure at 5x (300 ticks/sec).
	Engine.physics_ticks_per_second = 300
	Engine.max_physics_steps_per_frame = 200
	var frames_5x: int = await _measure_frames()
	print("    5x (300 tps): %d physics frames in %.1fs" % [frames_5x, MEASURE_DURATION_SEC])
	# Measure at 10x (600 ticks/sec).
	Engine.physics_ticks_per_second = 600
	Engine.max_physics_steps_per_frame = 200
	var frames_10x: int = await _measure_frames()
	print("    10x (600 tps): %d physics frames in %.1fs" % [frames_10x, MEASURE_DURATION_SEC])
	# Restore.
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	# Assertions:
	# At 1x, we expect ~60 frames/sec * 1s = ~60 frames.
	_assert(frames_1x > 40, "1x should produce >40 frames in 1s (got %d)" % frames_1x)
	# At 5x, we should get ~5x more frames.
	_assert(frames_5x > frames_1x * 2, "5x should produce >2x more frames than 1x (got %d vs %d)" % [frames_5x, frames_1x])
	# At 10x, even more.
	_assert(frames_10x > frames_5x, "10x should produce more frames than 5x (got %d vs %d)" % [frames_10x, frames_5x])
	print("    speed multiplier is effective: OK")

func _measure_frames() -> int:
	_frame_count = 0
	_measuring = true
	_measure_start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - _measure_start < MEASURE_DURATION_SEC * 1000.0:
		await get_tree().physics_frame
	_measuring = false
	return _frame_count
