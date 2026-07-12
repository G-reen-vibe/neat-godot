extends Control
## ============================================================
## NEAT Godot — Main Application
## ============================================================
## A proper multi-screen UI for training NEAT networks:
##   1. Environment Selection — pick one of 6 envs
##   2. Configuration — tune hyperparameters with sensible defaults
##   3. Training — live visualization + graph view + stats
##
## All layout uses Godot-standard containers (MarginContainer, VBoxContainer,
## HBoxContainer, ScrollContainer, PanelContainer) — no absolute positioning.
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
		"desc": "Balance a pole on\na moving cart.",
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
var _auto_run: bool = false  # Start paused; user presses Run to begin.
var _solved: bool = false
var _speed: int = 1
var _pong_opponents: Array = []
var _stats_tracker: TrainingStatsTracker = null

# === UI: screen containers ===
var _screens: Dictionary = {}

# === UI: config controls ===
var _config_controls: Dictionary = {}  # key -> Control
var _config_deps: Array = []
var _config_title: Label = null
var _config_scroll: ScrollContainer = null
var _config_vbox: VBoxContainer = null

# === UI: run screen elements ===
var _sim_viewport: SimulationViewport = null
var _visualizer: GraphVisualizer = null
var _stats_view: TrainingStatsView = null
var _save_load_view: SaveLoadView = null
var _xor_table: XorTruthTable = null
var _viz_container: PanelContainer = null
var _stats_label: Label = null
var _pause_btn: Button = null
var _speed_btn: OptionButton = null
var _solved_label: Label = null
var _right_tabs: TabContainer = null

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
# Styling helpers
# ============================================================

func _make_panel_style(bg_color: Color = Color(0.10, 0.10, 0.14), border_color: Color = Color(0.25, 0.25, 0.35), border_w: int = 1, radius: int = 6, pad: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.border_width_left = border_w
	sb.border_width_right = border_w
	sb.border_width_top = border_w
	sb.border_width_bottom = border_w
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	if pad > 0:
		sb.content_margin_left = pad
		sb.content_margin_right = pad
		sb.content_margin_top = pad
		sb.content_margin_bottom = pad
	return sb

func _make_button(text: String, min_size: Vector2 = Vector2(100, 32)) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	return btn

func _make_label(text: String, font_size: int = 13, color: Color = Color(0.85, 0.85, 0.9)) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl

# ============================================================
# Screen 1: Environment Selection
# ============================================================

func _build_env_select_screen() -> void:
	# Root: MarginContainer with generous margins.
	var root := MarginContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 48)
	root.add_theme_constant_override("margin_right", 48)
	root.add_theme_constant_override("margin_top", 32)
	root.add_theme_constant_override("margin_bottom", 24)
	# Main vertical layout.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	root.add_child(vbox)
	# Title.
	var title := _make_label("NEAT Godot", 28, Color(0.9, 0.9, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	# Subtitle.
	var subtitle := _make_label("Select an environment to train. Configure hyperparameters on the next screen.", 13, Color(0.55, 0.55, 0.65))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	# Spacer.
	vbox.add_child(_make_vspacer(8))
	# Grid of env cards inside a CenterContainer.
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	for i in range(ENVS.size()):
		grid.add_child(_make_env_card(i))
	center.add_child(grid)
	vbox.add_child(center)
	# Spacer.
	vbox.add_child(_make_vspacer(4))
	# Footer.
	var footer := _make_label("Click an environment to begin  |  ESC to quit", 12, Color(0.45, 0.45, 0.55))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(footer)
	_screens[ScreenState.ENV_SELECT] = root
	add_child(root)

func _make_vspacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c

func _make_env_card(idx: int) -> Control:
	var env: Dictionary = ENVS[idx]
	var card := Button.new()
	card.custom_minimum_size = Vector2(280, 150)
	card.text = ""
	card.pressed.connect(_select_env.bind(idx))
	# Normal stylebox.
	var sb := StyleBoxFlat.new()
	sb.bg_color = (env["color"] as Color).darkened(0.78)
	sb.border_color = (env["color"] as Color).darkened(0.3)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	card.add_theme_stylebox_override("normal", sb)
	# Hover stylebox.
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = (env["color"] as Color).darkened(0.65)
	sb_hover.border_color = env["color"] as Color
	sb_hover.border_width_left = 3
	sb_hover.border_width_right = 3
	sb_hover.border_width_top = 3
	sb_hover.border_width_bottom = 3
	card.add_theme_stylebox_override("hover", sb_hover)
	# Pressed stylebox.
	var sb_pressed := sb.duplicate()
	sb_pressed.bg_color = (env["color"] as Color).darkened(0.55)
	card.add_theme_stylebox_override("pressed", sb_pressed)
	# Card content via VBoxContainer.
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)
	# Name label.
	var name_lbl := Label.new()
	name_lbl.text = env["name"]
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", env["color"] as Color)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)
	# Description label.
	var desc_lbl := Label.new()
	desc_lbl.text = env["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)
	return card

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
	# Root: MarginContainer.
	var root := MarginContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 24)
	root.add_theme_constant_override("margin_right", 24)
	root.add_theme_constant_override("margin_top", 16)
	root.add_theme_constant_override("margin_bottom", 16)
	root.visible = false
	# Main VBox.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	root.add_child(vbox)
	# Header bar (HBox).
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var back_btn := _make_button("← Back", Vector2(100, 36))
	back_btn.pressed.connect(func(): _show_screen(ScreenState.ENV_SELECT))
	header.add_child(back_btn)
	_config_title = Label.new()
	_config_title.text = ""
	_config_title.add_theme_font_size_override("font_size", 20)
	_config_title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	_config_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_config_title.position.y = 6
	header.add_child(_config_title)
	vbox.add_child(header)
	# Scroll area (expand fill).
	_config_scroll = ScrollContainer.new()
	_config_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_config_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_config_scroll.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.08, 0.12), Color(0.2, 0.2, 0.28), 1, 4))
	vbox.add_child(_config_scroll)
	# Footer bar.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	var reset_btn := _make_button("Reset Defaults", Vector2(140, 36))
	reset_btn.pressed.connect(_reset_config_defaults)
	footer.add_child(reset_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var start_btn := _make_button("Start Training →", Vector2(160, 36))
	start_btn.pressed.connect(_start_training)
	footer.add_child(start_btn)
	vbox.add_child(footer)
	_screens[ScreenState.CONFIG] = root
	add_child(root)

func _build_config_controls() -> void:
	# Clear old content.
	if _config_vbox != null and is_instance_valid(_config_vbox):
		_config_vbox.queue_free()
	_config_controls.clear()
	_config_deps.clear()
	# Update title.
	_config_title.text = "%s — Configuration" % ENVS[_env_idx]["name"]
	# Build VBox for config rows inside scroll.
	_config_vbox = VBoxContainer.new()
	_config_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_config_vbox.add_theme_constant_override("separation", 3)
	_config_vbox.add_theme_constant_override("margin_left", 12)
	_config_vbox.add_theme_constant_override("margin_right", 12)
	_config_vbox.add_theme_constant_override("margin_top", 12)
	_config_vbox.add_theme_constant_override("margin_bottom", 12)
	_config_scroll.add_child(_config_vbox)
	# Build rows from schema.
	var schema: Array = _get_config_schema()
	for entry: Dictionary in schema:
		if entry.has("section"):
			_config_vbox.add_child(_make_section_header(entry["section"]))
		else:
			var row := _make_config_row(entry)
			_config_vbox.add_child(row)
			if entry.has("visible_when"):
				# visible_when: {key: value, ...} — ALL must match (AND).
				_config_deps.append({
					"key": entry["key"],
					"conditions": entry["visible_when"],
					"mode": "and",
					"row": row,
				})
			elif entry.has("visible_when_any"):
				# visible_when_any: {key: [v1, v2, ...]} — key must match ANY (OR).
				_config_deps.append({
					"key": entry["key"],
					"conditions": entry["visible_when_any"],
					"mode": "any",
					"row": row,
				})
	_update_config_visibility()

func _make_section_header(text: String) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	var lbl := _make_label(text, 15, Color(0.6, 0.8, 1.0))
	lbl.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(lbl)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	vbox.add_child(sep)
	return vbox

func _make_config_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := _make_label(entry["label"], 13, Color(0.78, 0.78, 0.84))
	lbl.custom_minimum_size = Vector2(260, 24)
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
				opt.set_item_metadata(i, opt_entry[1])
				if opt_entry[1] == current_val:
					opt.selected = i
			opt.custom_minimum_size = Vector2(200, 28)
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
	if key.begins_with("_"):
		return _extra.get(key)
	if _config.get(key) != null:
		return _config.get(key)
	return null

func _on_config_changed(_val: Variant = null) -> void:
	_update_config_visibility()

func _update_config_visibility() -> void:
	for dep: Dictionary in _config_deps:
		var conditions: Dictionary = dep["conditions"]
		var mode: String = dep.get("mode", "and")
		var row: Control = dep.get("row")
		if row == null or not is_instance_valid(row):
			continue
		if mode == "any":
			# OR: visible if any condition matches. conditions = {key: [v1, v2, ...]}
			var any_match: bool = false
			for dep_key: String in conditions:
				var allowed_values: Array = conditions[dep_key]
				var current_val: Variant = _read_control_value_typed(dep_key)
				for v in allowed_values:
					if str(current_val) == str(v):
						any_match = true
						break
				if any_match:
					break
			row.visible = any_match
		else:
			# AND: visible if all conditions match. conditions = {key: value}
			var all_match: bool = true
			for dep_key: String in conditions:
				var dep_value: Variant = conditions[dep_key]
				var current_val: Variant = _read_control_value_typed(dep_key)
				if str(current_val) != str(dep_value):
					all_match = false
					break
			row.visible = all_match

func _read_control_value_typed(key: String) -> Variant:
	var ctrl: Control = _config_controls.get(key)
	if ctrl == null:
		return ""
	if ctrl is SpinBox:
		return (ctrl as SpinBox).value
	if ctrl is OptionButton:
		var opt := ctrl as OptionButton
		if opt.selected >= 0 and opt.selected < opt.item_count:
			return opt.get_item_metadata(opt.selected)
		return ""
	if ctrl is CheckButton:
		return (ctrl as CheckButton).button_pressed
	return ""

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
	_auto_run = false  # Start paused.
	_speed = 1
	if _speed_btn:
		_speed_btn.selected = 0
	if _pause_btn:
		_pause_btn.text = "▶ Run"
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
		{"section": "Initialization (First Generation)"},
		{"key": "init_min_hidden_nodes", "label": "Min Starting Hidden Nodes", "type": "int", "min": 0, "max": 10, "step": 1},
		{"key": "init_max_hidden_nodes", "label": "Max Starting Hidden Nodes", "type": "int", "min": 0, "max": 10, "step": 1},
		{"key": "init_min_connections", "label": "Min Starting Connections", "type": "int", "min": 1, "max": 50, "step": 1},
		{"key": "init_max_connections", "label": "Max Starting Connections", "type": "int", "min": 1, "max": 50, "step": 1},
		{"key": "init_weight_min", "label": "Init Weight Min", "type": "float", "min": -5.0, "max": 0.0, "step": 0.1},
		{"key": "init_weight_max", "label": "Init Weight Max", "type": "float", "min": 0.0, "max": 5.0, "step": 0.1},
		{"section": "Weight Mutation"},
		{"key": "weight_mutation_mode", "label": "Weight Mutation Mode", "type": "enum", "options": [
			["Single (pick N, full delta)", "single"], ["All (perturb all, small delta)", "all"]
		]},
		{"key": "weight_mutator_method", "label": "Weight Mutator Distribution", "type": "enum", "options": [
			["Uniform (min, max)", "standard"], ["Normal (Gaussian)", "normal"]
		]},
		{"key": "weight_mutation_rate", "label": "Weight Mutation Rate (prob per genome)", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
		 "visible_when": {"weight_mutation_mode": "single"}},
		{"key": "weight_mutation_min", "label": "Min Connections to Mutate", "type": "int", "min": 1, "max": 10, "step": 1,
		 "visible_when": {"weight_mutation_mode": "single"}},
		{"key": "weight_mutation_delta_min", "label": "Delta Min (Uniform)", "type": "float", "min": -3.0, "max": 0.0, "step": 0.1,
		 "visible_when": {"weight_mutation_mode": "single", "weight_mutator_method": "standard"}},
		{"key": "weight_mutation_delta_max", "label": "Delta Max (Uniform)", "type": "float", "min": 0.0, "max": 3.0, "step": 0.1,
		 "visible_when": {"weight_mutation_mode": "single", "weight_mutator_method": "standard"}},
		{"key": "weight_mutation_normal_std", "label": "Normal Std Dev", "type": "float", "min": 0.01, "max": 3.0, "step": 0.05,
		 "visible_when": {"weight_mutator_method": "normal"}},
		{"key": "weight_mutation_all_scale", "label": "All-Mode Scale Factor", "type": "float", "min": 0.01, "max": 1.0, "step": 0.01,
		 "visible_when": {"weight_mutation_mode": "all"}},
		{"key": "weight_selector_method", "label": "Weight Selector", "type": "enum", "options": [
			["Standard (uniform)", "standard"], ["Capped (bias to bounds)", "capped"]
		]},
		{"key": "weight_capped_min", "label": "Capped Min Weight", "type": "float", "min": -10.0, "max": 0.0, "step": 0.1,
		 "visible_when": {"weight_selector_method": "capped"}},
		{"key": "weight_capped_max", "label": "Capped Max Weight", "type": "float", "min": 0.0, "max": 10.0, "step": 0.1,
		 "visible_when": {"weight_selector_method": "capped"}},
		{"section": "Structural Mutation"},
		{"key": "connection_mutation_rate", "label": "Connection Add Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05},
		{"key": "connection_selector_method", "label": "Connection Selector", "type": "enum", "options": [
			["Standard", "standard"], ["Least Used", "least_used"], ["Least Common", "least_common"]
		]},
		{"key": "connection_mutator_method", "label": "Connection Mutator", "type": "enum", "options": [
			["Uniform", "standard"], ["Normal", "normal"], ["Safe Gradient", "safe_gradient"]
		]},
		{"key": "connection_weight_min", "label": "New Connection Weight Min", "type": "float", "min": -3.0, "max": 0.0, "step": 0.1,
		 "visible_when": {"connection_mutator_method": "standard"}},
		{"key": "connection_weight_max", "label": "New Connection Weight Max", "type": "float", "min": 0.0, "max": 3.0, "step": 0.1,
		 "visible_when": {"connection_mutator_method": "standard"}},
		{"key": "neuron_mutation_rate", "label": "Neuron Add Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05},
		{"key": "neuron_selector_method", "label": "Neuron Selector", "type": "enum", "options": [
			["Standard", "standard"], ["Least Common", "least_common"]
		]},
		{"key": "enable_mutation_rate", "label": "Enable Mutation Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05},
		{"section": "Prune Mutation"},
		{"key": "enable_prune_mutation", "label": "Enable Prune Mutation", "type": "bool"},
		{"key": "prune_mutation_rate", "label": "Prune Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
		 "visible_when": {"enable_prune_mutation": true}},
		{"key": "prune_selector_method", "label": "Prune Selector", "type": "enum", "options": [
			["Standard", "standard"], ["Least Weight", "least_weight"]
		],
		 "visible_when": {"enable_prune_mutation": true}},
		{"key": "prune_mutator_method", "label": "Prune Mutator", "type": "enum", "options": [
			["Disabled (any)", "disabled"], ["Non Essential", "non_essential"], ["Merge Pair", "merge"]
		],
		 "visible_when": {"enable_prune_mutation": true}},
		{"section": "Speciation"},
		{"key": "speciation_method", "label": "Speciation Method", "type": "enum", "options": [
			["Single (all in one)", "single"], ["Standard (dynamic threshold)", "standard"], ["Purge (start with best N)", "purge"]
		]},
		{"key": "target_species_count", "label": "Target Species Count", "type": "int", "min": 1, "max": 30, "step": 1,
		 "visible_when_any": {"speciation_method": ["standard", "purge"]}},
		{"key": "compatibility_threshold", "label": "Initial Compatibility Threshold", "type": "float", "min": 0.5, "max": 20.0, "step": 0.1,
		 "visible_when": {"speciation_method": "standard"}},
		{"key": "threshold_up_speed", "label": "Threshold Up Speed (too many species)", "type": "float", "min": 0.01, "max": 5.0, "step": 0.01,
		 "visible_when": {"speciation_method": "standard"}},
		{"key": "threshold_down_speed", "label": "Threshold Down Speed (too few species)", "type": "float", "min": 0.01, "max": 5.0, "step": 0.01,
		 "visible_when": {"speciation_method": "standard"}},
		{"key": "min_threshold", "label": "Min Threshold", "type": "float", "min": 0.1, "max": 5.0, "step": 0.1,
		 "visible_when": {"speciation_method": "standard"}},
		{"key": "max_threshold", "label": "Max Threshold", "type": "float", "min": 5.0, "max": 50.0, "step": 0.5,
		 "visible_when": {"speciation_method": "standard"}},
		{"key": "merge_ratio", "label": "Merge Ratio (fraction of threshold)", "type": "float", "min": 0.1, "max": 1.0, "step": 0.05,
		 "visible_when": {"speciation_method": "standard"}},
		{"key": "max_species_count", "label": "Max Species (hard cap)", "type": "int", "min": 5, "max": 50, "step": 1,
		 "visible_when": {"speciation_method": "standard"}},
		{"section": "Similarity Test"},
		{"key": "similarity_method", "label": "Similarity Test", "type": "enum", "options": [
			["Standard (NEAT paper)", "standard"], ["Percentage", "percentage"]
		]},
		{"key": "similarity_c1", "label": "C1 (excess weight)", "type": "float", "min": 0.0, "max": 5.0, "step": 0.1,
		 "visible_when": {"similarity_method": "standard"}},
		{"key": "similarity_c2", "label": "C2 (disjoint weight)", "type": "float", "min": 0.0, "max": 5.0, "step": 0.1,
		 "visible_when": {"similarity_method": "standard"}},
		{"key": "similarity_c3", "label": "C3 (weight diff weight)", "type": "float", "min": 0.0, "max": 5.0, "step": 0.1,
		 "visible_when": {"similarity_method": "standard"}},
		{"section": "Generation & Evaluation"},
		{"key": "generation_method", "label": "Generation Method", "type": "enum", "options": [
			["Asexual", "asexual"], ["Crossover", "crossover"], ["Mixed", "mixed"]
		]},
		{"key": "crossover_rate", "label": "Crossover Rate", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
		 "visible_when": {"generation_method": "mixed"}},
		{"key": "overall_crossover_method", "label": "Overall Crossover Strategy", "type": "enum", "options": [
			["Fitter", "fitter"], ["Bigger", "bigger"], ["Combine", "combine"], ["Excluded", "excluded"]
		],
		 "visible_when": {"generation_method": "crossover"}},
		{"key": "overall_crossover_method", "label": "Overall Crossover Strategy", "type": "enum", "options": [
			["Fitter", "fitter"], ["Bigger", "bigger"], ["Combine", "combine"], ["Excluded", "excluded"]
		],
		 "visible_when": {"generation_method": "mixed"}},
		{"key": "neuron_crossover_method", "label": "Neuron Crossover", "type": "enum", "options": [
			["Standard", "standard"], ["Standard All", "standard_all"], ["Average", "average"], ["Biased Average", "biased_average"]
		],
		 "visible_when": {"generation_method": "crossover"}},
		{"key": "neuron_crossover_method", "label": "Neuron Crossover", "type": "enum", "options": [
			["Standard", "standard"], ["Standard All", "standard_all"], ["Average", "average"], ["Biased Average", "biased_average"]
		],
		 "visible_when": {"generation_method": "mixed"}},
		{"key": "biased_average_strength", "label": "Biased Average Strength", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
		 "visible_when": {"neuron_crossover_method": "biased_average"}},
		{"key": "selection_method", "label": "Parent Selection Method", "type": "enum", "options": [
			["Roulette", "roulette"], ["Inverse Roulette", "inverse_roulette"],
			["Gaussian", "gaussian"], ["Triangular", "triangular"], ["Uniform", "uniform"]
		]},
		{"key": "evaluation_method", "label": "Evaluation Strategy", "type": "enum", "options": [
			["Equal", "equal"], ["Improvement Rate", "improvement_rate"], ["Novelty", "novelty"]
		]},
		{"key": "interspecies_rate", "label": "Interspecies Mating Rate", "type": "float", "min": 0.0, "max": 0.5, "step": 0.01},
		{"section": "Forward Pass"},
		{"key": "forward_mode", "label": "Forward Mode", "type": "enum", "options": [
			["Topological (no loops)", "topological"], ["Timestep (allows loops)", "timestep"]
		]},
	]
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
		4, 5:
			schema.append_array([
				{"section": "Spider Walker"},
				{"key": "_max_steps", "label": "Max Steps per Episode", "type": "int", "min": 200, "max": 2000, "step": 100},
			])
	return schema

# ============================================================
# Screen 3: Training
# ============================================================

func _build_run_screen() -> void:
	# Root: MarginContainer.
	var root := MarginContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 8)
	root.add_theme_constant_override("margin_right", 8)
	root.add_theme_constant_override("margin_top", 8)
	root.add_theme_constant_override("margin_bottom", 8)
	root.visible = false
	# Main HSplitContainer: left (viz+stats) | right (tabs). Splitter lets user
	# resize the two sides; right side has a clamped min/max width.
	var main_split := HSplitContainer.new()
	main_split.add_theme_constant_override("separation", 8)
	main_split.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	root.add_child(main_split)
	# Left side: VBoxContainer (takes all remaining space).
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_stretch_ratio = 1.0
	left_vbox.add_theme_constant_override("separation", 6)
	main_split.add_child(left_vbox)
	# Header bar.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var back_btn := _make_button("← Menu", Vector2(90, 32))
	back_btn.pressed.connect(func(): _show_screen(ScreenState.ENV_SELECT))
	header.add_child(back_btn)
	var config_btn := _make_button("⚙ Config", Vector2(90, 32))
	config_btn.pressed.connect(func():
		_show_screen(ScreenState.CONFIG)
		_build_config_controls()
	)
	header.add_child(config_btn)
	var restart_btn := _make_button("↻ Restart", Vector2(90, 32))
	restart_btn.pressed.connect(_restart_training)
	header.add_child(restart_btn)
	_stats_label = Label.new()
	_stats_label.text = ""
	_stats_label.add_theme_font_size_override("font_size", 13)
	_stats_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
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
	# Visualization container (PanelContainer, expand fill).
	_viz_container = PanelContainer.new()
	_viz_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viz_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viz_container.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.04, 0.07), Color(0.2, 0.2, 0.28), 1, 4))
	left_vbox.add_child(_viz_container)
	# Help bar.
	var help_bar := HBoxContainer.new()
	help_bar.add_theme_constant_override("separation", 16)
	var help_text := _make_label("V=cycle viz  Space=step  R=pause  N/B=genome  Arrows=pan  +/-/0=zoom  ESC=back", 11, Color(0.5, 0.5, 0.6))
	help_bar.add_child(help_text)
	_solved_label = Label.new()
	_solved_label.text = ""
	_solved_label.add_theme_font_size_override("font_size", 14)
	_solved_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	_solved_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_solved_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help_bar.add_child(_solved_label)
	left_vbox.add_child(help_bar)
	# Right side: TabContainer with Genome View | Training Stats | Save/Load.
	# Wrapped in a PanelContainer for a border; uses SIZE_FILL with a stretch
	# ratio so it gets a fixed fraction of the width (not cut off).
	_right_tabs = TabContainer.new()
	_right_tabs.size_flags_horizontal = Control.SIZE_FILL
	_right_tabs.size_flags_stretch_ratio = 0.38  # ~38% of width
	_right_tabs.custom_minimum_size = Vector2(320, 0)
	_right_tabs.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.08, 0.12), Color(0.2, 0.2, 0.28), 1, 4))
	# Tab 1: Genome view.
	var genome_tab := PanelContainer.new()
	genome_tab.name = "Genome"
	_visualizer = GraphVisualizer.new()
	_visualizer.custom_minimum_size = Vector2(300, 400)
	genome_tab.add_child(_visualizer)
	_right_tabs.add_child(genome_tab)
	# Tab 2: Training stats.
	var stats_tab := PanelContainer.new()
	stats_tab.name = "Stats"
	_stats_view = TrainingStatsView.new()
	stats_tab.add_child(_stats_view)
	_right_tabs.add_child(stats_tab)
	# Tab 3: Save/Load.
	var save_tab := PanelContainer.new()
	save_tab.name = "Save/Load"
	_save_load_view = SaveLoadView.new()
	save_tab.add_child(_save_load_view)
	_right_tabs.add_child(save_tab)
	main_split.add_child(_right_tabs)
	_screens[ScreenState.RUNNING] = root
	add_child(root)

func _setup_run_for_env() -> void:
	for c in _viz_container.get_children():
		_viz_container.remove_child(c)
		c.queue_free()
	_sim_viewport = null
	_xor_table = null
	_visualizer.population = _pop
	# Initialize stats tracker.
	_stats_tracker = TrainingStatsTracker.new()
	_stats_tracker.record(_pop)
	_stats_view.tracker = _stats_tracker
	_stats_view.refresh()
	# Wire up save/load view.
	_save_load_view.population = _pop
	_save_load_view.config = _config
	_save_load_view.env_idx = _env_idx
	if ENVS[_env_idx]["has_viz"]:
		_sim_viewport = SimulationViewport.new()
		_sim_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_sim_viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sim_viewport.population = _pop
		_sim_viewport.env_factory = _env_factory
		_sim_viewport.forward_mode = _config.forward_mode
		_sim_viewport.mode = SimulationViewport.Mode.TOP
		_viz_container.add_child(_sim_viewport)
	else:
		_xor_table = XorTruthTable.new()
		_xor_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_xor_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_viz_container.add_child(_xor_table)
	# Ensure paused state.
	_auto_run = false
	if _pause_btn:
		_pause_btn.text = "▶ Run"

func _toggle_pause() -> void:
	_auto_run = not _auto_run
	if _pause_btn:
		_pause_btn.text = "▶ Run" if not _auto_run else "⏸ Pause"

func _restart_training() -> void:
	if _config == null:
		return
	_pop = Population.new(_config)
	_pop.initialize()
	_pong_opponents.clear()
	_solved = false
	_auto_run = false  # Start paused.
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
	# Record stats after evolution.
	if _stats_tracker != null:
		_stats_tracker.record(_pop)
	# Check for pending load from Save/Load tab.
	if _save_load_view != null and _save_load_view.has_pending_load():
		_apply_pending_load()
	if _is_solved():
		_solved = true
		_auto_run = false
		if _pause_btn:
			_pause_btn.text = "▶ Run"

func _apply_pending_load() -> void:
	var data: Dictionary = _save_load_view.take_pending_load()
	if data.is_empty():
		return
	# Load config if present.
	if data.has("config"):
		_config = _save_load_view._config_from_dict(data["config"])
	# Load population.
	if data.has("population"):
		_pop = _save_load_view.load_population_from_dict(data["population"], _config)
		_pong_opponents.clear()
		_solved = false
		_auto_run = false
		if _pause_btn:
			_pause_btn.text = "▶ Run"
		# Re-setup UI for the new population.
		_visualizer.population = _pop
		_save_load_view.population = _pop
		if _sim_viewport != null:
			_sim_viewport.population = _pop
		# Reset stats tracker with loaded generation as initial.
		_stats_tracker = TrainingStatsTracker.new()
		_stats_tracker.record(_pop)
		_stats_view.tracker = _stats_tracker
		_stats_view.refresh()

func _step_pong_generation() -> void:
	var input_ids: Array[int] = [0, 1, 2, 3, 4, 5]
	var bias_id: int = 6
	var output_id: int = 7
	var points_to_win: int = int(_extra.get("_points_to_win", 5))
	var max_opps: int = int(_extra.get("_episodes", 3))
	for i in range(_pop.genomes.size()):
		var g: Genome = _pop.genomes[i]
		var total_score: float = 0.0
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
	# Solved thresholds are set HIGH so auto-run continues training.
	# The "SOLVED!" indicator only appears when the env is genuinely mastered.
	match _env_idx:
		0: return _pop.best_fitness >= float(_extra.get("_solved_threshold", 15.5))
		1: return _pop.best_fitness >= float(_extra.get("_episodes", 3)) * float(_extra.get("_max_steps", 500)) * 0.98
		2: return _pop.best_fitness >= 3.0  # tip_y well above threshold + step bonus
		3: return _pop.best_fitness >= 200.0  # consistently winning tournaments
		4, 5: return _pop.best_fitness >= 20.0  # substantial forward distance
		_: return false

# ============================================================
# UI updates
# ============================================================

func _update_run_ui() -> void:
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
		ENVS[_env_idx]["name"], _pop.generation, max_gen, _pop.best_fitness,
		_pop.species_count(), avg_nodes, avg_conns
	]
	if _solved:
		_solved_label.text = "✓ SOLVED!"
	else:
		_solved_label.text = ""
	_visualizer.refresh()
	if _xor_table != null and _pop.best_genome != null:
		_xor_table.genome = _pop.best_genome
	if _sim_viewport != null:
		_sim_viewport.population = _pop
		# Pass tournament opponents for Pong live viz.
		if _env_idx == 3:
			_sim_viewport.opponents = _pong_opponents
	if _stats_view != null:
		_stats_view.refresh()
	# Update save/load view's population reference.
	if _save_load_view != null:
		_save_load_view.population = _pop
		_save_load_view.config = _config

# ============================================================
# Env setup: config, factory, evaluator
# ============================================================

func _make_config(env_idx: int) -> NeatConfig:
	var c := NeatConfig.new()
	c.use_bias = true
	c.forward_mode = "topological"
	# Initialization: random hidden nodes (0-3) and connections (5-20).
	c.init_min_hidden_nodes = 0
	c.init_max_hidden_nodes = 3
	c.init_min_connections = 5
	c.init_max_connections = 20
	c.init_weight_min = -1.0
	c.init_weight_max = 1.0
	# Speciation: Purge by default. First gen keeps top N genomes as seeds,
	# then computes an ideal threshold so they stay as N stable species.
	c.speciation_method = "purge"
	c.target_species_count = 10
	c.compatibility_threshold = 3.0
	c.threshold_up_speed = 0.3
	c.threshold_down_speed = 0.3
	c.max_species_count = 20
	c.merge_ratio = 0.5
	c.min_threshold = 0.5
	c.max_threshold = 15.0
	# Generation: Asexual with elitism (standard NEAT).
	c.generation_method = "asexual"
	c.elite_count = 1
	c.interspecies_rate = 0.001
	c.selection_method = "roulette"
	c.evaluation_method = "equal"
	# Weight mutation: single mode, 80% chance, uniform delta ±0.5 (NEAT paper).
	c.enable_weight_mutation = true
	c.weight_mutation_mode = "single"
	c.weight_mutation_rate = 0.8
	c.weight_mutation_min = 1
	c.weight_mutation_delta_min = -0.5
	c.weight_mutation_delta_max = 0.5
	c.weight_mutator_method = "standard"
	c.weight_selector_method = "standard"
	# Structural mutation: NEAT paper rates (low to avoid topological explosion).
	c.enable_connection_mutation = true
	c.connection_mutation_rate = 0.05
	c.connection_mutation_min = 0
	c.connection_weight_min = -1.0
	c.connection_weight_max = 1.0
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
	# Similarity: NEAT paper coefficients.
	c.similarity_method = "standard"
	c.similarity_c1 = 1.0
	c.similarity_c2 = 1.0
	c.similarity_c3 = 0.4
	c.similarity_n_threshold = 20
	c.forbid_loops = true
	# Crossover defaults (used if generation_method changes).
	c.overall_crossover_method = "fitter"
	c.neuron_crossover_method = "standard"
	c.biased_average_strength = 0.5
	c.crossover_rate = 0.5
	match env_idx:
		0:
			# XOR: small population, sigmoid output, low threshold.
			c.num_inputs = 2
			c.num_outputs = 1
			c.output_activation = ActivationFunctions.Func.SIGMOID
			c.population_size = 150
			c.target_species_count = 10
		1:
			# CartPole: tanh output, moderate population.
			c.num_inputs = 4
			c.num_outputs = 1
			c.output_activation = ActivationFunctions.Func.TANH
			c.population_size = 100
			c.target_species_count = 8
		2:
			# Acrobot: tanh output, moderate population.
			c.num_inputs = 6
			c.num_outputs = 1
			c.output_activation = ActivationFunctions.Func.TANH
			c.population_size = 100
			c.target_species_count = 8
		3:
			# Pong: tanh output, smaller pop (tournament is expensive).
			c.num_inputs = 6
			c.num_outputs = 1
			c.output_activation = ActivationFunctions.Func.TANH
			c.population_size = 80
			c.target_species_count = 8
		4:
			# Spider 2D: tanh output, 8 outputs (leg controls).
			c.num_inputs = 12
			c.num_outputs = 8
			c.output_activation = ActivationFunctions.Func.TANH
			c.population_size = 80
			c.target_species_count = 8
		5:
			# Spider 3D: tanh output, 12 outputs.
			c.num_inputs = 16
			c.num_outputs = 12
			c.output_activation = ActivationFunctions.Func.TANH
			c.population_size = 60
			c.target_species_count = 6
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
		4: d["_max_steps"] = 1000
		5: d["_max_steps"] = 1000
	return d

func _make_env_factory(env_idx: int) -> Callable:
	var num_in: int = _config.num_inputs
	var bias_id: int = num_in
	var output_start: int = num_in + 1
	var max_steps: int = int(_extra.get("_max_steps", 500))
	var points_to_win: int = int(_extra.get("_points_to_win", 5))
	match env_idx:
		0:
			return func() -> XorEnvironment:
				return XorEnvironment.new([0, 1], 2, 3)
		1:
			var ids: Array[int] = [0, 1, 2, 3]
			return func() -> CartPoleEnvironment:
				return CartPoleEnvironment.new(ids, bias_id, output_start, max_steps)
		2:
			var ids2: Array[int] = [0, 1, 2, 3, 4, 5]
			return func() -> AcrobotEnvironment:
				return AcrobotEnvironment.new(ids2, bias_id, output_start, max_steps)
		3:
			var ids3: Array[int] = [0, 1, 2, 3, 4, 5]
			return func() -> PongEnvironment:
				return PongEnvironment.new(ids3, bias_id, output_start, points_to_win)
		4:
			var in_ids: Array[int] = []
			for i in range(12):
				in_ids.append(i)
			var out_ids: Array[int] = []
			for i in range(8):
				out_ids.append(13 + i)
			return func() -> SpiderWalker2DEnvironment:
				return SpiderWalker2DEnvironment.new(in_ids, 12, out_ids)
		5:
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
