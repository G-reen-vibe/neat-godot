## Training screen: shows a grid of all envs running in parallel + graph + stats + save/load.
##
## Left panel layout:
##   HSplitContainer
##     Left (stretch=1.0):
##       VBox
##         Header (toolbar: back, config, speed down/dropdown/up, status)
##         VizScroll (ScrollContainer containing a GridContainer of env SubViewports)
##         HelpBar (key hints)
##     Right (fixed 420px):
##       TabContainer (Genome / Stats / Saving)
##
## Grid visualization (matches godot_rl preview functionality):
##   - The SceneEvaluator creates N SubViewports (one per genome slot).
##   - RunScreen re-parents each SubViewport into a SubViewportContainer in
##     the grid, so all N envs are visible and running simultaneously during
##     training.
##   - Each cell has a label showing the genome index and current fitness.
##   - The grid auto-sizes columns based on available width.
##
## Training control: speed dropdown with speed=0 (Pause) .. 50x.
##   - speed=0 (Pause): training halted; grid shows frozen envs.
##   - speed=N: training runs continuously (1 generation per evaluate_all
##     coroutine completion); the speed value is ignored for physics envs
##     but kept for UI consistency.
extends MarginContainer
class_name RunScreen

signal back_requested()
signal config_requested()

const GraphVisualizerScene: PackedScene = preload("res://ui/components/graph_visualizer.tscn")
const TrainingStatsViewScene: PackedScene = preload("res://ui/components/training_stats_view.tscn")
const SaveLoadViewScene: PackedScene = preload("res://ui/components/save_load_view.tscn")

# Speed presets: index in OptionButton -> generations per frame.
# For physics envs (all current envs), any speed > 0 means "train continuously".
# Index 0 is Pause (speed=0); indices 1..6 are 1x..50x.
const SPEED_PRESETS: Array[int] = [0, 1, 2, 5, 10, 25, 50]
const CELL_SIZE: Vector2i = Vector2i(96, 96)

@onready var _back_btn: Button = %BackBtn
@onready var _config_btn: Button = %ConfigBtn
@onready var _speed_down_btn: Button = %SpeedDownBtn
@onready var _speed_option: OptionButton = %SpeedOption
@onready var _speed_up_btn: Button = %SpeedUpBtn
@onready var _status_label: Label = %StatusLabel
@onready var _viz_scroll: ScrollContainer = %VizScroll
@onready var _grid: GridContainer = %GridContainer
@onready var _genome_tab: PanelContainer = %Genome
@onready var _stats_tab: PanelContainer = %Stats
@onready var _save_load_tab: PanelContainer = %Saving

var _visualizer: GraphVisualizer
var _stats_view: TrainingStatsView
var _save_load_view: SaveLoadView

var _pop: Population = null
var _config: NeatConfig = null
var _extra: Dictionary = {}
var _env_idx: int = -1
var _env_scene: PackedScene = null
# _speed: 0 = paused, >0 = training.
var _speed: int = 1
var _stepping: bool = false
var _evaluator: SceneEvaluator = null
var _stats_tracker: TrainingStatsTracker = null
# Set to true when the RunScreen is being freed; lets in-flight coroutines
# bail out instead of touching the disposed evaluator / freed nodes.
var _disposing: bool = false

# Grid cells: one per SubViewport slot. Each cell is a Control containing a
# SubViewportContainer (holding the re-parented SubViewport) + a Label.
var _cells: Array[Dictionary] = []  # { "svc": SubViewportContainer, "label": Label, "viewport": SubViewport }

func _ready() -> void:
	_back_btn.pressed.connect(func(): back_requested.emit())
	_config_btn.pressed.connect(func(): config_requested.emit())
	_speed_option.item_selected.connect(_on_speed_index_changed)
	_speed_down_btn.pressed.connect(_on_speed_down)
	_speed_up_btn.pressed.connect(_on_speed_up)
	# Initialize speed from the OptionButton's default selection.
	_speed = SPEED_PRESETS[_speed_option.selected]
	# Build the right-tab children.
	_visualizer = GraphVisualizerScene.instantiate()
	_genome_tab.add_child(_visualizer)
	_stats_view = TrainingStatsViewScene.instantiate()
	_stats_tab.add_child(_stats_view)
	_save_load_view = SaveLoadViewScene.instantiate()
	_save_load_tab.add_child(_save_load_view)

func setup(env_idx: int, config: NeatConfig, extra: Dictionary, pop: Population) -> void:
	_env_idx = env_idx
	_config = config
	_extra = extra
	_pop = pop
	_visualizer.population = pop
	_stats_tracker = TrainingStatsTracker.new()
	_stats_tracker.set_config_snapshot(config)
	_stats_view.tracker = _stats_tracker
	_save_load_view.population = pop
	_save_load_view.config = config
	_save_load_view.env_idx = env_idx
	# Determine env scene. All current envs are physics-based 2D.
	match env_idx:
		0:
			_env_scene = load("res://environments/cartpole/neat_cartpole_env.tscn")
		1:
			_env_scene = load("res://environments/pong/neat_pong_env.tscn")
		2:
			_env_scene = load("res://environments/lunar_lander/neat_lunar_lander_env.tscn")
		3:
			_env_scene = load("res://environments/bipedal_walker/neat_bipedal_walker_env.tscn")
	_setup_evaluator()
	_build_grid()
	_update_ui()

func _setup_evaluator() -> void:
	# Dispose any previous evaluator (frees its SubViewports).
	_dispose_evaluator()
	# All current envs are physics-based, so use SceneEvaluator.
	var max_steps: int = int(_extra.get("_max_steps", 500))
	var pop_size: int = _config.population_size
	_evaluator = SceneEvaluator.new(self, _env_scene, pop_size, max_steps + 10, _config.forward_mode)
	_evaluator.episodes_per_genome = int(_extra.get("_episodes", 1))
	_evaluator.env_setup_fn = _make_env_setup_fn()

func _dispose_evaluator() -> void:
	if _evaluator == null:
		return
	if is_instance_valid(_evaluator):
		_evaluator.dispose()
	_evaluator = null

## Build the grid by re-parenting the SceneEvaluator's SubViewports into
## SubViewportContainers. This mirrors the godot_rl RLPreviewGrid approach.
func _build_grid() -> void:
	# Clear old cells.
	for cell in _cells:
		var svc: SubViewportContainer = cell.svc
		if is_instance_valid(svc):
			svc.queue_free()
	_cells.clear()
	if _evaluator == null:
		return
	# Auto-calculate columns based on available width.
	var available_width: float = _viz_scroll.size.x
	if available_width < CELL_SIZE.x:
		available_width = 800  # fallback before layout
	var cols: int = max(1, int(available_width / (CELL_SIZE.x + 2)))
	_grid.columns = cols
	# Create one cell per slot.
	var n: int = _evaluator.get_slot_count()
	for i in range(n):
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(CELL_SIZE)
		_grid.add_child(cell)
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.set_anchors_preset(Control.PRESET_FULL_RECT)
		svc.size = Vector2(CELL_SIZE)
		svc.transparent_bg = true
		cell.add_child(svc)
		var lbl := Label.new()
		lbl.text = "#%d" % i
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.position = Vector2(2, 1)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		cell.add_child(lbl)
		# Re-parent the SubViewport from the SceneEvaluator into this cell's SVC.
		var vp: SubViewport = _evaluator.get_slot_viewport(i)
		if vp:
			vp.get_parent().remove_child(vp)
			svc.add_child(vp)
			# Re-activate the camera after re-parenting.
			var env: Node = _evaluator.get_slot_env(i)
			if env:
				for child in env.find_children("*", "Camera2D", true, false):
					(child as Camera2D).make_current()
					break
		_cells.append({ "svc": svc, "label": lbl, "viewport": vp })

func _exit_tree() -> void:
	_disposing = true
	_dispose_evaluator()

func _make_env_setup_fn() -> Callable:
	var num_in: int = _config.num_inputs
	var bias_id: int = num_in
	var output_start: int = num_in + 1
	var max_steps: int = int(_extra.get("_max_steps", 500))
	var output_ids: Array[int] = []
	match _env_idx:
		0:  # CartPole: 4 inputs, 1 output
			var ids: Array[int] = [0, 1, 2, 3]
			output_ids = [output_start]
			return func(env: Node) -> void:
				env.input_node_ids = ids
				env.bias_node_id = bias_id
				env.output_node_id = output_start
				env.output_node_ids = output_ids
				env.set_max_steps(max_steps)
		1:  # Pong: 5 inputs, 1 output
			var ids2: Array[int] = [0, 1, 2, 3, 4]
			output_ids = [output_start]
			return func(env: Node) -> void:
				env.input_node_ids = ids2
				env.bias_node_id = bias_id
				env.output_node_id = output_start
				env.output_node_ids = output_ids
				env.set_max_steps(max_steps)
		2:  # LunarLander: 6 inputs, 3 outputs
			var ids3: Array[int] = [0, 1, 2, 3, 4, 5]
			output_ids = [output_start, output_start + 1, output_start + 2]
			return func(env: Node) -> void:
				env.input_node_ids = ids3
				env.bias_node_id = bias_id
				env.output_node_id = output_start
				env.output_node_ids = output_ids
				env.set_max_steps(max_steps)
		3:  # BipedalWalker: 8 inputs, 4 outputs
			var ids4: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
			output_ids = [output_start, output_start + 1, output_start + 2, output_start + 3]
			return func(env: Node) -> void:
				env.input_node_ids = ids4
				env.bias_node_id = bias_id
				env.output_node_id = output_start
				env.output_node_ids = output_ids
				env.set_max_steps(max_steps)
	return Callable()

# --- Speed control ---

func _on_speed_index_changed(idx: int) -> void:
	idx = clampi(idx, 0, SPEED_PRESETS.size() - 1)
	var new_speed: int = SPEED_PRESETS[idx]
	if new_speed == _speed:
		return
	_speed = new_speed

func _on_speed_down() -> void:
	var idx: int = _speed_option.selected
	if idx > 0:
		_speed_option.selected = idx - 1

func _on_speed_up() -> void:
	var idx: int = _speed_option.selected
	if idx < SPEED_PRESETS.size() - 1:
		_speed_option.selected = idx + 1

# --- Input ---

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE:
			# Toggle between paused (speed=0) and running (speed=1).
			if _speed == 0:
				_speed_option.selected = 1
			else:
				_speed_option.selected = 0
			get_viewport().set_input_as_handled()

# --- Process loop ---

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _disposing:
		return
	_update_ui()
	# Start training only if speed > 0, not already stepping.
	if _speed == 0 or _stepping or _disposing:
		return
	if _pop == null:
		return
	# Launch the step coroutine; it runs independently of _process and
	# sets _stepping = false when done.
	_stepping = true
	_step_budget()

## Run training continuously. For physics envs (all current envs), run 1
## generation per call — physics is the bottleneck, so the speed value is
## ignored. _process will re-launch this coroutine each frame as long as
## speed > 0.
func _step_budget() -> void:
	await _step_generation()
	_stepping = false

func _step_generation() -> void:
	if _pop == null or _disposing:
		return
	if _evaluator == null:
		return
	var fitnesses: Array[float] = await _evaluator.evaluate_all(_pop.genomes)
	# The evaluator may have been disposed while we were awaiting (e.g. the
	# user clicked Back mid-generation). Bail out without touching _pop.
	if _disposing or _pop == null or not is_instance_valid(self):
		return
	for i in range(_pop.genomes.size()):
		_pop.genomes[i].fitness = fitnesses[i]
		if fitnesses[i] > _pop.best_fitness:
			_pop.best_fitness = fitnesses[i]
			_pop.best_genome = _pop.genomes[i].duplicate()
	# Record stats BEFORE evolve(), so we capture the actual evaluated
	# fitnesses of this generation.
	if _stats_tracker != null:
		_stats_tracker.record(_pop)
	_pop.evolve()

func _update_ui() -> void:
	if _pop == null:
		return
	var state_str: String = "Paused" if _speed == 0 else "Running %dx" % _speed
	_status_label.text = "Gen %d   |   Best: %.2f   |   Species: %d   |   %s" % [
		_pop.generation, _pop.best_fitness, _pop.species_count(), state_str,
	]
	_visualizer.refresh()
	if _save_load_view != null:
		_save_load_view.population = _pop
		_save_load_view.config = _config
	# Update cell labels with genome index + fitness.
	for i in range(_cells.size()):
		if i >= _pop.genomes.size():
			break
		var lbl: Label = _cells[i].label
		if lbl == null or not is_instance_valid(lbl):
			continue
		var fit: float = _pop.genomes[i].fitness
		lbl.text = "#%d  %.1f" % [i, fit]

func get_population() -> Population:
	return _pop

func get_config() -> NeatConfig:
	return _config

func get_extra() -> Dictionary:
	return _extra
