## Top-level preview scene: grid of envs + a small stats panel.
##
## Instantiates the Academy as a child, wires the grid to it, and
## attaches a random action source by default (so the scene runs
## standalone without a trainer).
extends Control

class_name RLPreviewScene

@export var env_name: String = "cartpole"
@export var num_envs: int = 16
@export var columns: int = 4
@export var time_scale: float = 1.0

var _academy: RLAcademy
var _grid: RLPreviewGrid
var _header: Label


func _ready() -> void:
	RLEnvRegistration.register_all()

	_header = Label.new()
	_header.text = "Env: %s  |  %d envs  |  random actions" % [env_name, num_envs]
	_header.add_theme_font_size_override("font_size", 16)
	_header.position = Vector2(8, 4)
	add_child(_header)

	_grid = RLPreviewGrid.new()
	_grid.columns = columns
	_grid.set_anchors_preset(PRESET_FULL_RECT)
	_grid.offset_top = 28
	add_child(_grid)

	_academy = RLAcademy.new()
	_academy.env_name = env_name
	_academy.num_envs = num_envs
	_academy.decision_period = 1
	_academy.time_scale = time_scale
	_academy.render_envs = true
	add_child(_academy)

	_academy.set_action_source(RLRandomActionSource.new())

	_grid.set_academy(_academy)
