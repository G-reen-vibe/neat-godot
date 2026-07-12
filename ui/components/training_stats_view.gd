extends VBoxContainer
class_name TrainingStatsView

var tracker: TrainingStatsTracker = null:
	set(t):
		tracker = t
		refresh()

@onready var _best_label: Label = $BestFitnessLabel
@onready var _avg_label: Label = $AvgFitnessLabel
@onready var _species_label: Label = $SpeciesLabel
@onready var _gen_label: Label = $GenLabel
@onready var _history: ItemList = $HistoryList

func refresh() -> void:
	if tracker == null:
		return
	_best_label.text = "Best: %.3f" % tracker.best_fitness
	_avg_label.text = "Avg: %.3f" % tracker.avg_fitness
	_species_label.text = "Species: %d" % tracker.species_count
	_gen_label.text = "Gen: %d" % tracker.generation
	_history.clear()
	for entry in tracker.history:
		_history.add_item(entry)

func _process(_delta: float) -> void:
	# Auto-refresh each frame so the view stays in sync.
	if tracker != null:
		refresh()
