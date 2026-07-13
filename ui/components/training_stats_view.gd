## Comprehensive, scrollable training stats view.
##
## Sections (top to bottom, all inside a ScrollContainer):
##   1. Overview: generation, population, best/avg/median/worst/std fitness
##   2. Fitness Chart: best + avg + median lines over generations (drawn on a Panel)
##   3. Topology: avg/min/max nodes & connections, enabled/disabled ratio
##   4. Speciation: species count, compatibility threshold, threshold chart
##   5. Species Table: per-species breakdown (ID, members, best, avg, staleness, etc.)
##   6. Algorithm Config: the NEAT strategy choices + key hyperparameters
##   7. History Log: scrollable text log of each generation
extends VBoxContainer
class_name TrainingStatsView

# --- Color palette (matches GraphVisualizer for consistency) ---
const COL_HEADING := Color(0.88, 0.88, 0.94, 1)
const COL_BODY := Color(0.75, 0.75, 0.82, 1)
const COL_MUTED := Color(0.55, 0.55, 0.62, 1)
const COL_ACCENT := Color(0.4, 0.7, 1.0, 1)
const COL_GREEN := Color(0.4, 0.85, 0.55, 1)
const COL_RED := Color(1.0, 0.5, 0.45, 1)
const COL_YELLOW := Color(1.0, 0.8, 0.35, 1)
const COL_PURPLE := Color(0.7, 0.5, 1.0, 1)
const COL_CHART_BG := Color(0.05, 0.05, 0.08, 1)
const COL_CHART_BORDER := Color(0.22, 0.22, 0.3, 1)
const COL_CHART_GRID := Color(0.18, 0.18, 0.24, 0.5)

var tracker: TrainingStatsTracker = null:
        set(t):
                tracker = t
                refresh()

@onready var _scroll: ScrollContainer = $ScrollContainer
# Overview
@onready var _ov_gen: Label = $ScrollContainer/VBox/OverviewSection/OverviewGrid/OVGen
@onready var _ov_pop: Label = $ScrollContainer/VBox/OverviewSection/OverviewGrid/OVPop
@onready var _ov_best: Label = $ScrollContainer/VBox/OverviewSection/OverviewGrid/OVBest
@onready var _ov_gen_best: Label = $ScrollContainer/VBox/OverviewSection/OverviewGrid/OVGenBest
@onready var _ov_avg: Label = $ScrollContainer/VBox/OverviewSection/OverviewGrid/OVAvg
@onready var _ov_median: Label = $ScrollContainer/VBox/OverviewSection/OverviewGrid/OVMedian
@onready var _ov_worst: Label = $ScrollContainer/VBox/OverviewSection/OverviewGrid/OVWorst
@onready var _ov_std: Label = $ScrollContainer/VBox/OverviewSection/OverviewGrid/OVStd
# Topology
@onready var _tp_avg_nodes: Label = $ScrollContainer/VBox/TopologySection/TopologyGrid/TPAvgNodes
@onready var _tp_avg_conns: Label = $ScrollContainer/VBox/TopologySection/TopologyGrid/TPAvgConns
@onready var _tp_min_max_nodes: Label = $ScrollContainer/VBox/TopologySection/TopologyGrid/TPMinMaxNodes
@onready var _tp_min_max_conns: Label = $ScrollContainer/VBox/TopologySection/TopologyGrid/TPMinMaxConns
@onready var _tp_enabled: Label = $ScrollContainer/VBox/TopologySection/TopologyGrid/TPEnabled
@onready var _tp_disabled: Label = $ScrollContainer/VBox/TopologySection/TopologyGrid/TPDisabled
# Speciation
@onready var _sp_count: Label = $ScrollContainer/VBox/SpeciationSection/SpeciationGrid/SPCount
@onready var _sp_threshold: Label = $ScrollContainer/VBox/SpeciationSection/SpeciationGrid/SPThreshold
@onready var _sp_target: Label = $ScrollContainer/VBox/SpeciationSection/SpeciationGrid/SPTarget
# Charts
@onready var _fitness_chart: Panel = $ScrollContainer/VBox/FitnessChartSection/FitnessChart
@onready var _threshold_chart: Panel = $ScrollContainer/VBox/ThresholdChartSection/ThresholdChart
# Species table
@onready var _species_table: GridContainer = $ScrollContainer/VBox/SpeciesTableSection/SpeciesTable
# Config
@onready var _config_grid: GridContainer = $ScrollContainer/VBox/ConfigSection/ConfigGrid
# History
@onready var _history_list: ItemList = $ScrollContainer/VBox/HistorySection/HistoryList

var _refresh_counter: int = 0

func _ready() -> void:
        _fitness_chart.draw.connect(_on_fitness_chart_draw)
        _threshold_chart.draw.connect(_on_threshold_chart_draw)

func refresh() -> void:
        if tracker == null:
                return
        # Overview
        _ov_gen.text = str(tracker.generation)
        var pop_size: int = int(tracker.config_snapshot.get("population_size", 0))
        _ov_pop.text = str(pop_size)
        _ov_best.text = "%.4f" % tracker.best_fitness
        _ov_gen_best.text = "%.4f" % tracker.gen_best_fitness
        _ov_avg.text = "%.4f" % tracker.avg_fitness
        _ov_median.text = "%.4f" % tracker.median_fitness
        _ov_worst.text = "%.4f" % tracker.worst_fitness
        _ov_std.text = "%.4f" % tracker.fitness_std
        # Color the best green if improving, red if stagnating
        if tracker.gen_best_history.size() >= 2:
                var prev: float = tracker.gen_best_history[tracker.gen_best_history.size() - 2]
                if tracker.gen_best_fitness > prev + 1e-6:
                        _ov_gen_best.add_theme_color_override("font_color", COL_GREEN)
                elif tracker.gen_best_fitness < prev - 1e-6:
                        _ov_gen_best.add_theme_color_override("font_color", COL_RED)
                else:
                        _ov_gen_best.add_theme_color_override("font_color", COL_YELLOW)
        else:
                _ov_gen_best.add_theme_color_override("font_color", COL_BODY)
        # Topology
        _tp_avg_nodes.text = "%.1f" % tracker.avg_nodes
        _tp_avg_conns.text = "%.1f" % tracker.avg_conns
        _tp_min_max_nodes.text = "%d – %d" % [tracker.min_nodes, tracker.max_nodes]
        _tp_min_max_conns.text = "%d – %d" % [tracker.min_conns, tracker.max_conns]
        _tp_enabled.text = str(tracker.total_enabled_conns)
        _tp_disabled.text = str(tracker.total_disabled_conns)
        # Speciation
        _sp_count.text = str(tracker.species_count)
        _sp_threshold.text = "%.3f" % tracker.compatibility_threshold
        _sp_target.text = str(int(tracker.config_snapshot.get("target_species_count", 0)))
        # Species table
        _rebuild_species_table()
        # Config
        _rebuild_config_grid()
        # History
        _history_list.clear()
        for entry in tracker.history:
                _history_list.add_item(entry)
        # Scroll to bottom (latest entry)
        if _history_list.item_count > 0:
                var vbar: VScrollBar = _history_list.get_v_scroll_bar()
                if vbar != null:
                        vbar.value = vbar.max_value
        # Charts
        _fitness_chart.queue_redraw()
        _threshold_chart.queue_redraw()

func _process(_delta: float) -> void:
        # Auto-refresh a few times per second so the view stays live during training.
        _refresh_counter += 1
        if _refresh_counter >= 15:
                _refresh_counter = 0
                if tracker != null:
                        refresh()

func _rebuild_species_table() -> void:
        # The GridContainer has 2 header rows (label + separator) pre-built.
        # We rebuild the data rows each time.
        # Children: [HeaderLabel0, HeaderValue0, HeaderLabel1, HeaderValue1, ...]
        # We keep the header row (first 8 children = 4 columns x 2 rows) and
        # rebuild the rest.
        # Actually, the GridContainer has columns=4. So row 0 = children 0-3 (headers).
        # Row 1+ = data.
        # Remove all data rows (keep first 4 children = headers).
        while _species_table.get_child_count() > 4:
                var last: Node = _species_table.get_child(_species_table.get_child_count() - 1)
                _species_table.remove_child(last)
                last.queue_free()
        # Add data rows.
        for sp_dict in tracker.species_snapshot:
                var id_lbl := Label.new()
                id_lbl.text = str(sp_dict["id"])
                _style_data_label(id_lbl)
                var members_lbl := Label.new()
                members_lbl.text = str(sp_dict["members"])
                _style_data_label(members_lbl)
                members_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                var best_lbl := Label.new()
                best_lbl.text = "%.3f" % float(sp_dict["best_fitness"])
                _style_data_label(best_lbl)
                best_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                var detail_lbl := Label.new()
                var staleness: int = int(sp_dict["staleness"])
                var detail_str: String = "avg=%.2f stale=%d alloc=%d mult=%.1fx n=%.1f c=%.1f" % [
                        float(sp_dict["avg_fitness"]), staleness,
                        int(sp_dict["allocated_children"]),
                        float(sp_dict["mutation_rate_multiplier"]),
                        float(sp_dict["avg_nodes"]), float(sp_dict["avg_conns"])
                ]
                detail_lbl.text = detail_str
                _style_data_label(detail_lbl)
                detail_lbl.add_theme_font_size_override("font_size", 10)
                # Color staleness: green=fresh, yellow=stale, red=very stale
                if staleness <= 2:
                        detail_lbl.add_theme_color_override("font_color", COL_GREEN)
                elif staleness <= 10:
                        detail_lbl.add_theme_color_override("font_color", COL_YELLOW)
                else:
                        detail_lbl.add_theme_color_override("font_color", COL_RED)
                _species_table.add_child(id_lbl)
                _species_table.add_child(members_lbl)
                _species_table.add_child(best_lbl)
                _species_table.add_child(detail_lbl)

func _style_data_label(lbl: Label) -> void:
        lbl.add_theme_color_override("font_color", COL_BODY)
        lbl.add_theme_font_size_override("font_size", 11)

func _rebuild_config_grid() -> void:
        # ConfigGrid has columns=2 with pre-built label pairs.
        # We populate them by index. The grid has 24 pairs (48 children).
        var cfg: Dictionary = tracker.config_snapshot
        var entries: Array = [
                ["Population", str(cfg.get("population_size", "-"))],
                ["Inputs / Outputs", "%d / %d" % [int(cfg.get("num_inputs", 0)), int(cfg.get("num_outputs", 0))]],
                ["Use Bias", "yes" if bool(cfg.get("use_bias", false)) else "no"],
                ["Forward Mode", str(cfg.get("forward_mode", "-"))],
                ["Input Activation", str(cfg.get("input_activation", "-"))],
                ["Output Activation", str(cfg.get("output_activation", "-"))],
                ["Hidden Activation", str(cfg.get("hidden_activation", "-"))],
                ["Selection", str(cfg.get("selection_method", "-"))],
                ["Similarity", str(cfg.get("similarity_method", "-"))],
                ["Speciation", str(cfg.get("speciation_method", "-"))],
                ["Evaluation", str(cfg.get("evaluation_method", "-"))],
                ["Generation", str(cfg.get("generation_method", "-"))],
                ["Crossover (neuron)", str(cfg.get("neuron_crossover_method", "-"))],
                ["Crossover (overall)", str(cfg.get("overall_crossover_method", "-"))],
                ["Mutation Policy", str(cfg.get("mutation_policy_method", "-"))],
                ["Stacked Mutation", "yes" if bool(cfg.get("mutation_stacked", false)) else "no"],
                ["Elite Count", str(cfg.get("elite_count", "-"))],
                ["Interspecies Rate", "%.3f" % float(cfg.get("interspecies_rate", 0))],
                ["Crossover Rate", "%.3f" % float(cfg.get("crossover_rate", 0))],
                ["Weight Mut Rate", "%.3f" % float(cfg.get("weight_mutation_rate", 0))],
                ["Conn Mut Rate", "%.3f" % float(cfg.get("connection_mutation_rate", 0))],
                ["Neuron Mut Rate", "%.3f" % float(cfg.get("neuron_mutation_rate", 0))],
                ["Prune Mut Rate", "%.3f" % float(cfg.get("prune_mutation_rate", 0))],
                ["Enable Mut Rate", "%.3f" % float(cfg.get("enable_mutation_rate", 0))],
        ]
        var grid := _config_grid
        for i in range(entries.size()):
                var base: int = i * 2
                if base + 1 >= grid.get_child_count():
                        break
                var lbl: Label = grid.get_child(base)
                var val: Label = grid.get_child(base + 1)
                lbl.text = entries[i][0]
                val.text = str(entries[i][1])

# --- Chart drawing ---

func _on_fitness_chart_draw() -> void:
        if tracker == null:
                return
        _draw_line_chart(_fitness_chart, {
                "Best": {"data": tracker.best_history, "color": COL_ACCENT, "width": 2.0},
                "Average": {"data": tracker.avg_history, "color": COL_GREEN, "width": 1.5},
                "Median": {"data": tracker.median_history, "color": COL_YELLOW, "width": 1.5},
        }, "Fitness Over Generations")

func _on_threshold_chart_draw() -> void:
        if tracker == null:
                return
        _draw_line_chart(_threshold_chart, {
                "Threshold": {"data": tracker.threshold_history, "color": COL_PURPLE, "width": 2.0},
                "Species Count": {"data": _int_array_to_float(tracker.species_count_history), "color": COL_GREEN, "width": 1.5},
        }, "Speciation Dynamics")

func _int_array_to_float(arr: Array) -> Array[float]:
        var out: Array[float] = []
        out.resize(arr.size())
        for i in range(arr.size()):
                out[i] = float(arr[i])
        return out

func _draw_line_chart(panel: Panel, series: Dictionary, title: String) -> void:
        var size_vec: Vector2 = panel.get_size()
        if size_vec.x < 2 or size_vec.y < 2:
                return
        # Background.
        panel.draw_rect(Rect2(Vector2.ZERO, size_vec), COL_CHART_BG, true)
        panel.draw_rect(Rect2(Vector2.ZERO, size_vec), COL_CHART_BORDER, false, 1.0)
        # Title.
        panel.draw_string(ThemeDB.fallback_font, Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_HEADING)
        # Check if we have data.
        var has_data: bool = false
        for key in series:
                var s: Dictionary = series[key]
                if s["data"].size() >= 2:
                        has_data = true
                        break
        if not has_data:
                panel.draw_string(ThemeDB.fallback_font, Vector2(8, size_vec.y * 0.55), "Collecting data...", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_MUTED)
                # Draw legend even with no data.
                _draw_legend(panel, series, size_vec)
                return
        # Compute min/max across all series.
        var min_val: float = INF
        var max_val: float = -INF
        for key in series:
                var s: Dictionary = series[key]
                for v in s["data"]:
                        if v < min_val:
                                min_val = v
                        if v > max_val:
                                max_val = v
        if max_val - min_val < 1e-6:
                max_val = min_val + 1.0
        # Add 5% padding.
        var pad: float = (max_val - min_val) * 0.05
        min_val -= pad
        max_val += pad
        # Chart area (leave room for title, legend, axes).
        var chart_left: float = 36.0
        var chart_top: float = 24.0
        var chart_right: float = size_vec.x - 8.0
        var chart_bottom: float = size_vec.y - 28.0
        var chart_w: float = chart_right - chart_left
        var chart_h: float = chart_bottom - chart_top
        if chart_w < 2 or chart_h < 2:
                return
        # Grid lines (horizontal).
        var grid_lines: int = 4
        for i in range(grid_lines + 1):
                var y: float = chart_top + (float(i) / float(grid_lines)) * chart_h
                panel.draw_line(Vector2(chart_left, y), Vector2(chart_right, y), COL_CHART_GRID, 1.0)
                # Y-axis label.
                var val: float = max_val - (float(i) / float(grid_lines)) * (max_val - min_val)
                panel.draw_string(ThemeDB.fallback_font, Vector2(2, y + 4), "%.1f" % val, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_MUTED)
        # X-axis label (generation).
        var last_gen: int = tracker.generation
        var first_gen: int = maxi(0, last_gen - tracker.best_history.size() + 1)
        panel.draw_string(ThemeDB.fallback_font, Vector2(chart_left, chart_bottom + 14), "Gen %d" % first_gen, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_MUTED)
        panel.draw_string(ThemeDB.fallback_font, Vector2(chart_right - 30, chart_bottom + 14), "Gen %d" % last_gen, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_MUTED)
        # Draw each series.
        for key in series:
                var s: Dictionary = series[key]
                var data: Array = s["data"]
                if data.size() < 2:
                        continue
                var color: Color = s["color"]
                var width: float = s["width"]
                var n: int = data.size()
                var points: Array[Vector2] = []
                for i in range(n):
                        var x: float = chart_left + (float(i) / float(maxi(1, n - 1))) * chart_w
                        var y: float = chart_top + chart_h - ((data[i] - min_val) / (max_val - min_val)) * chart_h
                        points.append(Vector2(x, y))
                # Draw line segments.
                for i in range(points.size() - 1):
                        panel.draw_line(points[i], points[i + 1], color, width)
                # Draw points (small circles) for small datasets.
                if n <= 50:
                        for p in points:
                                panel.draw_circle(p, 2.0, color)
        # Draw legend.
        _draw_legend(panel, series, size_vec)

func _draw_legend(panel: Panel, series: Dictionary, size_vec: Vector2) -> void:
        var legend_x: float = size_vec.x - 100.0
        var legend_y: float = 6.0
        var i: int = 0
        for key in series:
                var s: Dictionary = series[key]
                var color: Color = s["color"]
                var y: float = legend_y + float(i) * 14.0
                # Color swatch.
                panel.draw_rect(Rect2(legend_x, y + 2, 10, 8), color, true)
                # Label.
                panel.draw_string(ThemeDB.fallback_font, Vector2(legend_x + 14, y + 10), str(key), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_BODY)
                i += 1
