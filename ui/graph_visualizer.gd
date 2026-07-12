## Panel showing species/genome navigation, the graph visualization, and stats.
## Lives in the top-right corner of the main runner.
class_name GraphVisualizer
extends Panel

var population: Population = null:
	set(p):
		population = p
		_current_species_idx = 0
		_current_genome_idx = 0
		_refresh()

var _current_species_idx: int = 0
var _current_genome_idx: int = 0

var _species_label: Label
var _genome_label: Label
var _prev_species_btn: Button
var _next_species_btn: Button
var _prev_genome_btn: Button
var _next_genome_btn: Button
var _graph_view: GraphView
var _stats_label: Label

func _ready() -> void:
	# Build the UI.
	custom_minimum_size = Vector2(360, 480)
	# Layout: VBox with navigation rows, graph view, stats.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	add_child(vbox)
	# Species navigation row.
	var sp_row := HBoxContainer.new()
	vbox.add_child(sp_row)
	_prev_species_btn = Button.new()
	_prev_species_btn.text = "<"
	_prev_species_btn.custom_minimum_size = Vector2(30, 24)
	_prev_species_btn.pressed.connect(_prev_species)
	sp_row.add_child(_prev_species_btn)
	_species_label = Label.new()
	_species_label.text = "Species -/-"
	_species_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_species_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp_row.add_child(_species_label)
	_next_species_btn = Button.new()
	_next_species_btn.text = ">"
	_next_species_btn.custom_minimum_size = Vector2(30, 24)
	_next_species_btn.pressed.connect(_next_species)
	sp_row.add_child(_next_species_btn)
	# Genome navigation row.
	var g_row := HBoxContainer.new()
	vbox.add_child(g_row)
	_prev_genome_btn = Button.new()
	_prev_genome_btn.text = "<"
	_prev_genome_btn.custom_minimum_size = Vector2(30, 24)
	_prev_genome_btn.pressed.connect(_prev_genome)
	g_row.add_child(_prev_genome_btn)
	_genome_label = Label.new()
	_genome_label.text = "Genome -/-"
	_genome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_genome_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g_row.add_child(_genome_label)
	_next_genome_btn = Button.new()
	_next_genome_btn.text = ">"
	_next_genome_btn.custom_minimum_size = Vector2(30, 24)
	_next_genome_btn.pressed.connect(_next_genome)
	g_row.add_child(_next_genome_btn)
	# Graph view.
	_graph_view = GraphView.new()
	_graph_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_graph_view)
	# Stats label.
	_stats_label = Label.new()
	_stats_label.text = ""
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_label.add_theme_font_override("font", ThemeDB.fallback_font)
	_stats_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_stats_label)

func _prev_species() -> void:
	if population == null or population.species_list.is_empty():
		return
	_current_species_idx = (_current_species_idx - 1 + population.species_list.size()) % population.species_list.size()
	_current_genome_idx = 0
	_refresh()

func _next_species() -> void:
	if population == null or population.species_list.is_empty():
		return
	_current_species_idx = (_current_species_idx + 1) % population.species_list.size()
	_current_genome_idx = 0
	_refresh()

func _prev_genome() -> void:
	var sp := _current_species()
	if sp == null or sp.members.is_empty():
		return
	_current_genome_idx = (_current_genome_idx - 1 + sp.members.size()) % sp.members.size()
	_refresh()

func _next_genome() -> void:
	var sp := _current_species()
	if sp == null or sp.members.is_empty():
		return
	_current_genome_idx = (_current_genome_idx + 1) % sp.members.size()
	_refresh()

func _current_species() -> Species:
	if population == null or population.species_list.is_empty():
		return null
	if _current_species_idx >= population.species_list.size():
		_current_species_idx = 0
	return population.species_list[_current_species_idx]

func _refresh() -> void:
	if population == null:
		return
	var sp := _current_species()
	if sp == null:
		_species_label.text = "Species -/-"
		_genome_label.text = "Genome -/-"
		_graph_view.genome = null
		_stats_label.text = ""
		return
	_species_label.text = "Species %d (%d/%d)" % [sp.id, _current_species_idx + 1, population.species_list.size()]
	if sp.members.is_empty():
		_genome_label.text = "Genome -/-"
		_graph_view.genome = null
		_stats_label.text = ""
		return
	if _current_genome_idx >= sp.members.size():
		_current_genome_idx = 0
	var g: Genome = sp.members[_current_genome_idx]
	_genome_label.text = "Genome %d/%d" % [_current_genome_idx + 1, sp.members.size()]
	_graph_view.genome = g
	# Stats.
	var avg_fit: float = 0.0
	for m: Genome in sp.members:
		avg_fit += m.fitness
	avg_fit /= float(sp.members.size())
	_stats_label.text = "Genome: nodes=%d conns=%d fit=%.3f\nSpecies: members=%d best=%.3f avg=%.3f stale=%d alloc=%d mrx%.2f" % [
		g.node_count(), g.connection_count(), g.fitness,
		sp.members.size(), sp.best_fitness, avg_fit, sp.staleness,
		sp.allocated_children, sp.mutation_rate_multiplier,
	]

## Force a refresh (call after each generation).
func refresh() -> void:
	_refresh()
