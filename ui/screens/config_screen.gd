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
        var schema: Array = [
                # --- Population ---
                {"section": "Population & Topology"},
                {"key": "population_size", "label": "Population Size", "type": "int", "min": 10, "max": 500, "step": 10},
                {"key": "elite_count", "label": "Elite Count (per species)", "type": "int", "min": 0, "max": 10, "step": 1},
                {"key": "_max_generations", "label": "Max Generations", "type": "int", "min": 10, "max": 5000, "step": 10},
                {"key": "use_bias", "label": "Use Bias Node", "type": "bool"},
                {"key": "hidden_activation", "label": "Hidden Activation", "type": "enum", "options": _activation_options()},
                {"key": "output_activation", "label": "Output Activation", "type": "enum", "options": _activation_options()},

                # --- Initialization ---
                {"section": "Initialization (First Generation)"},
                {"key": "init_min_hidden_nodes", "label": "Min Starting Hidden Nodes", "type": "int", "min": 0, "max": 10, "step": 1},
                {"key": "init_max_hidden_nodes", "label": "Max Starting Hidden Nodes", "type": "int", "min": 0, "max": 10, "step": 1},
                {"key": "init_min_connections", "label": "Min Starting Connections", "type": "int", "min": 1, "max": 50, "step": 1},
                {"key": "init_max_connections", "label": "Max Starting Connections", "type": "int", "min": 1, "max": 50, "step": 1},
                {"key": "init_weight_min", "label": "Init Weight Min", "type": "float", "min": -5.0, "max": 0.0, "step": 0.1},
                {"key": "init_weight_max", "label": "Init Weight Max", "type": "float", "min": 0.0, "max": 5.0, "step": 0.1},

                # --- Forward Pass ---
                {"section": "Forward Pass"},
                {"key": "forward_mode", "label": "Forward Mode", "type": "enum", "options": [
                        ["Topological (no loops, single sweep)", "topological"],
                        ["Timestep (allows loops, iterative)", "timestep"],
                ]},
                {"key": "timestep_steps", "label": "Timestep Iterations", "type": "int", "min": 1, "max": 20, "step": 1,
                 "visible_when": {"forward_mode": "timestep"}},
                {"key": "forbid_loops", "label": "Forbid Loops (required for topological)", "type": "bool",
                 "visible_when": {"forward_mode": "timestep"}},

                # --- Mutation Policy ---
                {"section": "Mutation Policy"},
                {"key": "mutation_policy_method", "label": "Mutation Policy", "type": "enum", "options": [
                        ["General (apply all enabled mutations)", "general"],
                        ["Phased Pruning (alternate growth/pruning)", "phased_pruning"],
                ]},
                {"key": "mutation_stacked", "label": "Stacked (apply all in sequence)", "type": "bool",
                 "visible_when": {"mutation_policy_method": "general"}},
                {"key": "mutation_rate_multiplier", "label": "Global Rate Multiplier", "type": "float", "min": 0.0, "max": 5.0, "step": 0.1,
                 "visible_when": {"mutation_policy_method": "general"}},
                {"key": "phased_phase_length", "label": "Phased: Phase Length (gens)", "type": "int", "min": 1, "max": 20, "step": 1,
                 "visible_when": {"mutation_policy_method": "phased_pruning"}},
                {"key": "phased_pruning_rate_multiplier", "label": "Phased: Pruning Rate Multiplier", "type": "float", "min": 1.0, "max": 10.0, "step": 0.5,
                 "visible_when": {"mutation_policy_method": "phased_pruning"}},

                # --- Weight Mutation ---
                {"section": "Weight Mutation"},
                {"key": "enable_weight_mutation", "label": "Enable Weight Mutation", "type": "bool"},
                {"key": "weight_mutation_mode", "label": "Weight Mutation Mode", "type": "enum", "options": [
                        ["Single (pick N connections, full delta)", "single"],
                        ["All (perturb ALL connections, small delta)", "all"],
                ], "visible_when": {"enable_weight_mutation": true}},
                {"key": "weight_mutator_method", "label": "Weight Distribution", "type": "enum", "options": [
                        ["Uniform (min, max delta)", "standard"],
                        ["Normal (Gaussian)", "normal"],
                ], "visible_when": {"enable_weight_mutation": true}},
                {"key": "weight_mutation_rate", "label": "Mutation Rate (prob per genome, Single mode)", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
                 "visible_when": {"enable_weight_mutation": true, "weight_mutation_mode": "single"}},
                {"key": "weight_mutation_min", "label": "Min Connections to Mutate (Single mode, 0 = probabilistic)", "type": "int", "min": 0, "max": 20, "step": 1,
                 "visible_when": {"enable_weight_mutation": true, "weight_mutation_mode": "single"}},
                {"key": "weight_mutation_delta_min", "label": "Delta Min (Uniform)", "type": "float", "min": -3.0, "max": 0.0, "step": 0.1,
                 "visible_when": {"enable_weight_mutation": true, "weight_mutator_method": "standard"}},
                {"key": "weight_mutation_delta_max", "label": "Delta Max (Uniform)", "type": "float", "min": 0.0, "max": 3.0, "step": 0.1,
                 "visible_when": {"enable_weight_mutation": true, "weight_mutator_method": "standard"}},
                {"key": "weight_mutation_normal_std", "label": "Normal Std Dev", "type": "float", "min": 0.01, "max": 3.0, "step": 0.05,
                 "visible_when": {"enable_weight_mutation": true, "weight_mutator_method": "normal"}},
                {"key": "weight_mutation_all_scale", "label": "All-Mode Scale Factor (scales delta in All mode)", "type": "float", "min": 0.01, "max": 1.0, "step": 0.01,
                 "visible_when": {"enable_weight_mutation": true, "weight_mutation_mode": "all"}},
                {"key": "weight_selector_method", "label": "Weight Selector", "type": "enum", "options": [
                        ["Standard (uniform)", "standard"],
                        ["Capped (bias to bounds)", "capped"],
                ], "visible_when": {"enable_weight_mutation": true}},
                {"key": "weight_capped_min", "label": "Capped Min Weight", "type": "float", "min": -10.0, "max": 0.0, "step": 0.1,
                 "visible_when": {"enable_weight_mutation": true, "weight_selector_method": "capped"}},
                {"key": "weight_capped_max", "label": "Capped Max Weight", "type": "float", "min": 0.0, "max": 10.0, "step": 0.1,
                 "visible_when": {"enable_weight_mutation": true, "weight_selector_method": "capped"}},

                # --- Connection Mutation ---
                {"section": "Connection Add Mutation"},
                {"key": "enable_connection_mutation", "label": "Enable Connection Mutation", "type": "bool"},
                {"key": "connection_mutation_rate", "label": "Connection Add Rate (prob per genome)", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01,
                 "visible_when": {"enable_connection_mutation": true}},
                {"key": "connection_mutation_min", "label": "Min Add Count (0 = probabilistic, 1+ = force)", "type": "int", "min": 0, "max": 10, "step": 1,
                 "visible_when": {"enable_connection_mutation": true}},
                {"key": "connection_selector_method", "label": "Connection Selector", "type": "enum", "options": [
                        ["Standard (uniform)", "standard"],
                        ["Least Used (low degree bias)", "least_used"],
                        ["Least Common (rare innovation bias)", "least_common"],
                ], "visible_when": {"enable_connection_mutation": true}},
                {"key": "connection_mutator_method", "label": "Connection Weight Distribution", "type": "enum", "options": [
                        ["Uniform (min, max)", "standard"],
                        ["Normal (Gaussian)", "normal"],
                        ["Safe Gradient (probe + accept)", "safe_gradient"],
                ], "visible_when": {"enable_connection_mutation": true}},
                {"key": "connection_weight_min", "label": "New Conn Weight Min (Uniform)", "type": "float", "min": -3.0, "max": 0.0, "step": 0.1,
                 "visible_when": {"enable_connection_mutation": true, "connection_mutator_method": "standard"}},
                {"key": "connection_weight_max", "label": "New Conn Weight Max (Uniform)", "type": "float", "min": 0.0, "max": 3.0, "step": 0.1,
                 "visible_when": {"enable_connection_mutation": true, "connection_mutator_method": "standard"}},
                {"key": "connection_weight_normal_std", "label": "New Conn Weight Std Dev (Normal)", "type": "float", "min": 0.01, "max": 3.0, "step": 0.05,
                 "visible_when": {"enable_connection_mutation": true, "connection_mutator_method": "normal"}},

                # --- Neuron Mutation ---
                {"section": "Neuron Add Mutation"},
                {"key": "enable_neuron_mutation", "label": "Enable Neuron Mutation", "type": "bool"},
                {"key": "neuron_mutation_rate", "label": "Neuron Add Rate (prob per genome)", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01,
                 "visible_when": {"enable_neuron_mutation": true}},
                {"key": "neuron_mutation_min", "label": "Min Add Count (0 = probabilistic, 1+ = force)", "type": "int", "min": 0, "max": 10, "step": 1,
                 "visible_when": {"enable_neuron_mutation": true}},
                {"key": "neuron_selector_method", "label": "Neuron Selector", "type": "enum", "options": [
                        ["Standard (uniform)", "standard"],
                        ["Least Common (rare split bias)", "least_common"],
                ], "visible_when": {"enable_neuron_mutation": true}},

                # --- Enable Mutation ---
                {"section": "Enable Mutation (re-enable disabled connections)"},
                {"key": "enable_enable_mutation", "label": "Enable Enable Mutation", "type": "bool"},
                {"key": "enable_mutation_rate", "label": "Enable Rate (prob per genome)", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01,
                 "visible_when": {"enable_enable_mutation": true}},
                {"key": "enable_mutation_min", "label": "Min Re-enable Count (0 = probabilistic, 1+ = force)", "type": "int", "min": 0, "max": 10, "step": 1,
                 "visible_when": {"enable_enable_mutation": true}},

                # --- Prune Mutation ---
                {"section": "Prune Mutation (remove connections)"},
                {"key": "enable_prune_mutation", "label": "Enable Prune Mutation", "type": "bool"},
                {"key": "prune_mutation_rate", "label": "Prune Rate (prob per genome)", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01,
                 "visible_when": {"enable_prune_mutation": true}},
                {"key": "prune_mutation_min", "label": "Min Prune Count (0 = probabilistic, 1+ = force)", "type": "int", "min": 0, "max": 10, "step": 1,
                 "visible_when": {"enable_prune_mutation": true}},
                {"key": "prune_selector_method", "label": "Prune Selector", "type": "enum", "options": [
                        ["Standard (uniform)", "standard"],
                        ["Least Weight (small |w| bias)", "least_weight"],
                ], "visible_when": {"enable_prune_mutation": true}},
                {"key": "prune_mutator_method", "label": "Prune Mutator", "type": "enum", "options": [
                        ["Disabled (any connection)", "disabled"],
                        ["Non Essential (keep outputs reachable)", "non_essential"],
                        ["Merge Pair (collapse chain neurons)", "merge"],
                ], "visible_when": {"enable_prune_mutation": true}},

                # --- Speciation ---
                {"section": "Speciation"},
                {"key": "speciation_method", "label": "Speciation Method", "type": "enum", "options": [
                        ["Single (all in one species)", "single"],
                        ["Standard (dynamic threshold)", "standard"],
                        ["Purge (top N seeds + ideal threshold)", "purge"],
                ]},
                {"key": "target_species_count", "label": "Target Species Count", "type": "int", "min": 1, "max": 30, "step": 1,
                 "visible_when_any": {"speciation_method": ["standard", "purge"]}},
                {"key": "compatibility_threshold", "label": "Initial Compatibility Threshold", "type": "float", "min": 0.1, "max": 20.0, "step": 0.1,
                 "visible_when_any": {"speciation_method": ["standard", "purge"]}},
                {"key": "threshold_up_speed", "label": "Threshold Up Speed (too many species)", "type": "float", "min": 0.01, "max": 5.0, "step": 0.01,
                 "visible_when_any": {"speciation_method": ["standard", "purge"]}},
                {"key": "threshold_down_speed", "label": "Threshold Down Speed (too few species)", "type": "float", "min": 0.01, "max": 5.0, "step": 0.01,
                 "visible_when_any": {"speciation_method": ["standard", "purge"]}},
                {"key": "min_threshold", "label": "Min Threshold Bound", "type": "float", "min": 0.1, "max": 5.0, "step": 0.1,
                 "visible_when_any": {"speciation_method": ["standard", "purge"]}},
                {"key": "max_threshold", "label": "Max Threshold Bound", "type": "float", "min": 5.0, "max": 50.0, "step": 0.5,
                 "visible_when_any": {"speciation_method": ["standard", "purge"]}},
                {"key": "merge_ratio", "label": "Merge Ratio (fraction of threshold)", "type": "float", "min": 0.1, "max": 1.0, "step": 0.05,
                 "visible_when_any": {"speciation_method": ["standard", "purge"]}},
                {"key": "max_species_count", "label": "Max Species (hard cap)", "type": "int", "min": 5, "max": 50, "step": 1,
                 "visible_when_any": {"speciation_method": ["standard", "purge"]}},

                # --- Similarity ---
                {"section": "Similarity Test"},
                {"key": "similarity_method", "label": "Similarity Test", "type": "enum", "options": [
                        ["Standard (NEAT paper: E, D, W)", "standard"],
                        ["Percentage (weight diff ratio)", "percentage"],
                ]},
                {"key": "similarity_c1", "label": "C1 (excess gene weight)", "type": "float", "min": 0.0, "max": 5.0, "step": 0.1,
                 "visible_when": {"similarity_method": "standard"}},
                {"key": "similarity_c2", "label": "C2 (disjoint gene weight)", "type": "float", "min": 0.0, "max": 5.0, "step": 0.1,
                 "visible_when": {"similarity_method": "standard"}},
                {"key": "similarity_c3", "label": "C3 (weight difference weight)", "type": "float", "min": 0.0, "max": 5.0, "step": 0.1,
                 "visible_when": {"similarity_method": "standard"}},
                {"key": "similarity_n_threshold", "label": "N Threshold (normalize if > N genes)", "type": "int", "min": 1, "max": 100, "step": 1,
                 "visible_when": {"similarity_method": "standard"}},

                # --- Generation ---
                {"section": "Generation & Crossover"},
                {"key": "generation_method", "label": "Generation Method", "type": "enum", "options": [
                        ["Asexual (mutated clones)", "asexual"],
                        ["Crossover (two parents)", "crossover"],
                        ["Mixed (asexual + crossover)", "mixed"],
                ]},
                {"key": "crossover_rate", "label": "Crossover Rate (prob of crossover)", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
                 "visible_when": {"generation_method": "mixed"}},
                {"key": "overall_crossover_method", "label": "Overall Crossover Strategy", "type": "enum", "options": [
                        ["Fitter (inherit from fitter parent)", "fitter"],
                        ["Bigger (inherit from bigger parent)", "bigger"],
                        ["Combine (union of disjoints)", "combine"],
                        ["Excluded (shared + minimal disjoints)", "excluded"],
                ], "visible_when_any": {"generation_method": ["crossover", "mixed"]}},
                {"key": "neuron_crossover_method", "label": "Neuron Crossover (shared conn weights)", "type": "enum", "options": [
                        ["Standard (random pick per conn)", "standard"],
                        ["Standard All (per-neuron parent choice)", "standard_all"],
                        ["Average (mean of both)", "average"],
                        ["Biased Average (toward fitter)", "biased_average"],
                ], "visible_when_any": {"generation_method": ["crossover", "mixed"]}},
                {"key": "biased_average_strength", "label": "Biased Average Strength", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
                 "visible_when": {"neuron_crossover_method": "biased_average"}},
                {"key": "selection_method", "label": "Parent Selection Method", "type": "enum", "options": [
                        ["Roulette (prob proportional to fitness)", "roulette"],
                        ["Inverse Roulette (prob proportional to 1/fitness)", "inverse_roulette"],
                        ["Gaussian (sample N(mean,std))", "gaussian"],
                        ["Triangular (front-loaded index)", "triangular"],
                        ["Uniform (random)", "uniform"],
                ]},
                {"key": "interspecies_rate", "label": "Interspecies Mating Rate", "type": "float", "min": 0.0, "max": 0.5, "step": 0.001},

                # --- Evaluation ---
                {"section": "Evaluation Strategy"},
                {"key": "evaluation_method", "label": "Evaluation Strategy", "type": "enum", "options": [
                        ["Equal (even split)", "equal"],
                        ["Improvement Rate (reward improving species)", "improvement_rate"],
                        ["Novelty (reward diverse species)", "novelty"],
                ]},
                {"key": "novelty_weight", "label": "Novelty Weight (bonus multiplier)", "type": "float", "min": 0.0, "max": 5.0, "step": 0.1,
                 "visible_when": {"evaluation_method": "novelty"}},

                # --- Speed ---
                {"section": "Simulation Speed"},
                {"key": "_speedup", "label": "Physics Speedup Factor", "type": "float", "min": 1.0, "max": 8.0, "step": 0.5},
        ]
        # Per-env options.
        match _env_idx:
                0:
                        schema.append_array([
                                {"section": "XOR"},
                                {"key": "_solved_threshold", "label": "Solved Fitness Threshold", "type": "float", "min": 14.0, "max": 16.0, "step": 0.1},
                        ])
                1:
                        schema.append_array([
                                {"section": "CartPole"},
                                {"key": "_max_steps", "label": "Max Steps per Episode", "type": "int", "min": 100, "max": 1000, "step": 50},
                                {"key": "_episodes", "label": "Episodes per Genome", "type": "int", "min": 1, "max": 10, "step": 1},
                        ])
                2:
                        schema.append_array([
                                {"section": "Acrobot"},
                                {"key": "_max_steps", "label": "Max Steps per Episode", "type": "int", "min": 100, "max": 1000, "step": 50},
                                {"key": "_episodes", "label": "Episodes per Genome", "type": "int", "min": 1, "max": 5, "step": 1},
                        ])
                3:
                        schema.append_array([
                                {"section": "Pong Tournament"},
                                {"key": "_points_to_win", "label": "Points to Win (per match)", "type": "int", "min": 1, "max": 11, "step": 1},
                                {"key": "_episodes", "label": "Tournament Opponents (max 3)", "type": "int", "min": 0, "max": 3, "step": 1},
                        ])
        return schema

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
        c.init_max_hidden_nodes = 0
        c.init_min_connections = 1
        c.init_max_connections = 3
        c.init_weight_min = -1.0
        c.init_weight_max = 1.0
        c.speciation_method = "purge"
        c.target_species_count = 10
        c.compatibility_threshold = 3.0
        c.threshold_up_speed = 0.3
        c.threshold_down_speed = 0.3
        c.max_species_count = 20
        c.merge_ratio = 0.5
        c.min_threshold = 0.5
        c.max_threshold = 30.0
        c.generation_method = "mixed"
        c.crossover_rate = 0.75
        c.elite_count = 1
        c.interspecies_rate = 0.001
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
        c.connection_mutation_rate = 0.05
        c.connection_mutation_min = 0
        c.connection_weight_min = -1.0
        c.connection_weight_max = 1.0
        c.connection_weight_normal_std = 0.5
        c.connection_mutator_method = "standard"
        c.connection_selector_method = "standard"
        c.enable_neuron_mutation = true
        c.neuron_mutation_rate = 0.03
        c.neuron_mutation_min = 0
        c.neuron_selector_method = "standard"
        c.enable_enable_mutation = true
        c.enable_mutation_rate = 0.05
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
        return d
