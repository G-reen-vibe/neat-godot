## Panel showing species/genome navigation + a GraphView + detailed stats.
## Composes the GraphView tscn (real scene node) instead of building it
## programmatically.
##
## Features:
##   - Prev/Next arrow buttons for species and genome navigation.
##   - OptionButton dropdowns for direct species/genome selection.
##   - "Best" toggle button to view the population's best genome snapshot.
##   - Detailed per-genome and per-species reporting panel.
extends PanelContainer
class_name GraphVisualizer

const GraphViewScene: PackedScene = preload("res://ui/components/graph_view.tscn")

# --- Color palette (shared across the panel for consistency) ---
const COL_HEADING := Color(0.88, 0.88, 0.94, 1)
const COL_BODY := Color(0.75, 0.75, 0.82, 1)
const COL_MUTED := Color(0.55, 0.55, 0.62, 1)
const COL_ACCENT := Color(0.4, 0.7, 1.0, 1)
const COL_GREEN := Color(0.4, 0.85, 0.55, 1)
const COL_RED := Color(1.0, 0.5, 0.45, 1)
const COL_YELLOW := Color(1.0, 0.8, 0.35, 1)
const COL_PANEL_BG := Color(0.08, 0.08, 0.12, 1)
const COL_PANEL_BORDER := Color(0.22, 0.22, 0.3, 1)

var population: Population = null:
        set(p):
                population = p
                _current_species_idx = 0
                _current_genome_idx = 0
                _show_best = false
                if is_node_ready():
                        _best_btn.set_pressed_no_signal(false)
                _refresh()

var _current_species_idx: int = 0
var _current_genome_idx: int = 0
var _show_best: bool = false
var _suppress_dropdown_callback: bool = false

var _graph_view: GraphView

@onready var _prev_species: Button = $Margin/VBox/SpeciesRow/PrevSpecies
@onready var _next_species: Button = $Margin/VBox/SpeciesRow/NextSpecies
@onready var _species_dropdown: OptionButton = $Margin/VBox/SpeciesRow/SpeciesDropdown
@onready var _species_label: Label = $Margin/VBox/SpeciesRow/SpeciesLabel
@onready var _prev_genome: Button = $Margin/VBox/GenomeRow/PrevGenome
@onready var _next_genome: Button = $Margin/VBox/GenomeRow/NextGenome
@onready var _genome_dropdown: OptionButton = $Margin/VBox/GenomeRow/GenomeDropdown
@onready var _genome_label: Label = $Margin/VBox/GenomeRow/GenomeLabel
@onready var _best_btn: Button = $Margin/VBox/GenomeRow/BestBtn
@onready var _graph_view_parent: PanelContainer = $Margin/VBox/GraphViewParent
@onready var _stats_container: VBoxContainer = $Margin/VBox/ScrollContainer/StatsContainer
@onready var _genome_stats: GridContainer = $Margin/VBox/ScrollContainer/StatsContainer/GenomeSection/GenomeStats
@onready var _species_stats: GridContainer = $Margin/VBox/ScrollContainer/StatsContainer/SpeciesSection/SpeciesStats

func _ready() -> void:
        _graph_view = GraphViewScene.instantiate()
        _graph_view_parent.add_child(_graph_view)
        _prev_species.pressed.connect(_prev_species_click)
        _next_species.pressed.connect(_next_species_click)
        _prev_genome.pressed.connect(_prev_genome_click)
        _next_genome.pressed.connect(_next_genome_click)
        # Use pressed signal for the Best button (more reliable than toggled in
        # some TabContainer contexts). We manage the toggle state manually.
        _best_btn.pressed.connect(_on_best_pressed)
        _species_dropdown.item_selected.connect(_on_species_dropdown_selected)
        _genome_dropdown.item_selected.connect(_on_genome_dropdown_selected)

# --- Species navigation ---

func _prev_species_click() -> void:
        if population == null or population.species_list.is_empty():
                return
        _current_species_idx = (_current_species_idx - 1 + population.species_list.size()) % population.species_list.size()
        _current_genome_idx = 0
        _set_show_best(false)
        _refresh()

func _next_species_click() -> void:
        if population == null or population.species_list.is_empty():
                return
        _current_species_idx = (_current_species_idx + 1) % population.species_list.size()
        _current_genome_idx = 0
        _set_show_best(false)
        _refresh()

func _on_species_dropdown_selected(idx: int) -> void:
        if _suppress_dropdown_callback:
                return
        if population == null or idx < 0 or idx >= population.species_list.size():
                return
        _current_species_idx = idx
        _current_genome_idx = 0
        _set_show_best(false)
        _refresh()

# --- Genome navigation ---

func _prev_genome_click() -> void:
        var sp := _current_species()
        if sp == null or sp.members.is_empty():
                return
        _current_genome_idx = (_current_genome_idx - 1 + sp.members.size()) % sp.members.size()
        _set_show_best(false)
        _refresh()

func next_genome() -> void:
        _next_genome_click()

func _next_genome_click() -> void:
        var sp := _current_species()
        if sp == null or sp.members.is_empty():
                return
        _current_genome_idx = (_current_genome_idx + 1) % sp.members.size()
        _set_show_best(false)
        _refresh()

func _on_genome_dropdown_selected(idx: int) -> void:
        if _suppress_dropdown_callback:
                return
        var sp := _current_species()
        if sp == null or idx < 0 or idx >= sp.members.size():
                return
        _current_genome_idx = idx
        _set_show_best(false)
        _refresh()

# --- Best genome toggle ---

## Called when the Best button is pressed. Toggles _show_best on/off.
## Uses pressed signal (not toggled) for reliability. We manually manage
## the button's pressed state via set_pressed_no_signal to avoid recursive
## signal emission.
func _on_best_pressed() -> void:
        _set_show_best(not _show_best)

func _set_show_best(v: bool) -> void:
        _show_best = v
        _best_btn.set_pressed_no_signal(v)
        _refresh()

func show_best() -> void:
        if population == null or population.best_genome == null:
                return
        _set_show_best(true)

# --- Helpers ---

func _current_species() -> Species:
        if population == null or population.species_list.is_empty():
                return null
        if _current_species_idx >= population.species_list.size():
                _current_species_idx = 0
        return population.species_list[_current_species_idx]

func _current_genome() -> Genome:
        if _show_best:
                return population.best_genome if population != null else null
        var sp := _current_species()
        if sp == null or sp.members.is_empty():
                return null
        if _current_genome_idx >= sp.members.size():
                _current_genome_idx = 0
        return sp.members[_current_genome_idx]

# --- Refresh ---

func _refresh() -> void:
        if population == null:
                return
        # If showing best, use the best genome directly.
        if _show_best:
                if population.best_genome == null:
                        # No best genome yet; show a message and fall back.
                        _species_label.text = "Best Genome"
                        _genome_label.text = "(not available)"
                        _graph_view.genome = null
                        _update_dropdowns_for_best()
                        _update_best_unavailable_stats()
                        return
                _species_label.text = "Best Genome"
                _genome_label.text = "(snapshot)"
                _graph_view.genome = population.best_genome
                _update_dropdowns_for_best()
                _update_genome_stats(population.best_genome, null)
                return
        var sp := _current_species()
        if sp == null:
                _species_label.text = "Species -/-"
                _genome_label.text = "Genome -/-"
                _graph_view.genome = null
                _update_dropdowns(true)
                _clear_stats()
                return
        _species_label.text = "Species %d  (%d/%d)" % [sp.id, _current_species_idx + 1, population.species_list.size()]
        if sp.members.is_empty():
                _genome_label.text = "Genome -/-"
                _graph_view.genome = null
                _update_dropdowns(true)
                _clear_stats()
                return
        if _current_genome_idx >= sp.members.size():
                _current_genome_idx = 0
        var g: Genome = sp.members[_current_genome_idx]
        _genome_label.text = "Genome %d/%d" % [_current_genome_idx + 1, sp.members.size()]
        _graph_view.genome = g
        _update_dropdowns()
        _update_genome_stats(g, sp)

func _update_dropdowns_for_best() -> void:
        # When showing best, disable genome dropdown (no meaningful index).
        _suppress_dropdown_callback = true
        _genome_dropdown.clear()
        _genome_dropdown.add_item("(best snapshot)")
        _genome_dropdown.disabled = true
        # Species dropdown still works (shows current species context).
        _rebuild_species_dropdown()
        _suppress_dropdown_callback = false

func _update_dropdowns(empty: bool = false) -> void:
        _suppress_dropdown_callback = true
        if empty:
                _species_dropdown.clear()
                _species_dropdown.add_item("-/-")
                _species_dropdown.disabled = true
                _genome_dropdown.clear()
                _genome_dropdown.add_item("-/-")
                _genome_dropdown.disabled = true
                _suppress_dropdown_callback = false
                return
        _rebuild_species_dropdown()
        _rebuild_genome_dropdown()
        _suppress_dropdown_callback = false

func _rebuild_species_dropdown() -> void:
        _species_dropdown.clear()
        if population == null or population.species_list.is_empty():
                _species_dropdown.add_item("-/-")
                _species_dropdown.disabled = true
                return
        _species_dropdown.disabled = false
        for i in range(population.species_list.size()):
                var sp: Species = population.species_list[i]
                _species_dropdown.add_item("Species %d  (%d members)" % [sp.id, sp.members.size()])
        _species_dropdown.select(_current_species_idx)

func _rebuild_genome_dropdown() -> void:
        _genome_dropdown.clear()
        var sp := _current_species()
        if sp == null or sp.members.is_empty():
                _genome_dropdown.add_item("-/-")
                _genome_dropdown.disabled = true
                return
        _genome_dropdown.disabled = false
        for i in range(sp.members.size()):
                var g: Genome = sp.members[i]
                var fit_str: String = "%.3f" % g.fitness if g.fitness > -1e8 else "n/a"
                _genome_dropdown.add_item("#%d  fit=%s  n=%d c=%d" % [i + 1, fit_str, g.node_count(), g.connection_count()])
        _genome_dropdown.select(_current_genome_idx)

# --- Stats panel ---

func _clear_stats() -> void:
        for label in _genome_stats.get_children():
                label.text = "-"
        for label in _species_stats.get_children():
                label.text = "-"

func _update_best_unavailable_stats() -> void:
        _clear_stats()

func _update_genome_stats(g: Genome, sp: Species) -> void:
        if g == null:
                _clear_stats()
                return
        # Genome stats: each pair is (label_node, value_node) in the GridContainer.
        # GridContainer lays out children in row-major order with columns=2.
        var g_idx: int = 0
        # Genome section
        _set_grid_pair(_genome_stats, g_idx, "Nodes", str(g.node_count()))
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Connections", str(g.connection_count()))
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Enabled", str(g.enabled_connections().size()))
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Disabled", str(g.disabled_connections().size()))
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Inputs", str(g.input_nodes().size()))
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Hidden", str(g.hidden_nodes().size()))
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Outputs", str(g.output_nodes().size()))
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Bias", str(g.bias_nodes().size()))
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Fitness", "%.4f" % g.fitness)
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Adjusted Fit", "%.4f" % g.adjusted_fitness)
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Species ID", str(g.species_id))
        g_idx += 1
        # Weight statistics
        var w_min: float = INF
        var w_max: float = -INF
        var w_sum: float = 0.0
        var w_count: int = 0
        for c: ConnectionGene in g.connections.values():
                w_min = minf(w_min, c.weight)
                w_max = maxf(w_max, c.weight)
                w_sum += c.weight
                w_count += 1
        var w_avg: float = w_sum / float(maxi(1, w_count))
        _set_grid_pair(_genome_stats, g_idx, "Weight min", "%.3f" % (w_min if w_count > 0 else 0.0))
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Weight max", "%.3f" % (w_max if w_count > 0 else 0.0))
        g_idx += 1
        _set_grid_pair(_genome_stats, g_idx, "Weight avg", "%.3f" % w_avg)
        g_idx += 1
        # Has loop?
        _set_grid_pair(_genome_stats, g_idx, "Has Loop", "yes" if g.has_loop() else "no")
        g_idx += 1

        # Species stats (only if showing a species genome, not best)
        if sp == null:
                for label in _species_stats.get_children():
                        label.text = "-"
                return
        var s_idx: int = 0
        _set_grid_pair(_species_stats, s_idx, "Species ID", str(sp.id))
        s_idx += 1
        _set_grid_pair(_species_stats, s_idx, "Members", str(sp.members.size()))
        s_idx += 1
        _set_grid_pair(_species_stats, s_idx, "Best Fitness", "%.4f" % sp.best_fitness)
        s_idx += 1
        # Average fitness
        var avg_fit: float = 0.0
        for m: Genome in sp.members:
                avg_fit += m.fitness
        avg_fit /= float(maxi(1, sp.members.size()))
        _set_grid_pair(_species_stats, s_idx, "Avg Fitness", "%.4f" % avg_fit)
        s_idx += 1
        _set_grid_pair(_species_stats, s_idx, "Staleness", str(sp.staleness))
        s_idx += 1
        _set_grid_pair(_species_stats, s_idx, "Allocated Children", str(sp.allocated_children))
        s_idx += 1
        _set_grid_pair(_species_stats, s_idx, "Mutation Mult", "%.2fx" % sp.mutation_rate_multiplier)
        s_idx += 1
        # Species topology stats
        var sp_nodes_sum: int = 0
        var sp_conns_sum: int = 0
        for m: Genome in sp.members:
                sp_nodes_sum += m.node_count()
                sp_conns_sum += m.connection_count()
        _set_grid_pair(_species_stats, s_idx, "Avg Nodes", "%.1f" % (float(sp_nodes_sum) / float(maxi(1, sp.members.size()))))
        s_idx += 1
        _set_grid_pair(_species_stats, s_idx, "Avg Conns", "%.1f" % (float(sp_conns_sum) / float(maxi(1, sp.members.size()))))
        s_idx += 1
        # Best fitness history (last 5)
        var hist_str: String = ""
        var hist_len: int = sp.best_fitness_history.size()
        var start: int = maxi(0, hist_len - 5)
        for i in range(start, hist_len):
                if i > start:
                        hist_str += ", "
                hist_str += "%.2f" % sp.best_fitness_history[i]
        _set_grid_pair(_species_stats, s_idx, "Recent Best", hist_str if hist_str != "" else "-")
        s_idx += 1

func _set_grid_pair(grid: GridContainer, pair_index: int, label_text: String, value_text: String) -> void:
        var base: int = pair_index * 2
        if base + 1 >= grid.get_child_count():
                return
        var lbl: Label = grid.get_child(base)
        var val: Label = grid.get_child(base + 1)
        lbl.text = label_text
        val.text = value_text

func refresh() -> void:
        _refresh()
