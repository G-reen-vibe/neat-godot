## Training screen: shows live env visualization + graph + stats + save/load.
##
## Left panel layout (this file):
##   HSplitContainer
##     Left (stretch=1.0):
##       VBox
##         Header (toolbar: back, config, speed down/dropdown/up, status)
##         VizToolbar (zoom in/out, reset view)
##         VizContainer (env viewport or XOR truth table)
##         HelpBar (key hints)
##     Right (fixed 420px):
##       TabContainer (Genome / Stats / Saving)
##
## Training control: speed dropdown with speed=0 (Pause) .. 50x.
##   - speed=0 (Pause): training halted; live env runs (driven by its own
##     _physics_process in live_mode).
##   - speed=N: training runs continuously. For XOR (synchronous), N generations
##     per render frame. For physics envs, training runs as fast as physics
##     allows (1 generation per evaluate_all coroutine completion); the speed
##     value is ignored for physics envs but kept for UI consistency.
##
## Live env architecture (NEW):
##   - The live env drives ITSELF via its own _physics_process when live_mode
##     is true. RunScreen does NOT call step_env/apply_action on it.
##   - When training (speed > 0): live env's set_physics_process(false), bodies
##     frozen, live_mode=false. The visualization shows a "Training..." overlay.
##   - When paused (speed == 0): live env's set_physics_process(true), bodies
##     unfrozen, live_mode=true. The env runs the live genome continuously,
##     auto-resetting when is_done() returns true.
##   - N/B changes the live genome and resets the env.
##
## N/B cycle the live genome shown in the visualization (not the graph).
## There is no "solved" state and no generation limit — training runs
## continuously until the user pauses or goes back.
extends MarginContainer
class_name RunScreen

signal back_requested()
signal config_requested()

const GraphVisualizerScene: PackedScene = preload("res://ui/components/graph_visualizer.tscn")
const TrainingStatsViewScene: PackedScene = preload("res://ui/components/training_stats_view.tscn")
const SaveLoadViewScene: PackedScene = preload("res://ui/components/save_load_view.tscn")
const EnvViewportScene: PackedScene = preload("res://ui/components/env_viewport.tscn")
const XorTruthTableScene: PackedScene = preload("res://ui/components/xor_truth_table.tscn")

# Speed presets: index in OptionButton -> generations per frame (for XOR).
# For physics envs, any speed > 0 means "train continuously".
# Index 0 is Pause (speed=0); indices 1..6 are 1x..50x.
const SPEED_PRESETS: Array[int] = [0, 1, 2, 5, 10, 25, 50]

@onready var _back_btn: Button = %BackBtn
@onready var _config_btn: Button = %ConfigBtn
@onready var _speed_down_btn: Button = %SpeedDownBtn
@onready var _speed_option: OptionButton = %SpeedOption
@onready var _speed_up_btn: Button = %SpeedUpBtn
@onready var _status_label: Label = %StatusLabel
@onready var _viz_container: PanelContainer = %VizContainer
@onready var _genome_tab: PanelContainer = %Genome
@onready var _stats_tab: PanelContainer = %Stats
@onready var _save_load_tab: PanelContainer = %Saving
@onready var _zoom_in_btn: Button = %ZoomInBtn
@onready var _zoom_out_btn: Button = %ZoomOutBtn
@onready var _reset_view_btn: Button = %ResetViewBtn

var _visualizer: GraphVisualizer
var _stats_view: TrainingStatsView
var _save_load_view: SaveLoadView
var _env_viewport: EnvViewport
var _xor_table: XorTruthTable

var _pop: Population = null
var _config: NeatConfig = null
var _extra: Dictionary = {}
var _env_idx: int = -1
var _env_scene: PackedScene = null
var _view_type: String = "2d"
# _speed: 0 = paused (live env active), >0 = training.
var _speed: int = 1
var _stepping: bool = false
var _evaluator: Variant = null  # Evaluator or SceneEvaluator
var _stats_tracker: TrainingStatsTracker = null
var _live_env: Node = null
# Set to true when the RunScreen is being freed; lets in-flight coroutines
# bail out instead of touching the disposed evaluator / freed node.
var _disposing: bool = false

# Live genome: the genome currently shown in the visualization (env replay
# or XOR truth table). Defaults to the population's best genome. N cycles
# forward through pop.genomes; B resets to best.
var _live_is_best: bool = true
var _live_idx: int = -1  # index into pop.genomes; -1 means "best"

func _ready() -> void:
        _back_btn.pressed.connect(func(): back_requested.emit())
        _config_btn.pressed.connect(func(): config_requested.emit())
        _speed_option.item_selected.connect(_on_speed_index_changed)
        _speed_down_btn.pressed.connect(_on_speed_down)
        _speed_up_btn.pressed.connect(_on_speed_up)
        _zoom_in_btn.pressed.connect(func(): _adjust_zoom(1.25))
        _zoom_out_btn.pressed.connect(func(): _adjust_zoom(1.0 / 1.25))
        _reset_view_btn.pressed.connect(_on_reset_view)
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
        _live_is_best = true
        _live_idx = -1
        _visualizer.population = pop
        _stats_tracker = TrainingStatsTracker.new()
        _stats_tracker.set_config_snapshot(config)
        _stats_view.tracker = _stats_tracker
        _save_load_view.population = pop
        _save_load_view.config = config
        _save_load_view.env_idx = env_idx
        # Determine env scene + view type.
        match env_idx:
                0:
                        _env_scene = null
                        _view_type = "xor"
                1:
                        _env_scene = load("res://environments/cartpole/cartpole_environment.tscn")
                        _view_type = "2d"
                2:
                        _env_scene = load("res://environments/acrobot/acrobot_environment.tscn")
                        _view_type = "2d"
                3:
                        _env_scene = load("res://environments/pong/pong_environment.tscn")
                        _view_type = "2d"
        await _setup_visualization()
        _setup_evaluator()
        # Start with live env frozen + physics_process off (training active by
        # default at speed=1).
        _set_live_env_active(false)
        _update_ui()

func _setup_visualization() -> void:
        for c in _viz_container.get_children():
                c.queue_free()
        # Wait a frame so queue_free takes effect before adding new children.
        await get_tree().process_frame
        if _view_type == "xor":
                _xor_table = XorTruthTableScene.instantiate()
                _viz_container.add_child(_xor_table)
                # Hide camera buttons for XOR (no spatial visualization).
                _zoom_in_btn.visible = false
                _zoom_out_btn.visible = false
                _reset_view_btn.visible = false
                _xor_table.genome = _live_genome()
        elif _env_scene != null:
                _env_viewport = EnvViewportScene.instantiate()
                _viz_container.add_child(_env_viewport)
                _env_viewport.set_env_scene(_env_scene, _view_type)
                _live_env = _env_viewport.env
                # Disable the env's _physics_process immediately — it should NOT run
                # until we explicitly enable it (when paused). During training, the
                # live env is frozen + physics_process off.
                if _live_env != null:
                        _live_env.set_physics_process(false)
                # Configure the live env's IO so the live genome can drive it.
                if _live_env != null and _live_env.has_method("set_max_steps"):
                        _live_env.set_max_steps(int(_extra.get("_max_steps", 500)))
                # Apply the same setup function used by the evaluator.
                var setup_fn: Callable = _make_env_setup_fn()
                if setup_fn.is_valid():
                        setup_fn.call(_live_env)
                # Set the live genome + forward mode on the env.
                if _live_env != null:
                        _live_env.set_live_genome(_live_genome())
                        _live_env.live_forward_mode = _config.forward_mode
                        _live_env.set_live_mode(false)
                # Reset the live env with a fixed seed for consistent visualization.
                var rng := RandomNumberGenerator.new()
                rng.seed = 12345
                _env_viewport.reset_env(_live_genome(), rng)
                _zoom_in_btn.visible = true
                _zoom_out_btn.visible = true
                _reset_view_btn.visible = true

func _setup_evaluator() -> void:
        # Dispose any previous evaluator (frees its SubViewports).
        _dispose_evaluator()
        if _env_idx == 0:
                _evaluator = Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
                _evaluator.episodes_per_genome = 1
                _evaluator.num_threads = 4
        else:
                var max_steps: int = int(_extra.get("_max_steps", 500))
                var pop_size: int = _config.population_size
                _evaluator = SceneEvaluator.new(self, _env_scene, pop_size, max_steps + 10, _config.forward_mode)
                _evaluator.episodes_per_genome = int(_extra.get("_episodes", 1))
                _evaluator.env_setup_fn = _make_env_setup_fn()

func _dispose_evaluator() -> void:
        if _evaluator == null:
                return
        if _evaluator is SceneEvaluator and is_instance_valid(_evaluator):
                (_evaluator as SceneEvaluator).dispose()
        _evaluator = null

func _exit_tree() -> void:
        # Mark as disposing first so in-flight coroutines bail out.
        _disposing = true
        # Disable the live env's _physics_process immediately so it doesn't
        # run _live_step on a partially-freed env during the next physics frame.
        if _live_env != null and is_instance_valid(_live_env):
                _live_env.set_physics_process(false)
                _live_env.set_live_mode(false)
        # Dispose the evaluator (frees its SubViewports).
        _dispose_evaluator()

func _make_xor_env() -> XorEnvironment:
        return XorEnvironment.new([0, 1], 2, 3)

func _make_env_setup_fn() -> Callable:
        var num_in: int = _config.num_inputs
        var bias_id: int = num_in
        var output_start: int = num_in + 1
        var max_steps: int = int(_extra.get("_max_steps", 500))
        var points_to_win: int = int(_extra.get("_points_to_win", 5))
        match _env_idx:
                1:
                        var ids: Array[int] = [0, 1, 2, 3]
                        return func(env: Node) -> void:
                                env.input_node_ids = ids
                                env.bias_node_id = bias_id
                                env.output_node_id = output_start
                                env.set_max_steps(max_steps)
                2:
                        var ids2: Array[int] = [0, 1, 2, 3, 4, 5]
                        return func(env: Node) -> void:
                                env.input_node_ids = ids2
                                env.bias_node_id = bias_id
                                env.output_node_id = output_start
                                env.set_max_steps(max_steps)
                3:
                        var ids3: Array[int] = [0, 1, 2, 3, 4, 5]
                        var fwd_mode: String = _config.forward_mode
                        return func(env: Node) -> void:
                                env.input_node_ids = ids3
                                env.bias_node_id = bias_id
                                env.output_node_id = output_start
                                env.points_to_win = points_to_win
                                env.set_max_steps(max_steps)
                                env.set_player_b(null)
                                env.set_forward_mode(fwd_mode)
        return Callable()

# --- Speed control ---

func _on_speed_index_changed(idx: int) -> void:
        idx = clampi(idx, 0, SPEED_PRESETS.size() - 1)
        var new_speed: int = SPEED_PRESETS[idx]
        if new_speed == _speed:
                return
        _speed = new_speed
        # Live env is active (running its own _physics_process) only when paused.
        _set_live_env_active(_speed == 0)
        if _speed == 0:
                # Just paused — reset live env so it starts fresh with the live genome.
                _reset_live_env()

func _on_speed_down() -> void:
        var idx: int = _speed_option.selected
        if idx > 0:
                # Setting `selected` fires `item_selected` which calls _on_speed_index_changed.
                # No need to call it manually — that would double-fire.
                _speed_option.selected = idx - 1

func _on_speed_up() -> void:
        var idx: int = _speed_option.selected
        if idx < SPEED_PRESETS.size() - 1:
                _speed_option.selected = idx + 1

## Activate/deactivate the live env for visualization.
## When active (paused): physics_process ON, bodies unfrozen, live_mode ON.
## When inactive (training): physics_process OFF, bodies frozen, live_mode OFF.
func _set_live_env_active(active: bool) -> void:
        if _live_env == null or not is_instance_valid(_live_env):
                return
        _live_env.set_live_mode(active)
        _live_env.set_physics_process(active)
        if _live_env.has_method("set_bodies_frozen"):
                _live_env.set_bodies_frozen(not active)
        if active:
                # Reset the env's episode counter when transitioning to active.
                _live_env.live_episode_count = 0

# --- Live genome selection (N / B keys) ---

## Returns the genome currently shown in the visualization.
func _live_genome() -> Genome:
        if _pop == null:
                return null
        if _live_is_best or _live_idx < 0 or _live_idx >= _pop.genomes.size():
                return _pop.best_genome
        return _pop.genomes[_live_idx]

## Cycle to the next genome in pop.genomes. If currently showing best,
## jump to genome 0. Wraps around.
func _next_live_genome() -> void:
        if _pop == null or _pop.genomes.is_empty():
                return
        if _live_is_best or _live_idx < 0 or _live_idx >= _pop.genomes.size():
                _live_idx = 0
        else:
                _live_idx = (_live_idx + 1) % _pop.genomes.size()
        _live_is_best = false
        _reset_live_env()

## Reset the live view to show the population's best genome.
func _show_best_live_genome() -> void:
        if _pop == null:
                return
        _live_is_best = true
        _live_idx = -1
        _reset_live_env()

## Re-bind the live genome to the env viewport / XOR table and reset the
## simulation so the new genome's behavior is shown from the start.
func _reset_live_env() -> void:
        var g: Genome = _live_genome()
        if _xor_table != null and is_instance_valid(_xor_table):
                _xor_table.genome = g
        if _env_viewport != null and is_instance_valid(_env_viewport):
                # Update the live genome on the env.
                if _live_env != null and is_instance_valid(_live_env):
                        _live_env.set_live_genome(g)
                        _live_env.live_episode_count = 0
                var rng := RandomNumberGenerator.new()
                rng.seed = 12345
                _env_viewport.reset_env(g, rng)

# --- Input ---

func _input(event: InputEvent) -> void:
        if not (event is InputEventKey and event.pressed and not event.echo):
                return
        match event.keycode:
                KEY_N:
                        _next_live_genome()
                        get_viewport().set_input_as_handled()
                KEY_B:
                        _show_best_live_genome()
                        get_viewport().set_input_as_handled()
                KEY_SPACE:
                        # Toggle between paused (speed=0) and running (speed=1).
                        if _speed == 0:
                                _speed_option.selected = 1
                        else:
                                _speed_option.selected = 0
                        # The item_selected signal fires _on_speed_index_changed.
                        get_viewport().set_input_as_handled()

# --- Process loop ---

func _process(_delta: float) -> void:
        if not is_visible_in_tree() or _disposing:
                return
        # Refresh the status label + viz overlay every render frame.
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

## Run training continuously. For XOR (synchronous), run _speed generations
## per render frame. For physics envs, run 1 generation per call (the speed
## value is ignored — physics is the bottleneck). _process will re-launch
## this coroutine each frame as long as speed > 0.
func _step_budget() -> void:
        if _env_idx == 0:
                # XOR: synchronous, run _speed generations per frame.
                var steps_done: int = 0
                while steps_done < _speed and _speed > 0 and not _disposing:
                        await _step_generation()
                        steps_done += 1
                # Yield one frame so the UI can update.
                if not _disposing:
                        await get_tree().process_frame
        else:
                # Physics envs: run 1 generation per call. The evaluator's
                # physics_frame awaits provide natural yielding. _process will
                # re-launch us next frame if speed > 0.
                await _step_generation()
        _stepping = false

func _step_generation() -> void:
        if _pop == null or _disposing:
                return
        if _evaluator == null:
                return
        var fitnesses: Array[float]
        if _evaluator is SceneEvaluator:
                fitnesses = await (_evaluator as SceneEvaluator).evaluate_all(_pop.genomes)
        elif _evaluator is Evaluator:
                fitnesses = (_evaluator as Evaluator).evaluate_all(_pop.genomes)
        else:
                return
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
        # If the live view is showing "best", update the live genome binding so
        # the paused replay uses the new best genome. If showing a specific index,
        # leave it (the index persists across generations; _live_genome() handles
        # out-of-range by falling back to best).
        if _live_is_best and _live_env != null and is_instance_valid(_live_env):
                _live_env.set_live_genome(_live_genome())

func _update_ui() -> void:
        if _pop == null:
                return
        # Build a clear multi-part status string.
        var live_str: String
        if _live_is_best or _live_idx < 0 or _live_idx >= _pop.genomes.size():
                var best_g: Genome = _pop.best_genome
                if best_g != null:
                        live_str = "Best (fit=%.2f)" % best_g.fitness
                else:
                        live_str = "Best (-)"
        else:
                var lg: Genome = _pop.genomes[_live_idx]
                live_str = "#%d (fit=%.2f)" % [_live_idx, lg.fitness]
        var state_str: String = "Paused" if _speed == 0 else "Running %dx" % _speed
        _status_label.text = "Gen %d   |   Best: %.2f   |   Species: %d   |   Live: %s   |   %s" % [
                _pop.generation, _pop.best_fitness,
                _pop.species_count(), live_str, state_str,
        ]
        _visualizer.refresh()
        if _xor_table != null and is_instance_valid(_xor_table):
                _xor_table.genome = _live_genome()
        if _stats_view != null:
                # Don't call _stats_view.refresh() here — it's expensive (rebuilds
                # species table + history labels) and TrainingStatsView._process
                # already auto-refreshes every 15 frames. Calling it every frame
                # from _update_ui was a major performance issue.
                pass
        if _save_load_view != null:
                _save_load_view.population = _pop
                _save_load_view.config = _config
        # Update the viz overlay (training indicator / genome label / episode).
        if _env_viewport != null and is_instance_valid(_env_viewport):
                var ep: int = 0
                if _live_env != null and is_instance_valid(_live_env):
                        ep = _live_env.live_episode_count
                _env_viewport.set_overlay_info({
                        "training": _speed != 0,
                        "live_label": live_str,
                        "episode": ep,
                        "gen": _pop.generation,
                        "best": _pop.best_fitness,
                })

func _adjust_zoom(factor: float) -> void:
        if _env_viewport != null and is_instance_valid(_env_viewport):
                _env_viewport.adjust_zoom(factor)

func _on_reset_view() -> void:
        if _env_viewport != null and is_instance_valid(_env_viewport):
                _env_viewport.reset_view()

func get_population() -> Population:
        return _pop

func get_config() -> NeatConfig:
        return _config

func get_extra() -> Dictionary:
        return _extra
