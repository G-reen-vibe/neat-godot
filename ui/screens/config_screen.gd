## Configuration screen: shows NeatConfig + per-env extra params as a form.
extends MarginContainer
class_name ConfigScreen

signal back_requested()
signal start_requested(config: NeatConfig, extra: Dictionary)

const ConfigRowScene: PackedScene = preload("res://ui/components/config_row.tscn")

@onready var _back_btn: Button = $VBox/Header/BackBtn
@onready var _title: Label = $VBox/Header/Title
@onready var _rows: VBoxContainer = $VBox/Scroll/Rows
@onready var _reset_btn: Button = $VBox/Footer/ResetBtn
@onready var _start_btn: Button = $VBox/Footer/StartBtn

var _config: NeatConfig = null
var _extra: Dictionary = {}
var _env_idx: int = -1
var _row_map: Dictionary = {}  # key -> ConfigRow
var _deps: Array = []  # visibility deps

func _ready() -> void:
        _back_btn.pressed.connect(func(): back_requested.emit())
        _reset_btn.pressed.connect(func(): _build_for_env(_env_idx))
        _start_btn.pressed.connect(_on_start)

func configure_for_env(env_idx: int) -> void:
        _env_idx = env_idx
        _build_for_env(env_idx)

func _build_for_env(env_idx: int) -> void:
        _config = _make_config(env_idx)
        _extra = _make_extra(env_idx)
        _title.text = "%s -- Configuration" % EnvSelectScreen.ENVS[env_idx].name
        # Clear old rows.
        for c in _rows.get_children():
                c.queue_free()
        _row_map.clear()
        _deps.clear()
        # Build new rows.
        var schema: Array = _get_config_schema()
        for entry: Dictionary in schema:
                if entry.has("section"):
                        _rows.add_child(_make_section_header(entry.section))
                else:
                        var row := ConfigRowScene.instantiate() as ConfigRow
                        row.key = entry.key
                        row.label_text = entry.label
                        var opts := {
                                "value": _get_value(entry.key),
                                "min": entry.get("min", 0),
                                "max": entry.get("max", 100),
                                "step": entry.get("step", 1),
                                "options": entry.get("options", []),
                        }
                        row.set_kind(entry.type, opts)
                        _rows.add_child(row)
                        _row_map[entry.key] = row
                        if entry.has("visible_when"):
                                _deps.append({"key": entry.key, "conditions": entry.visible_when, "mode": "and", "row": row})
                        elif entry.has("visible_when_any"):
                                _deps.append({"key": entry.key, "conditions": entry.visible_when_any, "mode": "any", "row": row})
                        # Connect change signal for visibility updates.
                        if row.get_child_count() > 1 and row.get_child(1) is Container:
                                var ctrl: Control = (row.get_child(1) as Container).get_child(0) if (row.get_child(1) as Container).get_child_count() > 0 else null
                                if ctrl != null:
                                        if ctrl is SpinBox:
                                                (ctrl as SpinBox).value_changed.connect(_update_visibility)
                                        elif ctrl is OptionButton:
                                                (ctrl as OptionButton).item_selected.connect(_update_visibility)
                                        elif ctrl is CheckButton:
                                                (ctrl as CheckButton).toggled.connect(_update_visibility)
        _update_visibility()

func _make_section_header(text: String) -> Control:
        var vbox := VBoxContainer.new()
        vbox.add_theme_constant_override("separation", 2)
        var lbl := Label.new()
        lbl.text = text
        lbl.add_theme_font_size_override("font_size", 15)
        lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
        lbl.custom_minimum_size = Vector2(0, 28)
        vbox.add_child(lbl)
        var sep := HSeparator.new()
        sep.add_theme_constant_override("separation", 2)
        vbox.add_child(sep)
        return vbox

func _update_visibility(_v: Variant = null) -> void:
        for dep: Dictionary in _deps:
                var conditions: Dictionary = dep.conditions
                var mode: String = dep.get("mode", "and")
                var row: ConfigRow = dep.row
                if row == null or not is_instance_valid(row):
                        continue
                if mode == "any":
                        var any_match := false
                        for dep_key: String in conditions:
                                var allowed: Array = conditions[dep_key]
                                var cur = _read_value(dep_key)
                                for v in allowed:
                                        if str(cur) == str(v):
                                                any_match = true
                                                break
                                if any_match:
                                        break
                        row.visible = any_match
                else:
                        var all_match := true
                        for dep_key: String in conditions:
                                var want = conditions[dep_key]
                                var cur = _read_value(dep_key)
                                if str(cur) != str(want):
                                        all_match = false
                                        break
                        row.visible = all_match

func _read_value(key: String) -> Variant:
        var row: ConfigRow = _row_map.get(key)
        if row == null:
                return ""
        return row.get_value()

func _get_value(key: String) -> Variant:
        if key.begins_with("_"):
                return _extra.get(key)
        var val = _config.get(key)
        if val == null:
                return null
        if key.ends_with("_activation") and val is int:
                return ActivationFunctions.name_of(int(val))
        return val

func _on_start() -> void:
        # Apply all row values back to config + extra.
        for key in _row_map:
                var row: ConfigRow = _row_map[key]
                var val = row.get_value()
                if val == null:
                        continue
                if key.ends_with("_activation") and val is String:
                        val = ActivationFunctions.from_name(val)
                if key.begins_with("_"):
                        _extra[key] = val
                else:
                        _config.set(key, val)
        _config.forbid_loops = (_config.forward_mode == "topological")
        start_requested.emit(_config, _extra)

# === Config schema (defines all editable fields) ===
func _get_config_schema() -> Array:
        return [
                {"section": "Population & Topology"},
                {"key": "population_size", "label": "Population Size", "type": "int", "min": 10, "max": 500, "step": 10},
                {"key": "elite_count", "label": "Elite Count (per species)", "type": "int", "min": 0, "max": 10, "step": 1},
                {"key": "_max_generations", "label": "Max Generations", "type": "int", "min": 10, "max": 5000, "step": 10},
                {"key": "use_bias", "label": "Use Bias Node", "type": "bool"},
                {"key": "hidden_activation", "label": "Hidden Activation", "type": "enum", "options": _activation_options()},
                {"key": "output_activation", "label": "Output Activation", "type": "enum", "options": _activation_options()},
                {"section": "Forward Pass"},
                {"key": "forward_mode", "label": "Forward Mode", "type": "enum", "options": [
                        ["Topological (no loops, single sweep)", "topological"],
                        ["Timestep (allows loops, iterative)", "timestep"],
                ]},
                {"key": "timestep_steps", "label": "Timestep Iterations", "type": "int", "min": 1, "max": 20, "step": 1,
                 "visible_when": {"forward_mode": "timestep"}},
                {"section": "Mutation"},
                {"key": "enable_weight_mutation", "label": "Enable Weight Mutation", "type": "bool"},
                {"key": "weight_mutation_rate", "label": "Weight Mutation Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05},
                {"key": "enable_connection_mutation", "label": "Enable Connection Mutation", "type": "bool"},
                {"key": "connection_mutation_rate", "label": "Connection Mutation Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
                {"key": "enable_neuron_mutation", "label": "Enable Neuron Mutation", "type": "bool"},
                {"key": "neuron_mutation_rate", "label": "Neuron Mutation Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
                {"key": "enable_enable_mutation", "label": "Enable Enable Mutation", "type": "bool"},
                {"key": "enable_mutation_rate", "label": "Enable Mutation Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
                {"section": "Speciation"},
                {"key": "speciation_method", "label": "Speciation Method", "type": "enum", "options": [
                        ["Single", "single"],
                        ["Standard (dynamic threshold)", "standard"],
                        ["Purge (top N seeds)", "purge"],
                ]},
                {"key": "compatibility_threshold", "label": "Compatibility Threshold", "type": "float", "min": 0.1, "max": 20.0, "step": 0.1,
                 "visible_when_any": {"speciation_method": ["standard", "purge"]}},
                {"key": "target_species_count", "label": "Target Species Count", "type": "int", "min": 1, "max": 30, "step": 1,
                 "visible_when_any": {"speciation_method": ["standard", "purge"]}},
                {"section": "Generation"},
                {"key": "generation_method", "label": "Generation Method", "type": "enum", "options": [
                        ["Asexual", "asexual"],
                        ["Crossover", "crossover"],
                        ["Mixed", "mixed"],
                ]},
                {"key": "crossover_rate", "label": "Crossover Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
                 "visible_when_any": {"generation_method": ["crossover", "mixed"]}},
                {"key": "selection_method", "label": "Parent Selection", "type": "enum", "options": [
                        ["Roulette", "roulette"],
                        ["Inverse Roulette", "inverse_roulette"],
                        ["Gaussian", "gaussian"],
                        ["Triangular", "triangular"],
                        ["Uniform", "uniform"],
                ]},
                {"section": "Speed"},
                {"key": "_speedup", "label": "Physics Speedup Factor", "type": "float", "min": 1.0, "max": 8.0, "step": 0.5},
        ]

func _activation_options() -> Array:
        return [
                ["Linear", "linear"], ["Absolute", "abs"], ["Squared", "squared"], ["Cubed", "cubed"],
                ["Binary Step", "step"], ["Gaussian", "gaussian"], ["Sigmoid", "sigmoid"], ["Tanh", "tanh"],
                ["ReLU", "relu"], ["Leaky ReLU", "leaky_relu"], ["ELU", "elu"], ["SeLU", "selu"],
                ["GELU", "gelu"], ["Swish", "swish"],
        ]

# === Defaults per env ===
func _make_config(env_idx: int) -> NeatConfig:
        var c := NeatConfig.new()
        c.use_bias = true
        c.input_activation = ActivationFunctions.Func.LINEAR
        c.output_activation = ActivationFunctions.Func.TANH
        c.hidden_activation = ActivationFunctions.Func.TANH
        c.forward_mode = "topological"
        c.timestep_steps = 5
        c.forbid_loops = true
        c.init_min_hidden_nodes = 0
        c.init_max_hidden_nodes = 3
        c.init_min_connections = 5
        c.init_max_connections = 20
        c.init_weight_min = -1.0
        c.init_weight_max = 1.0
        c.speciation_method = "standard"
        c.target_species_count = 8
        c.compatibility_threshold = 6.0
        c.threshold_up_speed = 0.3
        c.threshold_down_speed = 0.3
        c.max_species_count = 20
        c.merge_ratio = 0.5
        c.min_threshold = 0.5
        c.max_threshold = 15.0
        c.generation_method = "asexual"
        c.crossover_rate = 0.75
        c.elite_count = 1
        c.interspecies_rate = 0.01
        c.selection_method = "roulette"
        c.evaluation_method = "equal"
        c.mutation_policy_method = "general"
        c.mutation_stacked = true
        c.mutation_rate_multiplier = 1.0
        c.phased_phase_length = 5
        c.phased_pruning_rate_multiplier = 3.0
        c.enable_weight_mutation = true
        c.weight_mutation_mode = "single"
        c.weight_mutation_rate = 0.8
        c.weight_mutation_min = 1
        c.weight_mutation_delta_min = -0.5
        c.weight_mutation_delta_max = 0.5
        c.weight_mutation_normal_std = 0.5
        c.weight_mutation_all_scale = 0.1
        c.weight_mutator_method = "standard"
        c.weight_selector_method = "standard"
        c.weight_capped_min = -3.0
        c.weight_capped_max = 3.0
        c.enable_connection_mutation = true
        c.connection_mutation_rate = 0.3
        c.connection_mutation_min = 0
        c.connection_weight_min = -1.0
        c.connection_weight_max = 1.0
        c.connection_weight_normal_std = 0.5
        c.connection_mutator_method = "standard"
        c.connection_selector_method = "standard"
        c.enable_neuron_mutation = true
        c.neuron_mutation_rate = 0.2
        c.neuron_mutation_min = 0
        c.neuron_selector_method = "standard"
        c.enable_enable_mutation = true
        c.enable_mutation_rate = 0.3
        c.enable_mutation_min = 0
        c.enable_prune_mutation = false
        c.prune_mutation_rate = 0.01
        c.prune_mutation_min = 0
        c.prune_selector_method = "standard"
        c.prune_mutator_method = "disabled"
        c.similarity_method = "standard"
        c.similarity_c1 = 1.0
        c.similarity_c2 = 1.0
        c.similarity_c3 = 0.4
        c.similarity_n_threshold = 20
        c.overall_crossover_method = "fitter"
        c.neuron_crossover_method = "standard"
        c.biased_average_strength = 0.5
        c.novelty_weight = 1.0
        match env_idx:
                0:
                        c.num_inputs = 2
                        c.num_outputs = 1
                        c.output_activation = ActivationFunctions.Func.SIGMOID
                        c.population_size = 150
                1:
                        c.num_inputs = 4
                        c.num_outputs = 1
                        c.population_size = 100
                2:
                        c.num_inputs = 6
                        c.num_outputs = 1
                        c.population_size = 100
                3:
                        c.num_inputs = 6
                        c.num_outputs = 1
                        c.population_size = 80
                4:
                        c.num_inputs = 12
                        c.num_outputs = 8
                        c.population_size = 80
                5:
                        c.num_inputs = 16
                        c.num_outputs = 12
                        c.population_size = 60
        return c

func _make_extra(env_idx: int) -> Dictionary:
        var d: Dictionary = {"_max_generations": 200, "_speedup": 2.0}
        match env_idx:
                0: d["_solved_threshold"] = 15.5
                1:
                        d["_max_steps"] = 500
                        d["_episodes"] = 3
                2:
                        d["_max_steps"] = 500
                        d["_episodes"] = 2
                3:
                        d["_points_to_win"] = 5
                        d["_episodes"] = 3
                4: d["_max_steps"] = 1000
                5: d["_max_steps"] = 1000
        return d
