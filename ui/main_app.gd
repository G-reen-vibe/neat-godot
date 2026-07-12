extends Control
## ============================================================
## NEAT Godot — Main Application
## ============================================================
## A proper multi-screen UI for training NEAT networks:
##   1. Environment Selection — pick one of 6 envs
##   2. Configuration — tune hyperparameters with sensible defaults
##   3. Training — live visualization + graph view + stats
##
## Controls (Training screen):
##   V        — cycle visualization mode (Top / Parallel / Off)
##   Space    — step one generation manually
##   R        — toggle auto-run
##   N / B    — next genome / best genome (in Top view)
##   Arrows   — pan camera
##   +/-/0    — zoom in / out / reset
##   ESC      — back to environment selection
## ============================================================

# === Screen state ===
enum ScreenState { ENV_SELECT, CONFIG, RUNNING }

# === Environment descriptors ===
const ENVS: Array = [
        {
                "name": "XOR",
                "desc": "Classic NEAT benchmark.\nLearn the XOR truth table.",
                "color": Color(0.3, 0.8, 0.4),
                "has_viz": false,
                "needs_custom_eval": false,
        },
        {
                "name": "CartPole",
                "desc": "Balance a pole on\na moving cart. 2D physics.",
                "color": Color(0.3, 0.7, 1.0),
                "has_viz": true,
                "needs_custom_eval": false,
        },
        {
                "name": "Acrobot",
                "desc": "Swing up a two-link\nunderactuated pendulum.",
                "color": Color(0.9, 0.6, 0.2),
                "has_viz": true,
                "needs_custom_eval": false,
        },
        {
                "name": "Pong",
                "desc": "Play pong vs top-3 from\nprevious gen (tournament).",
                "color": Color(0.9, 0.3, 0.5),
                "has_viz": true,
                "needs_custom_eval": true,
        },
        {
                "name": "Spider 2D",
                "desc": "Walk a 4-legged creature\nforward (2D side view).",
                "color": Color(0.7, 0.5, 0.9),
                "has_viz": true,
                "needs_custom_eval": false,
        },
        {
                "name": "Spider 3D",
                "desc": "Walk a 4-legged creature\nforward (3D top-down).",
                "color": Color(0.5, 0.9, 0.7),
                "has_viz": true,
                "needs_custom_eval": false,
        },
]

# === State ===
var _screen: int = ScreenState.ENV_SELECT
var _env_idx: int = -1
var _config: NeatConfig = null
var _extra: Dictionary = {}
var _pop: Population = null
var _evaluator: Evaluator = null
var _env_factory: Callable = Callable()
var _auto_run: bool = true
var _solved: bool = false
var _speed: int = 1
var _pong_opponents: Array = []

# === UI: screen containers ===
var _screens: Dictionary = {}

# === UI: config controls ===
var _config_controls: Dictionary = {}  # key -> Control
var _config_deps: Array = []  # Array of {control, dependents: [keys], values: [show_when]}
var _config_title: Label = null
var _config_scroll: ScrollContainer = null

# === UI: run screen elements ===
var _sim_viewport: SimulationViewport = null
var _visualizer: GraphVisualizer = null
var _xor_table: XorTruthTable = null
var _viz_container: Control = null
var _stats_label: Label = null
var _pause_btn: Button = null
var _speed_btn: OptionButton = null
var _solved_label: Label = null

# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
        set_anchors_preset(PRESET_FULL_RECT)
        var bg := ColorRect.new()
        bg.set_anchors_preset(PRESET_FULL_RECT)
        bg.color = Color(0.06, 0.06, 0.10)
        add_child(bg)
        _build_env_select_screen()
        _build_config_screen()
        _build_run_screen()
        _show_screen(ScreenState.ENV_SELECT)

func _process(_delta: float) -> void:
        if _screen != ScreenState.RUNNING or not _auto_run or _solved:
                return
        if _pop == null or _pop.generation >= int(_extra.get("_max_generations", 200)):
                return
        for _i in range(_speed):
                _step_generation()
                if _solved:
                        break
        _update_run_ui()

func _input(event: InputEvent) -> void:
        if not (event is InputEventKey and event.pressed):
                return
        match _screen:
                ScreenState.ENV_SELECT:
                        if event.keycode == KEY_ESCAPE:
                                get_tree().quit()
                ScreenState.CONFIG:
                        if event.keycode == KEY_ESCAPE:
                                _show_screen(ScreenState.ENV_SELECT)
                ScreenState.RUNNING:
                        match event.keycode:
                                KEY_ESCAPE:
                                        _show_screen(ScreenState.ENV_SELECT)
                                KEY_SPACE:
                                        _step_generation()
                                        _update_run_ui()
                                KEY_R:
                                        _toggle_pause()

# ============================================================
# Screen management
# ============================================================

func _show_screen(s: int) -> void:
        for k in _screens:
                (_screens[k] as Control).visible = (k == s)
        _screen = s

# ============================================================
# Screen 1: Environment Selection
# ============================================================

func _build_env_select_screen() -> void:
        var container := Control.new()
        container.set_anchors_preset(PRESET_FULL_RECT)
        # Title.
        var title := Label.new()
        title.text = "NEAT Godot — Select Environment"
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.add_theme_font_size_override("font_size", 26)
        title.position = Vector2(0, 30)
        title.size = Vector2(container.size.x, 40)
        container.add_child(title)
        # Subtitle.
        var subtitle := Label.new()
        subtitle.text = "Choose an environment to train. You can configure hyperparameters on the next screen."
        subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        subtitle.add_theme_font_size_override("font_size", 13)
        subtitle.position = Vector2(0, 70)
        subtitle.size = Vector2(container.size.x, 20)
        subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
        container.add_child(subtitle)
        # Grid of env cards.
        var grid := GridContainer.new()
        grid.columns = 3
        grid.add_theme_constant_override("h_separation", 16)
        grid.add_theme_constant_override("v_separation", 16)
        grid.position = Vector2(0, 110)
        grid.size = Vector2(container.size.x, container.size.y - 130)
        # Center the grid using a CenterContainer.
        var center := CenterContainer.new()
        center.set_anchors_preset(PRESET_FULL_RECT)
        center.offset_top = 100
        center.offset_bottom = -20
        for i in range(ENVS.size()):
                var card := _make_env_card(i)
                grid.add_child(card)
        center.add_child(grid)
        container.add_child(center)
        # Footer.
        var footer := Label.new()
        footer.text = "ESC to quit  |  Click an environment to begin"
        footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        footer.add_theme_font_size_override("font_size", 12)
        footer.position = Vector2(0, container.size.y - 25)
        footer.size = Vector2(container.size.x, 20)
        footer.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
        container.add_child(footer)
        _screens[ScreenState.ENV_SELECT] = container
        add_child(container)

func _make_env_card(idx: int) -> Control:
        var env: Dictionary = ENVS[idx]
        var btn := Button.new()
        btn.custom_minimum_size = Vector2(280, 140)
        btn.text = ""
        btn.pressed.connect(_select_env.bind(idx))
        # Stylebox for colored card.
        var sb := StyleBoxFlat.new()
        sb.bg_color = (env["color"] as Color).darkened(0.75)
        sb.border_color = env["color"] as Color
        sb.border_width_left = 2
        sb.border_width_right = 2
        sb.border_width_top = 2
        sb.border_width_bottom = 2
        sb.corner_radius_top_left = 10
        sb.corner_radius_top_right = 10
        sb.corner_radius_bottom_left = 10
        sb.corner_radius_bottom_right = 10
        sb.content_margin_left = 12
        sb.content_margin_right = 12
        sb.content_margin_top = 10
        sb.content_margin_bottom = 10
        btn.add_theme_stylebox_override("normal", sb)
        var sb_hover := sb.duplicate()
        sb_hover.bg_color = (env["color"] as Color).darkened(0.6)
        btn.add_theme_stylebox_override("hover", sb_hover)
        var sb_pressed := sb.duplicate()
        sb_pressed.bg_color = (env["color"] as Color).darkened(0.5)
        btn.add_theme_stylebox_override("pressed", sb_pressed)
        # Card content (label + description).
        var vbox := VBoxContainer.new()
        vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
        vbox.add_theme_constant_override("separation", 6)
        btn.add_child(vbox)
        var name_lbl := Label.new()
        name_lbl.text = env["name"]
        name_lbl.add_theme_font_size_override("font_size", 18)
        name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        name_lbl.add_theme_color_override("font_color", env["color"] as Color)
        name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
        vbox.add_child(name_lbl)
        var desc_lbl := Label.new()
        desc_lbl.text = env["desc"]
        desc_lbl.add_theme_font_size_override("font_size", 12)
        desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
        desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
        vbox.add_child(desc_lbl)
        return btn

func _select_env(idx: int) -> void:
        _env_idx = idx
        _config = _make_config(idx)
        _extra = _make_extra(idx)
        _build_config_controls()
        _show_screen(ScreenState.CONFIG)

# ============================================================
# Screen 2: Configuration
# ============================================================

func _build_config_screen() -> void:
        var container := Control.new()
        container.set_anchors_preset(PRESET_FULL_RECT)
        container.visible = false
        # Header bar.
        var header := HBoxContainer.new()
        header.position = Vector2(0, 0)
        header.size = Vector2(container.size.x, 50)
        var back_btn := Button.new()
        back_btn.text = "← Back"
        back_btn.custom_minimum_size = Vector2(100, 36)
        back_btn.pressed.connect(func(): _show_screen(ScreenState.ENV_SELECT))
        header.add_child(back_btn)
        var title := Label.new()
        title.text = ""
        title.add_theme_font_size_override("font_size", 20)
        title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        title.position.y = 8
        header.add_child(title)
        _config_title = title
        container.add_child(header)
        # Scrollable config area.
        var scroll := ScrollContainer.new()
        scroll.position = Vector2(0, 50)
        scroll.size = Vector2(container.size.x, container.size.y - 120)
        container.add_child(scroll)
        _config_scroll = scroll
        # Footer bar.
        var footer := HBoxContainer.new()
        footer.position = Vector2(0, container.size.y - 60)
        footer.size = Vector2(container.size.x, 50)
        var reset_btn := Button.new()
        reset_btn.text = "Reset Defaults"
        reset_btn.custom_minimum_size = Vector2(140, 36)
        reset_btn.pressed.connect(_reset_config_defaults)
        footer.add_child(reset_btn)
        var spacer := Control.new()
        spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        footer.add_child(spacer)
        var start_btn := Button.new()
        start_btn.text = "Start Training →"
        start_btn.custom_minimum_size = Vector2(160, 36)
        start_btn.pressed.connect(_start_training)
        footer.add_child(start_btn)
        container.add_child(footer)
        _screens[ScreenState.CONFIG] = container
        add_child(container)

func _build_config_controls() -> void:
        var scroll: ScrollContainer = _config_scroll
        # Clear old content.
        for c in scroll.get_children():
                c.free()
        _config_controls.clear()
        _config_deps.clear()
        # Update title.
        _config_title.text = "  %s — Configuration" % ENVS[_env_idx]["name"]
        # Build VBox for config rows.
        var vbox := VBoxContainer.new()
        vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        vbox.add_theme_constant_override("separation", 4)
        scroll.add_child(vbox)
        # Build rows from schema.
        var schema: Array = _get_config_schema()
        for entry: Dictionary in schema:
                if entry.has("section"):
                        vbox.add_child(_make_section_header(entry["section"]))
                else:
                        var row := _make_config_row(entry)
                        vbox.add_child(row)
                        # Track dependencies for conditional visibility.
                        if entry.has("visible_when"):
                                _config_deps.append({
                                        "key": entry["key"],
                                        "dep_key": entry["visible_when"].keys()[0],
                                        "dep_value": entry["visible_when"].values()[0],
                                        "row": row,
                                })
        # Apply initial visibility.
        _update_config_visibility()

func _make_section_header(text: String) -> Control:
        var lbl := Label.new()
        lbl.text = text
        lbl.add_theme_font_size_override("font_size", 15)
        lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
        lbl.custom_minimum_size = Vector2(0, 28)
        # Add separator.
        var sep := HSeparator.new()
        sep.add_theme_constant_override("separation", 2)
        var container := VBoxContainer.new()
        container.add_child(lbl)
        container.add_child(sep)
        return container

func _make_config_row(entry: Dictionary) -> Control:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        var lbl := Label.new()
        lbl.text = entry["label"]
        lbl.custom_minimum_size = Vector2(240, 24)
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
        row.add_child(lbl)
        var type: String = entry["type"]
        match type:
                "int":
                        var spin := SpinBox.new()
                        spin.min_value = entry.get("min", 0)
                        spin.max_value = entry.get("max", 9999)
                        spin.step = entry.get("step", 1)
                        spin.value = _get_config_value(entry["key"])
                        spin.custom_minimum_size = Vector2(120, 28)
                        spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                        spin.value_changed.connect(_on_config_changed)
                        _config_controls[entry["key"]] = spin
                        row.add_child(spin)
                "float":
                        var spin := SpinBox.new()
                        spin.min_value = entry.get("min", 0.0)
                        spin.max_value = entry.get("max", 999.0)
                        spin.step = entry.get("step", 0.1)
                        spin.value = _get_config_value(entry["key"])
                        spin.custom_minimum_size = Vector2(120, 28)
                        spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                        spin.value_changed.connect(_on_config_changed)
                        _config_controls[entry["key"]] = spin
                        row.add_child(spin)
                "enum":
                        var opt := OptionButton.new()
                        var options: Array = entry["options"]
                        var current_val: String = _get_config_value(entry["key"])
                        for i in range(options.size()):
                                var opt_entry: Array = options[i]
                                opt.add_item(opt_entry[0])
                                # Store the value string as metadata for this item.
                                opt.set_item_metadata(i, opt_entry[1])
                                if opt_entry[1] == current_val:
                                        opt.selected = i
                        opt.custom_minimum_size = Vector2(180, 28)
                        opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                        opt.item_selected.connect(_on_config_changed)
                        _config_controls[entry["key"]] = opt
                        row.add_child(opt)
                "bool":
                        var chk := CheckButton.new()
                        chk.button_pressed = _get_config_value(entry["key"])
                        chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                        chk.toggled.connect(_on_config_changed)
                        _config_controls[entry["key"]] = chk
                        row.add_child(chk)
        return row

func _get_config_value(key: String) -> Variant:
        # Keys starting with "_" are stored in _extra; others in _config.
        if key.begins_with("_"):
                return _extra.get(key)
        # Try to get from _config using property name.
        if _config.get(key) != null:
                return _config.get(key)
        return null

func _on_config_changed(_val: Variant = null) -> void:
        _update_config_visibility()

func _update_config_visibility() -> void:
        for dep: Dictionary in _config_deps:
                var dep_key: String = dep["dep_key"]
                var dep_value: String = dep["dep_value"]
                var ctrl: Control = _config_controls.get(dep_key)
                if ctrl == null:
                        continue
                var current_val: String = _read_control_value(dep_key)
                var row: Control = dep.get("row")
                if row != null and is_instance_valid(row):
                        row.visible = (current_val == dep_value)

func _read_control_value(key: String) -> String:
        var ctrl: Control = _config_controls.get(key)
        if ctrl == null:
                return ""
        if ctrl is SpinBox:
                return str((ctrl as SpinBox).value)
        if ctrl is OptionButton:
                var opt := ctrl as OptionButton
                if opt.selected >= 0 and opt.selected < opt.item_count:
                        return str(opt.get_item_metadata(opt.selected))
        if ctrl is CheckButton:
                return "true" if (ctrl as CheckButton).button_pressed else "false"
        return ""

func _read_control_value_mapped(key: String, schema: Array) -> Variant:
        var ctrl: Control = _config_controls.get(key)
        if ctrl == null:
                return null
        if ctrl is SpinBox:
                var spin := ctrl as SpinBox
                # Check if this key should be int or float.
                for entry: Dictionary in schema:
                        if entry.get("key") == key:
                                if entry.get("type") == "int":
                                        return int(spin.value)
                                else:
                                        return spin.value
                return spin.value
        if ctrl is OptionButton:
                var opt := ctrl as OptionButton
                if opt.selected >= 0 and opt.selected < opt.item_count:
                        return opt.get_item_metadata(opt.selected)
                return ""
        if ctrl is CheckButton:
                return (ctrl as CheckButton).button_pressed
        return null

func _apply_config() -> void:
        var schema: Array = _get_config_schema()
        for entry: Dictionary in schema:
                if entry.has("section"):
                        continue
                var key: String = entry["key"]
                var val: Variant = _read_control_value_mapped(key, schema)
                if val == null:
                        continue
                if key.begins_with("_"):
                        _extra[key] = val
                else:
                        _config.set(key, val)
        # Derived: forbid_loops must be true for topological mode.
        _config.forbid_loops = (_config.forward_mode == "topological")

func _reset_config_defaults() -> void:
        _config = _make_config(_env_idx)
        _extra = _make_extra(_env_idx)
        _build_config_controls()

func _start_training() -> void:
        _apply_config()
        _env_factory = _make_env_factory(_env_idx)
        if not ENVS[_env_idx]["needs_custom_eval"]:
                _evaluator = _make_evaluator(_env_idx, _env_factory, _config)
        _pop = Population.new(_config)
        _pop.initialize()
        _pong_opponents.clear()
        _solved = false
        _auto_run = true
        _speed = 1
        _setup_run_for_env()
        _show_screen(ScreenState.RUNNING)
        _update_run_ui()

# ============================================================
# Config schema
# ============================================================

func _get_config_schema() -> Array:
        var schema: Array = [
                {"section": "Population"},
                {"key": "population_size", "label": "Population Size", "type": "int", "min": 10, "max": 500, "step": 10},
                {"key": "elite_count", "label": "Elite Count", "type": "int", "min": 0, "max": 10, "step": 1},
                {"key": "_max_generations", "label": "Max Generations", "type": "int", "min": 10, "max": 2000, "step": 10},
                {"section": "Mutation"},
                {"key": "weight_mutation_rate", "label": "Weight Mutation Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05},
                {"key": "connection_mutation_rate", "label": "Connection Mutation Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05},
                {"key": "neuron_mutation_rate", "label": "Neuron Mutation Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05},
                {"key": "enable_mutation_rate", "label": "Enable Mutation Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05},
                {"section": "Speciation"},
                {"key": "speciation_method", "label": "Speciation Method", "type": "enum", "options": [
                        ["Single", "single"], ["Standard", "standard"], ["Purge", "purge"]
                ]},
                {"key": "compatibility_threshold", "label": "Compatibility Threshold", "type": "float", "min": 1.0, "max": 15.0, "step": 0.5,
                 "visible_when": {"speciation_method": "standard"}},
                {"key": "target_species_count", "label": "Target Species Count", "type": "int", "min": 1, "max": 30, "step": 1,
                 "visible_when": {"speciation_method": "standard"}},
                {"section": "Generation"},
                {"key": "generation_method", "label": "Generation Method", "type": "enum", "options": [
                        ["Asexual", "asexual"], ["Crossover", "crossover"], ["Mixed", "mixed"]
                ]},
                {"key": "crossover_rate", "label": "Crossover Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
                 "visible_when": {"generation_method": "mixed"}},
                {"key": "selection_method", "label": "Selection Method", "type": "enum", "options": [
                        ["Roulette", "roulette"], ["Inverse Roulette", "inverse_roulette"],
                        ["Gaussian", "gaussian"], ["Triangular", "triangular"], ["Uniform", "uniform"]
                ]},
                {"key": "evaluation_method", "label": "Evaluation Strategy", "type": "enum", "options": [
                        ["Equal", "equal"], ["Improvement Rate", "improvement_rate"], ["Novelty", "novelty"]
                ]},
                {"key": "forward_mode", "label": "Forward Mode", "type": "enum", "options": [
                        ["Topological (no loops)", "topological"], ["Timestep (allows loops)", "timestep"]
                ]},
        ]
        # Env-specific options.
        match _env_idx:
                0: # XOR
                        schema.append_array([
                                {"section": "XOR"},
                                {"key": "_solved_threshold", "label": "Solved Fitness Threshold", "type": "float", "min": 14.0, "max": 16.0, "step": 0.1},
                        ])
                1: # CartPole
                        schema.append_array([
                                {"section": "CartPole"},
                                {"key": "_max_steps", "label": "Max Steps per Episode", "type": "int", "min": 100, "max": 1000, "step": 50},
                                {"key": "_episodes", "label": "Episodes per Genome", "type": "int", "min": 1, "max": 10, "step": 1},
                        ])
                2: # Acrobot
                        schema.append_array([
                                {"section": "Acrobot"},
                                {"key": "_max_steps", "label": "Max Steps per Episode", "type": "int", "min": 100, "max": 1000, "step": 50},
                                {"key": "_episodes", "label": "Episodes per Genome", "type": "int", "min": 1, "max": 5, "step": 1},
                        ])
                3: # Pong
                        schema.append_array([
                                {"section": "Pong Tournament"},
                                {"key": "_points_to_win", "label": "Points to Win (per match)", "type": "int", "min": 1, "max": 11, "step": 1},
                                {"key": "_episodes", "label": "Tournament Opponents (max 3)", "type": "int", "min": 0, "max": 3, "step": 1},
                        ])
                4, 5: # Spider 2D / 3D
                        schema.append_array([
                                {"section": "Spider Walker"},
                                {"key": "_max_steps", "label": "Max Steps per Episode", "type": "int", "min": 200, "max": 2000, "step": 100},
                        ])
        return schema

# ============================================================
# Screen 3: Training
# ============================================================

func _build_run_screen() -> void:
        var container := Control.new()
        container.set_anchors_preset(PRESET_FULL_RECT)
        container.visible = false
        # Main horizontal split: left (viz+stats) | right (graph viz).
        var main_hbox := HBoxContainer.new()
        main_hbox.set_anchors_preset(PRESET_FULL_RECT)
        main_hbox.offset_left = 4
        main_hbox.offset_top = 4
        main_hbox.offset_right = -4
        main_hbox.offset_bottom = -4
        main_hbox.add_theme_constant_override("separation", 4)
        container.add_child(main_hbox)
        # Left side: header + viz area + controls.
        var left_vbox := VBoxContainer.new()
        left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        left_vbox.add_theme_constant_override("separation", 4)
        main_hbox.add_child(left_vbox)
        # Header bar.
        var header := HBoxContainer.new()
        header.add_theme_constant_override("separation", 8)
        var back_btn := Button.new()
        back_btn.text = "← Menu"
        back_btn.custom_minimum_size = Vector2(90, 32)
        back_btn.pressed.connect(func(): _show_screen(ScreenState.ENV_SELECT))
        header.add_child(back_btn)
        var config_btn := Button.new()
        config_btn.text = "⚙ Config"
        config_btn.custom_minimum_size = Vector2(90, 32)
        config_btn.pressed.connect(func():
                _show_screen(ScreenState.CONFIG)
                _build_config_controls()
        )
        header.add_child(config_btn)
        var restart_btn := Button.new()
        restart_btn.text = "↻ Restart"
        restart_btn.custom_minimum_size = Vector2(90, 32)
        restart_btn.pressed.connect(_restart_training)
        header.add_child(restart_btn)
        _stats_label = Label.new()
        _stats_label.text = ""
        _stats_label.add_theme_font_size_override("font_size", 13)
        _stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _stats_label.position.y = 6
        header.add_child(_stats_label)
        _pause_btn = Button.new()
        _pause_btn.text = "⏸ Pause"
        _pause_btn.custom_minimum_size = Vector2(90, 32)
        _pause_btn.pressed.connect(_toggle_pause)
        header.add_child(_pause_btn)
        _speed_btn = OptionButton.new()
        _speed_btn.add_item("1×")
        _speed_btn.add_item("2×")
        _speed_btn.add_item("5×")
        _speed_btn.add_item("10×")
        _speed_btn.add_item("Max")
        _speed_btn.selected = 0
        _speed_btn.custom_minimum_size = Vector2(70, 32)
        _speed_btn.item_selected.connect(func(idx): _speed = [1, 2, 5, 10, 100][idx])
        header.add_child(_speed_btn)
        left_vbox.add_child(header)
        # Visualization container.
        _viz_container = Panel.new()
        _viz_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
        _viz_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var viz_bg := StyleBoxFlat.new()
        viz_bg.bg_color = Color(0.04, 0.04, 0.07)
        _viz_container.add_theme_stylebox_override("panel", viz_bg)
        left_vbox.add_child(_viz_container)
        # Controls help bar.
        var help_bar := HBoxContainer.new()
        help_bar.add_theme_constant_override("separation", 16)
        var help_text := Label.new()
        help_text.text = "V=cycle viz  Space=step  R=pause  N/B=genome  Arrows=pan  +/-/0=zoom  ESC=back"
        help_text.add_theme_font_size_override("font_size", 11)
        help_text.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
        help_bar.add_child(help_text)
        _solved_label = Label.new()
        _solved_label.text = ""
        _solved_label.add_theme_font_size_override("font_size", 14)
        _solved_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
        _solved_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _solved_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        help_bar.add_child(_solved_label)
        left_vbox.add_child(help_bar)
        # Right side: graph visualizer.
        _visualizer = GraphVisualizer.new()
        _visualizer.custom_minimum_size = Vector2(380, 500)
        main_hbox.add_child(_visualizer)
        _screens[ScreenState.RUNNING] = container
        add_child(container)

func _setup_run_for_env() -> void:
        # Clear existing viz children.
        for c in _viz_container.get_children():
                _viz_container.remove_child(c)
                c.queue_free()
        _sim_viewport = null
        _xor_table = null
        _visualizer.population = _pop
        if ENVS[_env_idx]["has_viz"]:
                # Add SimulationViewport.
                _sim_viewport = SimulationViewport.new()
                _sim_viewport.set_anchors_preset(PRESET_FULL_RECT)
                _sim_viewport.offset_left = 4
                _sim_viewport.offset_top = 4
                _sim_viewport.offset_right = -4
                _sim_viewport.offset_bottom = -4
                _sim_viewport.population = _pop
                _sim_viewport.env_factory = _env_factory
                _sim_viewport.forward_mode = _config.forward_mode
                _sim_viewport.mode = SimulationViewport.Mode.TOP
                _viz_container.add_child(_sim_viewport)
        else:
                # XOR: add truth table.
                _xor_table = XorTruthTable.new()
                _xor_table.set_anchors_preset(PRESET_FULL_RECT)
                _xor_table.offset_left = 20
                _xor_table.offset_top = 20
                _xor_table.offset_right = -20
                _xor_table.offset_bottom = -20
                _viz_container.add_child(_xor_table)

func _toggle_pause() -> void:
        _auto_run = not _auto_run
        if _pause_btn:
                _pause_btn.text = "▶ Run" if not _auto_run else "⏸ Pause"

func _restart_training() -> void:
        if _evaluator != null or ENVS[_env_idx]["needs_custom_eval"]:
                _pop = Population.new(_config)
                _pop.initialize()
                _pong_opponents.clear()
                _solved = false
                _auto_run = true
                _setup_run_for_env()
                _update_run_ui()

# ============================================================
# Training logic
# ============================================================

func _step_generation() -> void:
        if _pop == null:
                return
        if ENVS[_env_idx]["needs_custom_eval"]:
                _step_pong_generation()
        else:
                var fitnesses: Array[float] = _evaluator.evaluate_all(_pop.genomes)
                for i in range(_pop.genomes.size()):
                        _pop.genomes[i].fitness = fitnesses[i]
                        if fitnesses[i] > _pop.best_fitness:
                                _pop.best_fitness = fitnesses[i]
                                _pop.best_genome = _pop.genomes[i].duplicate()
        if _env_idx == 3:
                _update_pong_opponents()
        _pop.evolve()
        # Check solved.
        if _is_solved():
                _solved = true
                _auto_run = false
                if _pause_btn:
                        _pause_btn.text = "▶ Run"

func _step_pong_generation() -> void:
        var input_ids: Array[int] = [0, 1, 2, 3, 4, 5]
        var bias_id: int = 6
        var output_id: int = 7
        var points_to_win: int = int(_extra.get("_points_to_win", 5))
        var max_opps: int = int(_extra.get("_episodes", 3))
        for i in range(_pop.genomes.size()):
                var g: Genome = _pop.genomes[i]
                var total_score: float = 0.0
                # Always play against nonmoving paddle.
                var env_static := PongEnvironment.new(input_ids, bias_id, output_id, points_to_win)
                env_static.set_player_a(g)
                env_static.set_player_b(null)
                env_static.reset()
                var state: Dictionary = env_static.initial_state()
                var steps: int = 0
                while not env_static.is_done() and steps < 1200:
                        var out: Dictionary = g.forward(state, "topological")
                        var action: Dictionary = env_static.interpret_output(out, {})
                        state = env_static.step(action)
                        steps += 1
                total_score += env_static.current_fitness() * 2.0
                # Play against tournament opponents.
                var n_opps: int = mini(max_opps, _pong_opponents.size())
                for j in range(n_opps):
                        var opp: Genome = _pong_opponents[j]
                        var env := PongEnvironment.new(input_ids, bias_id, output_id, points_to_win)
                        env.set_player_a(g)
                        env.set_player_b(opp)
                        env.reset()
                        state = env.initial_state()
                        steps = 0
                        while not env.is_done() and steps < 1200:
                                var out_a: Dictionary = g.forward(state, "topological")
                                var out_b: Dictionary = opp.forward(state, "topological")
                                var action: Dictionary = env.interpret_output(out_a, out_b)
                                state = env.step(action)
                                steps += 1
                        total_score += env.current_fitness()
                g.fitness = total_score / float(maxi(1, n_opps + 1))
                if g.fitness > _pop.best_fitness:
                        _pop.best_fitness = g.fitness
                        _pop.best_genome = g.duplicate()

func _update_pong_opponents() -> void:
        var candidates: Array = []
        for sp: Species in _pop.species_list:
                var members := sp.members.duplicate()
                members.sort_custom(func(a, b): return a.fitness > b.fitness)
                if not members.is_empty():
                        candidates.append(members[0])
        candidates.sort_custom(func(a, b): return a.fitness > b.fitness)
        _pong_opponents = candidates.slice(0, mini(3, candidates.size()))

func _is_solved() -> bool:
        match _env_idx:
                0: return _pop.best_fitness >= float(_extra.get("_solved_threshold", 15.5))
                1: return _pop.best_fitness >= float(_extra.get("_episodes", 3)) * float(_extra.get("_max_steps", 500)) * 0.95
                2: return _pop.best_fitness >= 2.0
                3: return _pop.best_fitness >= 50.0
                4, 5: return _pop.best_fitness >= 5.0
                _: return false

# ============================================================
# UI updates
# ============================================================

func _update_run_ui() -> void:
        if _pop == null:
                return
        # Stats label.
        var max_gen: int = int(_extra.get("_max_generations", 200))
        var avg_conns: float = 0.0
        var avg_nodes: float = 0.0
        for g: Genome in _pop.genomes:
                avg_conns += g.connection_count()
                avg_nodes += g.node_count()
        avg_conns /= float(maxi(1, _pop.genomes.size()))
        avg_nodes /= float(maxi(1, _pop.genomes.size()))
        _stats_label.text = "  %s  |  Gen %d/%d  |  Best: %.2f  |  Species: %d  |  Nodes: %.1f  Conns: %.1f" % [
                ENVS[_env_idx]["name"], _pop.generation, max_gen, _pop.best_fitness,
                _pop.species_count(), avg_nodes, avg_conns
        ]
        # Solved indicator.
        if _solved:
                _solved_label.text = "✓ SOLVED!"
        else:
                _solved_label.text = ""
        # Update graph visualizer.
        _visualizer.refresh()
        # Update XOR truth table.
        if _xor_table != null and _pop.best_genome != null:
                _xor_table.genome = _pop.best_genome
        # Update simulation viewport population (in case it changed).
        if _sim_viewport != null:
                _sim_viewport.population = _pop

# ============================================================
# Env setup: config, factory, evaluator
# ============================================================

func _make_config(env_idx: int) -> NeatConfig:
        var c := NeatConfig.new()
        c.use_bias = true
        c.forward_mode = "topological"
        c.speciation_method = "standard"
        c.compatibility_threshold = 6.0
        c.target_species_count = 10
        c.generation_method = "asexual"
        c.elite_count = 1
        c.selection_method = "roulette"
        c.evaluation_method = "equal"
        c.enable_weight_mutation = true
        c.weight_mutation_rate = 0.8
        c.weight_mutation_min = 1
        c.enable_connection_mutation = true
        c.connection_mutation_rate = 0.3
        c.connection_mutation_min = 0
        c.enable_neuron_mutation = true
        c.neuron_mutation_rate = 0.2
        c.neuron_mutation_min = 0
        c.enable_enable_mutation = true
        c.enable_mutation_rate = 0.3
        c.enable_mutation_min = 0
        c.forbid_loops = true
        match env_idx:
                0: # XOR
                        c.num_inputs = 2
                        c.num_outputs = 1
                        c.output_activation = ActivationFunctions.Func.SIGMOID
                        c.population_size = 150
                1: # CartPole
                        c.num_inputs = 4
                        c.num_outputs = 1
                        c.output_activation = ActivationFunctions.Func.TANH
                        c.population_size = 100
                2: # Acrobot
                        c.num_inputs = 6
                        c.num_outputs = 1
                        c.output_activation = ActivationFunctions.Func.TANH
                        c.population_size = 100
                3: # Pong
                        c.num_inputs = 6
                        c.num_outputs = 1
                        c.output_activation = ActivationFunctions.Func.TANH
                        c.population_size = 80
                4: # Spider 2D
                        c.num_inputs = 12
                        c.num_outputs = 8
                        c.output_activation = ActivationFunctions.Func.TANH
                        c.population_size = 80
                5: # Spider 3D
                        c.num_inputs = 16
                        c.num_outputs = 12
                        c.output_activation = ActivationFunctions.Func.TANH
                        c.population_size = 60
        return c

func _make_extra(env_idx: int) -> Dictionary:
        var d: Dictionary = {"_max_generations": 200}
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
                4:
                        d["_max_steps"] = 1000
                5:
                        d["_max_steps"] = 1000
        return d

func _make_env_factory(env_idx: int) -> Callable:
        var num_in: int = _config.num_inputs
        var bias_id: int = num_in
        var output_start: int = num_in + 1
        var max_steps: int = int(_extra.get("_max_steps", 500))
        var points_to_win: int = int(_extra.get("_points_to_win", 5))
        match env_idx:
                0: # XOR
                        return func() -> XorEnvironment:
                                return XorEnvironment.new([0, 1], 2, 3)
                1: # CartPole
                        var ids: Array[int] = [0, 1, 2, 3]
                        return func() -> CartPoleEnvironment:
                                return CartPoleEnvironment.new(ids, bias_id, output_start, max_steps)
                2: # Acrobot
                        var ids2: Array[int] = [0, 1, 2, 3, 4, 5]
                        return func() -> AcrobotEnvironment:
                                return AcrobotEnvironment.new(ids2, bias_id, output_start, max_steps)
                3: # Pong
                        var ids3: Array[int] = [0, 1, 2, 3, 4, 5]
                        return func() -> PongEnvironment:
                                return PongEnvironment.new(ids3, bias_id, output_start, points_to_win)
                4: # Spider 2D
                        var in_ids: Array[int] = []
                        for i in range(12):
                                in_ids.append(i)
                        var out_ids: Array[int] = []
                        for i in range(8):
                                out_ids.append(13 + i)
                        return func() -> SpiderWalker2DEnvironment:
                                return SpiderWalker2DEnvironment.new(in_ids, 12, out_ids)
                5: # Spider 3D
                        var in_ids3: Array[int] = []
                        for i in range(16):
                                in_ids3.append(i)
                        var out_ids3: Array[int] = []
                        for i in range(12):
                                out_ids3.append(17 + i)
                        return func() -> SpiderWalker3DEnvironment:
                                return SpiderWalker3DEnvironment.new(in_ids3, 16, out_ids3)
        return Callable()

func _make_evaluator(env_idx: int, factory: Callable, cfg: NeatConfig) -> Evaluator:
        var max_steps: int = int(_extra.get("_max_steps", 500))
        var episodes: int = int(_extra.get("_episodes", 1))
        var ev := Evaluator.new(factory, max_steps + 50, cfg.forward_mode)
        ev.episodes_per_genome = maxi(1, episodes)
        ev.num_threads = 4
        return ev
