## Lays out all env SubViewports in a grid for the "watch all envs train" view.
##
## Each cell is a SubViewportContainer that hosts the env's existing
## SubViewport. We re-parent the SubViewport from the Academy into
## the container so the same physics world keeps running.
extends Control

class_name RLPreviewGrid

@export var columns: int = 4
@export var show_stats: bool = true
@export var stat_font_size: int = 10

var _academy: RLAcademy
var _grid: GridContainer
# B3 fix: store cell Control nodes directly so we can free them
var _cell_nodes: Array[Control] = []
var _cell_data: Array = []


func _ready() -> void:
        _build_ui()


func set_academy(academy: RLAcademy) -> void:
        _academy = academy
        if not academy.is_spawned():
                await academy.spawned
        _rebuild_grid()


func _build_ui() -> void:
        _grid = GridContainer.new()
        _grid.columns = columns
        _grid.set_anchors_preset(Control.PRESET_FULL_RECT)
        _grid.offset_left = 8
        _grid.offset_top = 8
        _grid.offset_right = -8
        _grid.offset_bottom = -8
        add_child(_grid)


func _rebuild_grid() -> void:
        # B3 fix: free cell nodes properly (is_instance_valid on Nodes, not Dictionaries)
        for cell_node in _cell_nodes:
                if is_instance_valid(cell_node):
                        cell_node.queue_free()
        _cell_nodes.clear()
        _cell_data.clear()

        if not _academy:
                return

        var n := _academy.get_num_envs()
        for i in range(n):
                var cell := Control.new()
                cell.custom_minimum_size = _academy.env_viewport_size

                var svc := SubViewportContainer.new()
                svc.stretch = true
                svc.set_anchors_preset(Control.PRESET_FULL_RECT)
                cell.add_child(svc)

                var lbl := Label.new()
                lbl.text = "#%d" % i
                lbl.add_theme_font_size_override("font_size", stat_font_size)
                lbl.position = Vector2(2, 2)
                lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
                lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
                lbl.add_theme_constant_override("shadow_offset_x", 1)
                lbl.add_theme_constant_override("shadow_offset_y", 1)
                cell.add_child(lbl)

                _grid.add_child(cell)
                _cell_nodes.append(cell)
                _cell_data.append({"cell": cell, "svc": svc, "label": lbl, "env_idx": i})

                # Re-parent the env's viewport from the Academy into this cell
                var vp := _academy.get_viewport_for_env(i)
                if vp:
                        vp.get_parent().remove_child(vp)
                        svc.add_child(vp)
                        vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
                        # Re-activate the camera after re-parenting
                        var env := _academy.get_env(i)
                        if env:
                                for child in env.find_children("*", "Camera2D", true, false):
                                        (child as Camera2D).make_current()
                                        break

        if not _academy.step_completed.is_connected(_on_step):
                _academy.step_completed.connect(_on_step)


func _on_step(stats: Array) -> void:
        if not show_stats:
                return
        for entry in _cell_data:
                var idx: int = entry["env_idx"]
                if idx >= 0 and idx < stats.size():
                        var s: Dictionary = stats[idx]
                        var lbl: Label = entry["label"]
                        lbl.text = "#%d  ep:%d  r:%.1f  best:%.1f" % [
                                idx,
                                s.get("episode", 0),
                                s.get("episode_reward", 0.0),
                                s.get("best_reward", -INF),
                        ]
