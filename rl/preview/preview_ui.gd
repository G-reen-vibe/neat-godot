## Main preview UI: toolbar + env grid + stats panel.
##
## Layout:
##   +-----------------------------------------------------+
##   | Toolbar: [Env v] [Envs:9] [Cols:3] [Speed:1.0]      |
##   |          [Play/Pause] [Reset]                        |
##   +----------------------------------+------------------+
##   |                                  | Aggregate Stats  |
##   |   Grid of parallel envs          |  Total reward    |
##   |   (SubViewport per env)          |  Episodes        |
##   |                                  |  Avg steps       |
##   |                                  |  Best reward     |
##   |                                  +------------------+
##   |                                  | Per-env stats    |
##   |                                  |  #0 ep:5 r:120   |
##   |                                  |  #1 ep:3 r:89    |
##   |                                  |  ...             |
##   +----------------------------------+------------------+
extends Control

class_name RLPreviewUI

const ENV_NAMES := ["cartpole", "pong", "lunar_lander", "bipedal_walker"]

# --- UI refs ---
var _env_select: OptionButton
var _num_envs_spin: SpinBox
var _columns_spin: SpinBox
var _speed_spin: SpinBox
var _play_pause_btn: Button
var _reset_btn: Button
var _grid_host: Control       # host for RLPreviewGrid
var _grid: RLPreviewGrid
var _stats_panel: VBoxContainer
var _agg_labels: Dictionary   # name -> Label
var _per_env_container: VBoxContainer

# --- State ---
var _academy: RLAcademy
var _playing: bool = true
var _stats_dirty: bool = false


func _ready() -> void:
        RLEnvRegistration.register_all()
        _build_ui()
        _start_env(ENV_NAMES[0])


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
        color_self(Color(0.12, 0.12, 0.16))
        set_anchors_preset(PRESET_FULL_RECT)

        var root_vb := VBoxContainer.new()
        root_vb.set_anchors_preset(PRESET_FULL_RECT)
        root_vb.offset_left = 6
        root_vb.offset_top = 6
        root_vb.offset_right = -6
        root_vb.offset_bottom = -6
        root_vb.add_theme_constant_override("separation", 6)
        add_child(root_vb)

        # --- Toolbar ---
        var toolbar := PanelContainer.new()
        var tb_style := StyleBoxFlat.new()
        tb_style.bg_color = Color(0.18, 0.18, 0.24)
        tb_style.border_width_bottom = 2
        tb_style.border_color = Color(0.35, 0.35, 0.45)
        tb_style.content_margin_left = 10
        tb_style.content_margin_right = 10
        tb_style.content_margin_top = 6
        tb_style.content_margin_bottom = 6
        toolbar.add_theme_stylebox_override("panel", tb_style)
        root_vb.add_child(toolbar)

        var tb_hb := HBoxContainer.new()
        tb_hb.add_theme_constant_override("separation", 12)
        toolbar.add_child(tb_hb)

        # Title
        var title := Label.new()
        title.text = "Godot RL"
        title.add_theme_font_size_override("font_size", 16)
        title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
        tb_hb.add_child(title)

        tb_hb.add_child(_make_vsep())

        # Env selector
        tb_hb.add_child(_make_label("Env:"))
        _env_select = OptionButton.new()
        for name in ENV_NAMES:
                _env_select.add_item(name)
        _env_select.item_selected.connect(_on_env_changed)
        _env_select.custom_minimum_size.x = 130
        tb_hb.add_child(_env_select)

        tb_hb.add_child(_make_vsep())

        # Num envs
        tb_hb.add_child(_make_label("Envs:"))
        _num_envs_spin = _make_spinbox(1, 64, 9)
        _num_envs_spin.value_changed.connect(_on_params_changed)
        tb_hb.add_child(_num_envs_spin)

        # Columns
        tb_hb.add_child(_make_label("Cols:"))
        _columns_spin = _make_spinbox(1, 8, 3)
        _columns_spin.value_changed.connect(_on_params_changed)
        tb_hb.add_child(_columns_spin)

        tb_hb.add_child(_make_vsep())

        # Speed
        tb_hb.add_child(_make_label("Speed:"))
        _speed_spin = _make_spinbox(0.1, 10.0, 1.0, 0.1)
        _speed_spin.value_changed.connect(_on_speed_changed)
        tb_hb.add_child(_speed_spin)

        tb_hb.add_child(_make_vsep())

        # Play/Pause
        _play_pause_btn = Button.new()
        _play_pause_btn.text = "Pause"
        _play_pause_btn.custom_minimum_size.x = 90
        _play_pause_btn.pressed.connect(_on_play_pause)
        tb_hb.add_child(_play_pause_btn)

        # Reset
        _reset_btn = Button.new()
        _reset_btn.text = "Reset"
        _reset_btn.custom_minimum_size.x = 80
        _reset_btn.pressed.connect(_on_reset)
        tb_hb.add_child(_reset_btn)

        # Spacer
        var spacer := Control.new()
        spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        tb_hb.add_child(spacer)

        # --- Content area: grid + stats panel ---
        var content_hb := HBoxContainer.new()
        content_hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
        content_hb.add_theme_constant_override("separation", 6)
        root_vb.add_child(content_hb)

        # Grid panel (left, expands)
        var grid_panel := PanelContainer.new()
        grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var gp_style := StyleBoxFlat.new()
        gp_style.bg_color = Color(0.10, 0.10, 0.14)
        gp_style.content_margin_left = 8
        gp_style.content_margin_right = 8
        gp_style.content_margin_top = 8
        gp_style.content_margin_bottom = 8
        grid_panel.add_theme_stylebox_override("panel", gp_style)
        content_hb.add_child(grid_panel)

        _grid_host = Control.new()
        _grid_host.set_anchors_preset(PRESET_FULL_RECT)
        grid_panel.add_child(_grid_host)

        # Stats panel (right, fixed width)
        var stats_outer := PanelContainer.new()
        stats_outer.custom_minimum_size.x = 280
        var sp_style := StyleBoxFlat.new()
        sp_style.bg_color = Color(0.18, 0.18, 0.24)
        sp_style.content_margin_left = 10
        sp_style.content_margin_right = 10
        sp_style.content_margin_top = 10
        sp_style.content_margin_bottom = 10
        stats_outer.add_theme_stylebox_override("panel", sp_style)
        content_hb.add_child(stats_outer)

        _stats_panel = VBoxContainer.new()
        _stats_panel.add_theme_constant_override("separation", 4)
        stats_outer.add_child(_stats_panel)

        _build_stats_panel()


func _build_stats_panel() -> void:
        # Header
        var header := Label.new()
        header.text = "Statistics"
        header.add_theme_font_size_override("font_size", 16)
        header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
        _stats_panel.add_child(header)

        # Aggregate section
        var agg_section := _make_section_label("Aggregate")
        _stats_panel.add_child(agg_section)

        for key in ["envs", "episodes", "total_reward", "avg_steps", "best_reward"]:
                var row := HBoxContainer.new()
                var name_lbl := _make_label(key.replace("_", " ").capitalize() + ":")
                name_lbl.modulate = Color(0.7, 0.7, 0.75)
                var val_lbl := _make_label("—")
                val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                row.add_child(name_lbl)
                row.add_child(val_lbl)
                _stats_panel.add_child(row)
                _agg_labels[key] = val_lbl

        _stats_panel.add_child(_make_hsep())

        # Per-env section
        var per_env_section := _make_section_label("Per-env")
        _stats_panel.add_child(per_env_section)

        var scroll := ScrollContainer.new()
        scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        _stats_panel.add_child(scroll)

        _per_env_container = VBoxContainer.new()
        _per_env_container.add_theme_constant_override("separation", 2)
        scroll.add_child(_per_env_container)


# ---------------------------------------------------------------------------
# Env lifecycle
# ---------------------------------------------------------------------------

func _start_env(env_name: String) -> void:
        # Tear down old academy + grid
        if _academy:
                _academy.queue_free()
                _academy = null
        if _grid:
                _grid.queue_free()
                _grid = null
                # Wait a frame so children are actually freed
                await get_tree().process_frame

        # Create academy
        _academy = RLAcademy.new()
        _academy.env_name = env_name
        _academy.num_envs = int(_num_envs_spin.value)
        _academy.decision_period = 1
        _academy.time_scale = float(_speed_spin.value)
        _academy.render_envs = true
        _academy.env_viewport_size = Vector2i(192, 192)
        add_child(_academy)

        # Wire up random action source + stats
        _academy.set_action_source(RLRandomActionSource.new())

        # Create grid (will re-parent env viewports from academy)
        _grid = RLPreviewGrid.new()
        _grid.columns = int(_columns_spin.value)
        _grid.show_stats = true
        _grid.set_anchors_preset(PRESET_FULL_RECT)
        _grid_host.add_child(_grid)
        _grid.set_academy(_academy)

        # Connect stats updates
        if not _academy.step_completed.is_connected(_on_step_completed):
                _academy.step_completed.connect(_on_step_completed)


func _on_step_completed(_stats: Array) -> void:
        _stats_dirty = true


func _process(_delta: float) -> void:
        if _stats_dirty and _academy and _academy.is_spawned():
                _update_stats()
                _stats_dirty = false


func _update_stats() -> void:
        var stats := _academy.get_stats()
        if stats.is_empty():
                return

        var total_reward := 0.0
        var total_episodes := 0
        var total_steps := 0
        var best: float = -INF

        for s in stats:
                total_reward += s.get("episode_reward", 0.0)
                total_episodes += s.get("episode", 0)
                total_steps += s.get("steps", 0)
                var b: float = s.get("best_reward", -INF)
                if b > best:
                        best = b

        var avg_steps: float = float(total_steps) / max(1, stats.size())

        _agg_labels["envs"].text = str(stats.size())
        _agg_labels["episodes"].text = str(total_episodes)
        _agg_labels["total_reward"].text = "%.1f" % total_reward
        _agg_labels["avg_steps"].text = "%.1f" % avg_steps
        _agg_labels["best_reward"].text = "%.1f" % best if best > -INF else "—"

        # Rebuild per-env rows if count changed
        if _per_env_container.get_child_count() != stats.size():
                for child in _per_env_container.get_children():
                        child.queue_free()
                for i in range(stats.size()):
                        var row := HBoxContainer.new()
                        row.add_theme_constant_override("separation", 6)
                        var idx_lbl := _make_label("#%d" % i)
                        idx_lbl.modulate = Color(0.6, 0.75, 1.0)
                        idx_lbl.custom_minimum_size.x = 36
                        var ep_lbl := _make_label("ep:0")
                        ep_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                        var r_lbl := _make_label("r:0")
                        r_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                        var best_lbl := _make_label("best:0")
                        best_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                        best_lbl.modulate = Color(0.9, 0.85, 0.5)
                        row.add_child(idx_lbl)
                        row.add_child(ep_lbl)
                        row.add_child(r_lbl)
                        row.add_child(best_lbl)
                        _per_env_container.add_child(row)

        # Update per-env values
        var i := 0
        for s in stats:
                if i < _per_env_container.get_child_count():
                        var row: HBoxContainer = _per_env_container.get_child(i)
                        row.get_child(1).text = "ep:%d" % s.get("episode", 0)
                        row.get_child(2).text = "r:%.1f" % s.get("episode_reward", 0.0)
                        row.get_child(3).text = "best:%.1f" % s.get("best_reward", -INF)
                i += 1


# ---------------------------------------------------------------------------
# Toolbar callbacks
# ---------------------------------------------------------------------------

func _on_env_changed(_idx: int) -> void:
        _start_env(_env_select.get_item_text(_env_select.selected))


func _on_params_changed(_v: float) -> void:
        _start_env(_env_select.get_item_text(_env_select.selected))


func _on_speed_changed(v: float) -> void:
        if _academy:
                _academy.time_scale = v
                Engine.time_scale = v


func _on_play_pause() -> void:
        _playing = not _playing
        _play_pause_btn.text = "Pause" if _playing else "Play"
        if _academy:
                _academy.set_physics_process(_playing)


func _on_reset() -> void:
        _start_env(_env_select.get_item_text(_env_select.selected))


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func color_self(c: Color) -> void:
        var bg := ColorRect.new()
        bg.color = c
        bg.set_anchors_preset(PRESET_FULL_RECT)
        bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(bg)
        move_child(bg, 0)


func _make_label(text: String) -> Label:
        var lbl := Label.new()
        lbl.text = text
        lbl.add_theme_font_size_override("font_size", 13)
        return lbl


func _make_section_label(text: String) -> Label:
        var lbl := Label.new()
        lbl.text = text
        lbl.add_theme_font_size_override("font_size", 14)
        lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
        return lbl


func _make_spinbox(min_v: float, max_v: float, val: float, step: float = 1.0) -> SpinBox:
        var sb := SpinBox.new()
        sb.min_value = min_v
        sb.max_value = max_v
        sb.value = val
        sb.step = step
        sb.custom_minimum_size.x = 70
        return sb


func _make_vsep() -> VSeparator:
        var sep := VSeparator.new()
        sep.add_theme_constant_override("separation", 12)
        return sep


func _make_hsep() -> HSeparator:
        var sep := HSeparator.new()
        sep.add_theme_constant_override("separation", 8)
        return sep
