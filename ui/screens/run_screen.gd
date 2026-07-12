## Training screen: shows live env visualization + graph + stats + save/load.
extends MarginContainer
class_name RunScreen

signal back_requested()
signal config_requested()
signal restart_requested()

const GraphVisualizerScene: PackedScene = preload("res://ui/components/graph_visualizer.tscn")
const TrainingStatsViewScene: PackedScene = preload("res://ui/components/training_stats_view.tscn")
const SaveLoadViewScene: PackedScene = preload("res://ui/components/save_load_view.tscn")
const EnvViewportScene: PackedScene = preload("res://ui/components/env_viewport.tscn")
const XorTruthTableScene: PackedScene = preload("res://ui/components/xor_truth_table.tscn")

@onready var _back_btn: Button = $MainSplit/Left/Header/BackBtn
@onready var _config_btn: Button = $MainSplit/Left/Header/ConfigBtn
@onready var _restart_btn: Button = $MainSplit/Left/Header/RestartBtn
@onready var _stats_label: Label = $MainSplit/Left/Header/StatsLabel
@onready var _pause_btn: Button = $MainSplit/Left/Header/PauseBtn
@onready var _speed_btn: OptionButton = $MainSplit/Left/Header/SpeedBtn
@onready var _viz_container: PanelContainer = $MainSplit/Left/VizContainer
@onready var _help_text: Label = $MainSplit/Left/HelpBar/HelpText
@onready var _solved_label: Label = $MainSplit/Left/HelpBar/SolvedLabel
@onready var _right_tabs: TabContainer = $MainSplit/RightTabs
@onready var _genome_tab: PanelContainer = $MainSplit/RightTabs/Genome
@onready var _stats_tab: PanelContainer = $MainSplit/RightTabs/Stats
@onready var _save_load_tab: PanelContainer = $MainSplit/RightTabs/SaveLoad

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
var _auto_run: bool = false
var _solved: bool = false
var _speed: int = 1
var _stepping: bool = false
var _evaluator: Variant = null  # Evaluator or SceneEvaluator
var _stats_tracker: TrainingStatsTracker = null
var _live_env: Node = null
var _live_genome: Genome = null

func _ready() -> void:
        _back_btn.pressed.connect(func(): back_requested.emit())
        _config_btn.pressed.connect(func(): config_requested.emit())
        _restart_btn.pressed.connect(func(): restart_requested.emit())
        _pause_btn.pressed.connect(_toggle_pause)
        _speed_btn.item_selected.connect(func(idx): _speed = [1, 2, 5, 10, 100][idx])
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
        _solved = false
        _auto_run = false
        _pause_btn.text = "> Run"
        _visualizer.population = pop
        _stats_tracker = TrainingStatsTracker.new()
        _stats_tracker.record(pop)
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
                4:
                        _env_scene = load("res://environments/spider_2d/spider_walker_2d_environment.tscn")
                        _view_type = "2d"
                5:
                        _env_scene = load("res://environments/spider_3d/spider_walker_3d_environment.tscn")
                        _view_type = "3d"
        _setup_visualization()
        _setup_evaluator()

func _setup_visualization() -> void:
        for c in _viz_container.get_children():
                c.queue_free()
        if _view_type == "xor":
                _xor_table = XorTruthTableScene.instantiate()
                _viz_container.add_child(_xor_table)
        elif _env_scene != null:
                _env_viewport = EnvViewportScene.instantiate()
                _viz_container.add_child(_env_viewport)
                _env_viewport.set_env_scene(_env_scene, _view_type)
                _live_env = _env_viewport.env
                # Configure the live env's IO so the best genome can drive it.
                if _live_env != null and _live_env.has_method("set_max_steps"):
                        _live_env.set_max_steps(int(_extra.get("_max_steps", 500)))
                # Apply the same setup function used by the evaluator.
                var setup_fn: Callable = _make_env_setup_fn()
                if setup_fn.is_valid():
                        setup_fn.call(_live_env)

func _setup_evaluator() -> void:
        if _env_idx == 0:
                _evaluator = Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
                _evaluator.episodes_per_genome = 1
                _evaluator.num_threads = 4
        else:
                var speedup: float = float(_extra.get("_speedup", 2.0))
                var max_steps: int = int(_extra.get("_max_steps", 500))
                var pop_size: int = _config.population_size
                _evaluator = SceneEvaluator.new(self, _env_scene, pop_size, max_steps + 10, _config.forward_mode)
                _evaluator.speedup = speedup
                _evaluator.episodes_per_genome = int(_extra.get("_episodes", 1))
                _evaluator.env_setup_fn = _make_env_setup_fn()

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
                        return func(env: Node) -> void:
                                env.input_node_ids = ids3
                                env.bias_node_id = bias_id
                                env.output_node_id = output_start
                                env.points_to_win = points_to_win
                                env.set_player_b(null)
                4:
                        var in_ids: Array[int] = []
                        for i in range(12):
                                in_ids.append(i)
                        var out_ids: Array[int] = []
                        for i in range(8):
                                out_ids.append(13 + i)
                        return func(env: Node) -> void:
                                env.input_node_ids = in_ids
                                env.bias_node_id = 12
                                env.output_node_ids = out_ids
                5:
                        var in_ids3: Array[int] = []
                        for i in range(16):
                                in_ids3.append(i)
                        var out_ids3: Array[int] = []
                        for i in range(12):
                                out_ids3.append(17 + i)
                        return func(env: Node) -> void:
                                env.input_node_ids = in_ids3
                                env.bias_node_id = 16
                                env.output_node_ids = out_ids3
        return Callable()

func _toggle_pause() -> void:
        _auto_run = not _auto_run
        _pause_btn.text = "> Run" if not _auto_run else "|| Pause"

func _input(event: InputEvent) -> void:
        if not (event is InputEventKey and event.pressed):
                return
        match event.keycode:
                KEY_ESCAPE:
                        back_requested.emit()
                KEY_SPACE:
                        if not _stepping:
                                _stepping = true
                                await _step_generation()
                                _stepping = false
                                _update_ui()
                KEY_R:
                        _toggle_pause()

func _process(_delta: float) -> void:
        if not is_visible_in_tree():
                return
        if not _auto_run or _solved or _stepping:
                # Even when not training, drive the live env visualization.
                _drive_live_env()
                return
        if _pop == null or _pop.generation >= int(_extra.get("_max_generations", 200)):
                return
        _stepping = true
        for _i in range(_speed):
                await _step_generation()
                if _solved:
                        break
        _stepping = false
        _update_ui()
        _drive_live_env()

## Drive the live visualization env with the best genome. This is purely for
## display; it does NOT affect fitness (which is computed by the SceneEvaluator).
func _drive_live_env() -> void:
        if _live_env == null or not is_instance_valid(_live_env):
                return
        if _pop == null or _pop.best_genome == null:
                return
        if not _live_env.has_method("get_state") or not _live_env.has_method("interpret_output") or not _live_env.has_method("apply_action"):
                return
        # Reset live env when done.
        if _live_env.has_method("is_done") and _live_env.is_done():
                var rng := RandomNumberGenerator.new()
                rng.seed = 12345
                _live_env.reset(_pop.best_genome, rng)
                return
        # Apply best genome's action.
        var state: Dictionary = _live_env.get_state()
        var output: Dictionary = _pop.best_genome.forward(state, _config.forward_mode)
        var action: Dictionary = _live_env.interpret_output(output)
        _live_env.apply_action(action)

func _step_generation() -> void:
        if _pop == null:
                return
        var fitnesses: Array[float]
        if _evaluator is SceneEvaluator:
                fitnesses = await (_evaluator as SceneEvaluator).evaluate_all(_pop.genomes)
        else:
                fitnesses = (_evaluator as Evaluator).evaluate_all(_pop.genomes)
        for i in range(_pop.genomes.size()):
                _pop.genomes[i].fitness = fitnesses[i]
                if fitnesses[i] > _pop.best_fitness:
                        _pop.best_fitness = fitnesses[i]
                        _pop.best_genome = _pop.genomes[i].duplicate()
        _pop.evolve()
        if _stats_tracker != null:
                _stats_tracker.record(_pop)
        if _is_solved():
                _solved = true
                _auto_run = false
                _pause_btn.text = "> Run"

func _is_solved() -> bool:
        match _env_idx:
                0: return _pop.best_fitness >= float(_extra.get("_solved_threshold", 15.5))
                1: return _pop.best_fitness >= float(_extra.get("_max_steps", 500)) * 0.98
                2: return _pop.best_fitness >= 3.0
                3: return _pop.best_fitness >= 200.0
                4, 5: return _pop.best_fitness >= 20.0
                _: return false

func _update_ui() -> void:
        if _pop == null:
                return
        var max_gen: int = int(_extra.get("_max_generations", 200))
        var avg_conns: float = 0.0
        var avg_nodes: float = 0.0
        for g: Genome in _pop.genomes:
                avg_conns += g.connection_count()
                avg_nodes += g.node_count()
        avg_conns /= float(maxi(1, _pop.genomes.size()))
        avg_nodes /= float(maxi(1, _pop.genomes.size()))
        _stats_label.text = "  %s  |  Gen %d/%d  |  Best: %.2f  |  Species: %d  |  Nodes: %.1f  Conns: %.1f" % [
                EnvSelectScreen.ENVS[_env_idx].name, _pop.generation, max_gen, _pop.best_fitness,
                _pop.species_count(), avg_nodes, avg_conns
        ]
        _solved_label.text = "OK SOLVED!" if _solved else ""
        _visualizer.refresh()
        if _xor_table != null and _pop.best_genome != null:
                _xor_table.genome = _pop.best_genome
        if _stats_view != null:
                _stats_view.refresh()
        if _save_load_view != null:
                _save_load_view.population = _pop
                _save_load_view.config = _config

func get_population() -> Population:
        return _pop

func get_config() -> NeatConfig:
        return _config

func get_extra() -> Dictionary:
        return _extra
