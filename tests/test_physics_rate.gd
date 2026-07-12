extends Node
## Diagnostic: measures how many physics frames fire per main frame at
## different Engine.physics_ticks_per_second settings, in headless mode.
##
## Run with: godot --headless --path . res://tests/test_physics_rate.tscn

var _physics_count: int = 0
var _process_count: int = 0
var _test_phase: int = 0  # 0=baseline 60, 1=120, 2=240
var _phase_frames: int = 0
const PHASE_LENGTH: int = 60  # main frames per phase

func _ready() -> void:
	print("=== test_physics_rate: measuring physics frames per main frame ===")
	get_tree().physics_frame.connect(_on_physics_frame)
	_set_phase(0)

func _set_phase(phase: int) -> void:
	_test_phase = phase
	_phase_frames = 0
	_physics_count = 0
	_process_count = 0
	var ticks: int = [60, 120, 240][phase]
	Engine.physics_ticks_per_second = ticks
	Engine.time_scale = 1.0
	print("  Phase %d: physics_ticks_per_second=%d, measuring %d main frames..." % [phase, ticks, PHASE_LENGTH])

func _on_physics_frame() -> void:
	_physics_count += 1

func _process(_delta: float) -> void:
	_process_count += 1
	_phase_frames += 1
	if _phase_frames >= PHASE_LENGTH:
		var ticks: int = [60, 120, 240][_test_phase]
		var ratio: float = float(_physics_count) / float(maxi(1, _process_count))
		print("    Result: %d physics frames / %d process frames = %.3f physics/process (expected ~%.2f)" % [
			_physics_count, _process_count, ratio, float(ticks) / 60.0])
		if _test_phase < 2:
			_set_phase(_test_phase + 1)
		else:
			print("\n=== test_physics_rate: DONE ===")
			get_tree().quit(0)
