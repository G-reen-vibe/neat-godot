## Panel showing species/genome navigation + a GraphView + stats. Composes
## the GraphView tscn (real scene node) instead of building it programmatically.
extends Panel
class_name GraphVisualizer

const GraphViewScene: PackedScene = preload("res://ui/components/graph_view.tscn")

var population: Population = null:
	set(p):
		population = p
		_current_species_idx = 0
		_current_genome_idx = 0
		_refresh()

var _current_species_idx: int = 0
var _current_genome_idx: int = 0

var _graph_view: GraphView

@onready var _prev_species: Button = $VBox/SpeciesRow/PrevSpecies
@onready var _next_species: Button = $VBox/SpeciesRow/NextSpecies
@onready var _species_label: Label = $VBox/SpeciesRow/SpeciesLabel
@onready var _prev_genome: Button = $VBox/GenomeRow/PrevGenome
@onready var _next_genome: Button = $VBox/GenomeRow/NextGenome
@onready var _genome_label: Label = $VBox/GenomeRow/GenomeLabel
@onready var _stats_label: Label = $VBox/StatsLabel
@onready var _graph_view_parent: Control = $VBox/GraphView

func _ready() -> void:
	_graph_view = GraphViewScene.instantiate()
	_graph_view_parent.add_child(_graph_view)
	_prev_species.pressed.connect(_prev_species_click)
	_next_species.pressed.connect(_next_species_click)
	_prev_genome.pressed.connect(_prev_genome_click)
	_next_genome.pressed.connect(_next_genome_click)

func _prev_species_click() -> void:
	if population == null or population.species_list.is_empty():
		return
	_current_species_idx = (_current_species_idx - 1 + population.species_list.size()) % population.species_list.size()
	_current_genome_idx = 0
	_refresh()

func _next_species_click() -> void:
	if population == null or population.species_list.is_empty():
		return
	_current_species_idx = (_current_species_idx + 1) % population.species_list.size()
	_current_genome_idx = 0
	_refresh()

func _prev_genome_click() -> void:
	var sp := _current_species()
	if sp == null or sp.members.is_empty():
		return
	_current_genome_idx = (_current_genome_idx - 1 + sp.members.size()) % sp.members.size()
	_refresh()

func _next_genome_click() -> void:
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
	var avg_fit: float = 0.0
	for m: Genome in sp.members:
		avg_fit += m.fitness
	avg_fit /= float(sp.members.size())
	_stats_label.text = "nodes=%d conns=%d fit=%.3f\nmembers=%d best=%.3f avg=%.3f" % [
		g.node_count(), g.connection_count(), g.fitness,
		sp.members.size(), sp.best_fitness, avg_fit]

func refresh() -> void:
	_refresh()
