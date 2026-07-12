## Training stats view with live fitness-over-generations graph.
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
@onready var _graph: Control = $Graph

var _refresh_counter: int = 0

func _ready() -> void:
	_graph.draw.connect(_on_graph_draw)

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
	_graph.queue_redraw()

func _process(_delta: float) -> void:
	# Auto-refresh a few times per second.
	_refresh_counter += 1
	if _refresh_counter >= 10:
		_refresh_counter = 0
		if tracker != null:
			refresh()

func _on_graph_draw() -> void:
	if tracker == null or tracker.history.size() < 2:
		return
	var size_vec := _graph.get_size()
	if size_vec.x < 2 or size_vec.y < 2:
		return
	# Background.
	_graph.draw_rect(Rect2(Vector2.ZERO, size_vec), Color(0.06, 0.06, 0.1), true)
	_graph.draw_rect(Rect2(Vector2.ZERO, size_vec), Color(0.2, 0.2, 0.28), false, 1.0)
	var data := tracker.best_history
	var avg_data := tracker.avg_history
	if data.size() < 2:
		return
	var min_val: float = data[0]
	var max_val: float = data[0]
	for v in data:
		if v < min_val: min_val = v
		if v > max_val: max_val = v
	for v in avg_data:
		if v < min_val: min_val = v
		if v > max_val: max_val = v
	if max_val - min_val < 0.001:
		max_val = min_val + 1.0
	var padding := 8.0
	var w := size_vec.x - padding * 2
	var h := size_vec.y - padding * 2
	# Draw avg fitness line (green).
	var points_avg := PackedVector2Array()
	for i in range(avg_data.size()):
		var x: float = padding + (float(i) / float(maxi(1, avg_data.size() - 1))) * w
		var y: float = padding + h - ((avg_data[i] - min_val) / (max_val - min_val)) * h
		points_avg.append(Vector2(x, y))
	if points_avg.size() >= 2:
		for i in range(points_avg.size() - 1):
			_graph.draw_line(points_avg[i], points_avg[i + 1], Color(0.3, 0.8, 0.4), 1.5)
	# Draw best fitness line (blue, thicker).
	var points_best := PackedVector2Array()
	for i in range(data.size()):
		var x: float = padding + (float(i) / float(maxi(1, data.size() - 1))) * w
		var y: float = padding + h - ((data[i] - min_val) / (max_val - min_val)) * h
		points_best.append(Vector2(x, y))
	if points_best.size() >= 2:
		for i in range(points_best.size() - 1):
			_graph.draw_line(points_best[i], points_best[i + 1], Color(0.3, 0.7, 1.0), 2.0)
	# Labels.
	_graph.draw_string(ThemeDB.fallback_font, Vector2(padding, padding + 10), "Best: %.2f" % tracker.best_fitness, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.7, 1.0))
	_graph.draw_string(ThemeDB.fallback_font, Vector2(padding, padding + 24), "Avg: %.2f" % tracker.avg_fitness, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.8, 0.4))
	_graph.draw_string(ThemeDB.fallback_font, Vector2(padding, size_vec.y - 4), "Gen %d" % tracker.generation, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.6))
