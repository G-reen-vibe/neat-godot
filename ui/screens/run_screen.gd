## Training screen: shows a grid of all envs running in parallel + graph + stats + save/load.
##
## Left panel layout:
##   HSplitContainer
##     Left (stretch=1.0, max_width constrained):
##       VBox
##         Header (toolbar: back, config, speed, columns, zoom, status)
##         VizPanel > VizScroll > GridContainer (env SubViewport grid)
##         HelpBar (key hints)
##     Right (fixed 420px):
##       TabContainer (Genome / Stats / Saving)
##
## Grid visualization (matches godot_rl preview functionality):
##   - The SceneEvaluator creates N SubViewports (one per genome slot).
##   - RunScreen re-parents each SubViewport into a SubViewportContainer in
##     the grid, so all N envs are visible and running simultaneously during
##     training.
##   - Each cell has a label showing the genome index, episode count, and
##     current episode reward (mirrors godot_rl's RLPreviewGrid labels).
##   - Column count is user-configurable via a SpinBox in the toolbar.
##   - Zoom buttons change Camera2D.zoom (how much of the world the camera
##     sees) and scale cell size proportionally. All cameras zoom together.
##   - WASD pans all cameras together.
##
## Speed multiplier:
##   - Uses Engine.physics_ticks_per_second to accelerate physics. This
##     increases the actual number of physics steps per wall-clock second,
##     each with a proportionally smaller delta — physics quality is
##     preserved (smaller delta = more stable integration, not less).
##   - Engine.time_scale is NOT used because in headless mode it only
##     inflates the delta without increasing step count, which degrades
##     physics (tunneling, instability).
##   - Also increases Engine.max_physics_steps_per_frame so the engine can
##     actually run that many ticks per render frame (default cap is 8).
##   - speed=0 pauses (physics_ticks_per_second=0); speed=N sets
##     physics_ticks_per_second = 60 * N.
##   - Training episodes finish faster because max_steps is in physics steps,
##     so more steps/sec = less wall-clock time per episode = faster training.
extends MarginContainer
class_name RunScreen

signal back_requested()
signal config_requested()

const GraphVisualizerScene: PackedScene = preload("res://ui/components/graph_visualizer.tscn")
const TrainingStatsViewScene: PackedScene = preload("res://ui/components/training_stats_view.tscn")
const SaveLoadViewScene: PackedScene = preload("res://ui/components/save_load_view.tscn")

# Speed presets: index in OptionButton -> Engine.time_scale value.
# Index 0 is Pause (speed=0); indices 1..8 are 1x..200x.
const SPEED_PRESETS: Array[float] = [0.0, 1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0, 200.0]
const DEFAULT_CELL_SIZE: int = 96
const MIN_CELL_SIZE: int = 48
const MAX_CELL_SIZE: int = 384
const DEFAULT_COLUMNS: int = 8
const CAMERA_PAN_SPEED: float = 200.0  # world units per second
const MIN_CAM_ZOOM: float = 0.25
const MAX_CAM_ZOOM: float = 8.0

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
@onready var _columns_spin: SpinBox = %ColumnsSpin
@onready var _zoom_in_btn: Button = %ZoomInBtn
@onready var _zoom_out_btn: Button = %ZoomOutBtn

var _visualizer: GraphVisualizer
var _stats_view: TrainingStatsView
var _save_load_view: SaveLoadView

var _pop: Population = null
var _config: NeatConfig = null
var _extra: Dictionary = {}
var _env_idx: int = -1
var _env_scene: PackedScene = null
# _speed: 0 = paused, >0 = training (Engine.time_scale = _speed).
var _speed: float = 1.0
var _stepping: bool = false
var _evaluator: SceneEvaluator = null
var _stats_tracker: TrainingStatsTracker = null
# Set to true when the RunScreen is being freed; lets in-flight coroutines
# bail out instead of touching the disposed evaluator / freed nodes.
var _disposing: bool = false

# Grid cells: one per SubViewport slot. Each cell is a Control containing a
# SubViewportContainer (holding the re-parented SubViewport) + a Label.
var _cells: Array[Dictionary] = []
# { "svc": SubViewportContainer, "label": Label, "viewport": SubViewport,
#   "env": Node, "camera": Camera2D, "base_cam_zoom": Vector2 }

# Per-env live stats (updated each physics frame by reading the env).
# Mirrors godot_rl's RLEnvStats: episode count, episode reward, best reward.
var _env_stats: Array[Dictionary] = []
# { "episode": int, "episode_reward": float, "best_reward": float,
#   "last_fitness": float, "done_last_frame": bool }

# Current cell size (pixels). Scales with camera zoom.
var _cell_size: int = DEFAULT_CELL_SIZE
# Current camera zoom multiplier (applied to all cameras). >1 = zoomed in
# (see less of the world, objects appear larger).
var _cam_zoom: float = 1.0

# Camera pan offset (world units). Applied to all cameras simultaneously.
var _cam_offset: Vector2 = Vector2.ZERO
# Track held WASD keys for continuous smooth panning.
var _pan_input: Vector2 = Vector2.ZERO

# Saved engine settings to restore on exit.
var _saved_physics_ticks: int = 60
var _saved_max_physics_steps: int = 8

func _ready() -> void:
        _back_btn.pressed.connect(func(): back_requested.emit())
        _config_btn.pressed.connect(func(): config_requested.emit())
        _speed_option.item_selected.connect(_on_speed_index_changed)
        _speed_down_btn.pressed.connect(_on_speed_down)
        _speed_up_btn.pressed.connect(_on_speed_up)
        _columns_spin.value_changed.connect(_on_columns_changed)
        _zoom_in_btn.pressed.connect(func(): _adjust_zoom(1.25))
        _zoom_out_btn.pressed.connect(func(): _adjust_zoom(1.0 / 1.25))
        # Initialize speed from the OptionButton's default selection.
        _speed = SPEED_PRESETS[_speed_option.selected]
        # Save engine settings so we can restore them on exit.
        _saved_physics_ticks = Engine.physics_ticks_per_second
        _saved_max_physics_steps = Engine.max_physics_steps_per_frame
        _apply_speed()
        # Build the right-tab children.
        _visualizer = GraphVisualizerScene.instantiate()
        _genome_tab.add_child(_visualizer)
        _stats_view = TrainingStatsViewScene.instantiate()
        _stats_tab.add_child(_stats_view)
        _save_load_view = SaveLoadViewScene.instantiate()
        _save_load_tab.add_child(_save_load_view)
        set_process_input(true)

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
        _dispose_evaluator()
        var max_steps: int = int(_extra.get("_max_steps", 500))
        var pop_size: int = _config.population_size
        _evaluator = SceneEvaluator.new(self, _env_scene, pop_size, max_steps + 10, _config.forward_mode)
        _evaluator.episodes_per_genome = int(_extra.get("_episodes", 1))
        _evaluator.env_setup_fn = _make_env_setup_fn()
        _evaluator.viewport_size = Vector2i(_cell_size, _cell_size)

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
        _env_stats.clear()
        if _evaluator == null:
                return
        # Initialize per-env stats.
        var n: int = _evaluator.get_slot_count()
        _env_stats.resize(n)
        for i in range(n):
                _env_stats[i] = {
                        "episode": 0,
                        "episode_reward": 0.0,
                        "best_reward": -1e9,
                        "last_fitness": 0.0,
                        "done_last_frame": false,
                }
        # Create one cell per slot.
        for i in range(n):
                var cell := Control.new()
                cell.custom_minimum_size = Vector2(_cell_size, _cell_size)
                # Prevent the cell from expanding beyond its minimum size — this
                # keeps the grid from pushing the layout wider than the viewport.
                cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
                _grid.add_child(cell)
                var svc := SubViewportContainer.new()
                svc.stretch = true
                svc.set_anchors_preset(Control.PRESET_FULL_RECT)
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
                var env: Node = _evaluator.get_slot_env(i)
                var cam: Camera2D = null
                var base_zoom: Vector2 = Vector2.ONE
                if vp:
                        vp.reparent(svc)
                        # Find + activate the camera after re-parenting.
                        if env:
                                for child in env.find_children("*", "Camera2D", true, false):
                                        cam = child as Camera2D
                                        base_zoom = cam.zoom
                                        cam.make_current()
                                        break
                _cells.append({
                        "svc": svc, "label": lbl, "viewport": vp,
                        "env": env, "camera": cam, "base_cam_zoom": base_zoom,
                })
        # Apply current column count from the SpinBox.
        _grid.columns = int(_columns_spin.value)
        # Apply current camera zoom.
        _apply_camera_zoom()

func _exit_tree() -> void:
        _disposing = true
        # Restore saved engine settings so we don't leave the engine accelerated.
        Engine.physics_ticks_per_second = _saved_physics_ticks
        Engine.max_physics_steps_per_frame = _saved_max_physics_steps
        Engine.time_scale = 1.0
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
        var new_speed: float = SPEED_PRESETS[idx]
        if new_speed == _speed:
                return
        _speed = new_speed
        _apply_speed()

func _apply_speed() -> void:
        # Use Engine.physics_ticks_per_second to accelerate physics. This
        # increases the actual number of physics steps per wall-clock second,
        # each with a proportionally smaller delta — physics quality is
        # preserved (smaller delta = more stable integration).
        # Engine.time_scale is NOT used because in headless mode it only
        # inflates the delta without increasing step count, which degrades
        # physics.
        if _speed > 0.0:
                Engine.physics_ticks_per_second = ceili(60.0 * _speed)
                # Increase max_physics_steps_per_frame so the engine can actually
                # run that many ticks per render frame. Default cap is 8.
                Engine.max_physics_steps_per_frame = ceili(_speed * 2.0) + 8
        else:
                # Pause: set ticks to 0 so no physics steps run.
                Engine.physics_ticks_per_second = 0
                Engine.max_physics_steps_per_frame = _saved_max_physics_steps

func _on_speed_down() -> void:
        var idx: int = _speed_option.selected
        if idx > 0:
                _speed_option.selected = idx - 1

func _on_speed_up() -> void:
        var idx: int = _speed_option.selected
        if idx < SPEED_PRESETS.size() - 1:
                _speed_option.selected = idx + 1

# --- Column count control ---

func _on_columns_changed(value: float) -> void:
        if is_instance_valid(_grid):
                _grid.columns = maxi(1, int(value))

# --- Camera zoom control ---

## Adjust camera zoom by [param factor] (1.25 = zoom in, 0.8 = zoom out).
## Changes Camera2D.zoom (how much of the world the camera sees) and scales
## cell size proportionally.
func _adjust_zoom(factor: float) -> void:
        _cam_zoom = clampf(_cam_zoom * factor, MIN_CAM_ZOOM, MAX_CAM_ZOOM)
        # Scale cell size proportionally so the rendered content fills the cell.
        _cell_size = clampi(int(DEFAULT_CELL_SIZE * _cam_zoom), MIN_CELL_SIZE, MAX_CELL_SIZE)
        # Update all cell minimum sizes.
        for cell in _cells:
                var svc: SubViewportContainer = cell.svc
                if is_instance_valid(svc):
                        var cell_node: Control = svc.get_parent() as Control
                        if cell_node != null:
                                cell_node.custom_minimum_size = Vector2(_cell_size, _cell_size)
        # Apply camera zoom to all cameras.
        _apply_camera_zoom()

## Apply the current _cam_zoom to all cameras. Each camera's zoom = its
## base zoom (from the scene) * _cam_zoom.
func _apply_camera_zoom() -> void:
        for cell in _cells:
                var cam: Camera2D = cell.camera
                var base_zoom: Vector2 = cell.base_cam_zoom
                if cam != null and is_instance_valid(cam):
                        cam.zoom = base_zoom * _cam_zoom

# --- Camera pan (WASD) ---

func _apply_camera_offset() -> void:
        # Apply the pan offset to all cameras. We use offset rather than position
        # so we don't fight with the scene's authored camera position.
        for cell in _cells:
                var cam: Camera2D = cell.camera
                if cam != null and is_instance_valid(cam):
                        cam.offset = _cam_offset

# --- Input ---

func _input(event: InputEvent) -> void:
        if event is InputEventKey:
                var k := event as InputEventKey
                match k.keycode:
                        KEY_A:
                                _pan_input.x = -1.0 if k.pressed else 0.0
                                get_viewport().set_input_as_handled()
                        KEY_D:
                                _pan_input.x = 1.0 if k.pressed else 0.0
                                get_viewport().set_input_as_handled()
                        KEY_W:
                                _pan_input.y = -1.0 if k.pressed else 0.0
                                get_viewport().set_input_as_handled()
                        KEY_S:
                                _pan_input.y = 1.0 if k.pressed else 0.0
                                get_viewport().set_input_as_handled()
                        KEY_SPACE:
                                if k.pressed and not k.echo:
                                        if _speed == 0:
                                                _speed_option.selected = 1
                                        else:
                                                _speed_option.selected = 0
                                        get_viewport().set_input_as_handled()

# --- Process loop ---

func _process(delta: float) -> void:
        if not is_visible_in_tree() or _disposing:
                return
        # Continuous camera pan based on currently-held WASD keys.
        # Scale pan speed by 1/zoom so panning feels the same at any zoom level.
        if _pan_input != Vector2.ZERO:
                _cam_offset += _pan_input * CAMERA_PAN_SPEED * delta / _cam_zoom
                _apply_camera_offset()
        _update_ui()
        # Update per-env stats each frame (read from the live envs).
        _update_env_stats()
        # Start training only if speed > 0, not already stepping.
        if _speed == 0.0 or _stepping or _disposing:
                return
        if _pop == null:
                return
        _stepping = true
        _step_budget()

## Update per-env live stats by reading each env's current fitness + done
## state. Mirrors godot_rl's RLEnvStats tracking.
func _update_env_stats() -> void:
        for i in range(_cells.size()):
                if i >= _env_stats.size():
                        break
                var env: Node = _cells[i].env
                if env == null or not is_instance_valid(env):
                        continue
                var s: Dictionary = _env_stats[i]
                var cur_fit: float = env.current_fitness()
                var cur_done: bool = env.is_done()
                s["episode_reward"] = cur_fit
                if cur_fit > float(s["best_reward"]):
                        s["best_reward"] = cur_fit
                # Detect episode end: done transitioned from false to true.
                if cur_done and not bool(s["done_last_frame"]):
                        s["episode"] = int(s["episode"]) + 1
                s["done_last_frame"] = cur_done
                s["last_fitness"] = cur_fit

## Run training continuously. For physics envs (all current envs), run 1
## generation per call. _process re-launches this coroutine each frame as
## long as speed > 0. Engine.time_scale makes physics run faster.
func _step_budget() -> void:
        await _step_generation()
        _stepping = false

func _step_generation() -> void:
        if _pop == null or _disposing:
                return
        if _evaluator == null:
                return
        var fitnesses: Array[float] = await _evaluator.evaluate_all(_pop.genomes)
        if _disposing or _pop == null or not is_instance_valid(self):
                return
        for i in range(_pop.genomes.size()):
                _pop.genomes[i].fitness = fitnesses[i]
                if fitnesses[i] > _pop.best_fitness:
                        _pop.best_fitness = fitnesses[i]
                        _pop.best_genome = _pop.genomes[i].duplicate()
        if _stats_tracker != null:
                _stats_tracker.record(_pop)
        _pop.evolve()

func _update_ui() -> void:
        if _pop == null:
                return
        var state_str: String = "Paused" if _speed == 0.0 else "Running %.0fx" % _speed
        _status_label.text = "Gen %d   |   Best: %.2f   |   Species: %d   |   %s" % [
                _pop.generation, _pop.best_fitness, _pop.species_count(), state_str,
        ]
        _visualizer.refresh()
        if _save_load_view != null:
                _save_load_view.population = _pop
                _save_load_view.config = _config
        # Update cell labels with godot_rl-style stats: index, episode, reward, best.
        for i in range(_cells.size()):
                if i >= _env_stats.size():
                        break
                var lbl: Label = _cells[i].label
                if lbl == null or not is_instance_valid(lbl):
                        continue
                var s: Dictionary = _env_stats[i]
                var ep: int = int(s["episode"])
                var reward: float = float(s["episode_reward"])
                var best: float = float(s["best_reward"])
                if best <= -1e9:
                        best = 0.0
                lbl.text = "#%d  ep:%d  r:%.1f  best:%.1f" % [i, ep, reward, best]

func get_population() -> Population:
        return _pop

func get_config() -> NeatConfig:
        return _config

func get_extra() -> Dictionary:
        return _extra
