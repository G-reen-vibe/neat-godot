class_name TrainingStatsView
extends Control
## Draws multiple graphs of training statistics over generations.
## Updates whenever [member tracker] changes (call [method refresh]).

var tracker: TrainingStatsTracker = null

enum GraphType { BEST_FITNESS, AVG_FITNESS, SPECIES_COUNT, GENOME_SIZE }

func _ready() -> void:
	custom_minimum_size = Vector2(340, 460)

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	var s := get_size()
	if s.x < 20 or s.y < 20:
		return
	# Background.
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.05, 0.09), true)
	if tracker == null or tracker.size() < 1:
		draw_string(ThemeDB.fallback_font, Vector2(8, 24), "No training data yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.5, 0.6))
		return
	# Layout: 4 graphs in a 2x2 grid.
	var pad: float = 8.0
	var title_h: float = 24.0
	var graph_w: float = (s.x - 3.0 * pad) * 0.5
	var graph_h: float = (s.y - title_h - 3.0 * pad) * 0.5
	var positions: Array = [
		Rect2(pad, title_h, graph_w, graph_h),
		Rect2(pad * 2 + graph_w, title_h, graph_w, graph_h),
		Rect2(pad, title_h * 2 + graph_h + pad, graph_w, graph_h),
		Rect2(pad * 2 + graph_w, title_h * 2 + graph_h + pad, graph_w, graph_h),
	]
	# Title.
	draw_string(ThemeDB.fallback_font, Vector2(pad, 18), "Training Statistics (%d generations)" % tracker.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.85, 0.9))
	# Draw each graph.
	_draw_graph(positions[0], "Best Fitness", tracker.best_fitness, Color(0.3, 0.9, 0.4))
	_draw_graph(positions[1], "Avg Fitness", tracker.avg_fitness, Color(0.3, 0.7, 1.0))
	_draw_graph(positions[2], "Species Count", tracker.species_count, Color(0.9, 0.7, 0.3), true)
	_draw_graph(positions[3], "Avg Conns / Max Conns", tracker.avg_conns, Color(0.8, 0.5, 0.9), false, tracker.max_conns)

func _draw_graph(rect: Rect2, title: String, data: Array, color: Color, is_int: bool = false, secondary_data: Array = []) -> void:
	# Background.
	draw_rect(rect, Color(0.08, 0.08, 0.12), true)
	draw_rect(rect, Color(0.25, 0.25, 0.32), false, 1.0)
	# Title.
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.75, 0.8))
	if data.size() < 2:
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x * 0.5 - 30, rect.size.y * 0.5), "...", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.4, 0.5))
		return
	# Compute min/max.
	var min_val: float = data[0]
	var max_val: float = data[0]
	for v in data:
		var fv: float = float(v)
		if fv < min_val:
			min_val = fv
		if fv > max_val:
			max_val = fv
	for v in secondary_data:
		var fv: float = float(v)
		if fv < min_val:
			min_val = fv
		if fv > max_val:
			max_val = fv
	if max_val - min_val < 1e-6:
		max_val = min_val + 1.0
	# Plot area (inside rect, below title).
	var plot := Rect2(rect.position.x + 6, rect.position.y + 20, rect.size.x - 12, rect.size.y - 26)
	# Draw axes (4 horizontal grid lines).
	var grid_color := Color(0.2, 0.2, 0.25)
	for i in range(5):
		var y: float = plot.position.y + plot.size.y * float(i) / 4.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.position.x + plot.size.x, y), grid_color, 1.0)
		# Y-axis label.
		var val: float = max_val - (max_val - min_val) * float(i) / 4.0
		var label: String
		if is_int:
			label = str(int(val))
		else:
			label = "%.2f" % val
		draw_string(ThemeDB.fallback_font, Vector2(plot.position.x + 2, y + 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.55))
	# Draw secondary data (max) as a faint line.
	if secondary_data.size() >= 2:
		var pts2 := PackedVector2Array()
		for i in range(secondary_data.size()):
			var x: float = plot.position.x + plot.size.x * float(i) / float(maxi(1, secondary_data.size() - 1))
			var y: float = plot.position.y + plot.size.y * (1.0 - (float(secondary_data[i]) - min_val) / (max_val - min_val))
			pts2.append(Vector2(x, y))
		draw_polyline(pts2, Color(0.5, 0.5, 0.5, 0.5), 1.0)
	# Draw primary data as a polyline.
	var pts := PackedVector2Array()
	for i in range(data.size()):
		var x: float = plot.position.x + plot.size.x * float(i) / float(maxi(1, data.size() - 1))
		var y: float = plot.position.y + plot.size.y * (1.0 - (float(data[i]) - min_val) / (max_val - min_val))
		pts.append(Vector2(x, y))
	draw_polyline(pts, color, 2.0)
	# Draw points.
	for p in pts:
		draw_circle(p, 1.5, color)
	# X-axis label (last generation).
	var last_gen: int = tracker.generations[tracker.generations.size() - 1] if tracker.generations.size() > 0 else 0
	draw_string(ThemeDB.fallback_font, Vector2(plot.position.x + plot.size.x - 24, plot.position.y + plot.size.y + 4), "g%d" % last_gen, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.55))
