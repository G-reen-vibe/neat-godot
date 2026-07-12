class_name XorTruthTable
extends Control
## Draws a live XOR truth table showing the best genome's outputs vs targets.
## Updates whenever [member genome] is set.

var genome: Genome = null:
	set(g):
		genome = g
		queue_redraw()

const INPUTS: Array = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]
const TARGETS: Array = [0.0, 1.0, 1.0, 0.0]

func _ready() -> void:
	custom_minimum_size = Vector2(400, 300)

func _draw() -> void:
	var s := get_size()
	if s.x < 10 or s.y < 10:
		return
	# Layout
	var pad: float = 24.0
	var title_h: float = 30.0
	var footer_h: float = 30.0
	var table_x: float = pad
	var table_y: float = pad + title_h
	var table_w: float = s.x - 2.0 * pad
	var table_h: float = s.y - 2.0 * pad - title_h - footer_h
	var col_w: float = table_w / 4.0
	var header_h: float = 28.0
	var row_h: float = (table_h - header_h) / 4.0
	# Title.
	draw_string(ThemeDB.fallback_font, Vector2(table_x, pad + 20), "XOR Truth Table — Best Genome", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.9, 0.9))
	# Header background.
	draw_rect(Rect2(table_x, table_y, table_w, header_h), Color(0.2, 0.25, 0.35))
	# Headers.
	var headers: Array = ["Input 1", "Input 2", "Target", "Output"]
	for i in range(4):
		var cx: float = table_x + i * col_w + col_w * 0.5
		draw_string(ThemeDB.fallback_font, Vector2(cx - 35, table_y + 19), headers[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.8, 0.9))
	# Header separators.
	for i in range(1, 4):
		var lx: float = table_x + i * col_w
		draw_line(Vector2(lx, table_y), Vector2(lx, table_y + table_h), Color(0.3, 0.3, 0.4), 1.0)
	# Rows.
	var total_error: float = 0.0
	for row in range(4):
		var y: float = table_y + header_h + row * row_h
		var bg: Color = Color(0.12, 0.12, 0.16) if row % 2 == 0 else Color(0.16, 0.16, 0.22)
		draw_rect(Rect2(table_x, y, table_w, row_h), bg)
		var in1: float = INPUTS[row][0]
		var in2: float = INPUTS[row][1]
		var target: float = TARGETS[row]
		var output_val: float = 0.0
		if genome != null:
			var out: Dictionary = genome.forward({0: in1, 1: in2}, "topological")
			output_val = float(out.get(3, 0.0))
		var err: float = absf(output_val - target)
		total_error += err
		# Draw values.
		draw_string(ThemeDB.fallback_font, Vector2(table_x + col_w * 0.5 - 5, y + row_h * 0.65), str(int(in1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(table_x + col_w * 1.5 - 5, y + row_h * 0.65), str(int(in2)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(table_x + col_w * 2.5 - 5, y + row_h * 0.65), str(int(target)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.9, 0.7))
		var out_color: Color
		if err < 0.1:
			out_color = Color(0.3, 0.9, 0.3)
		elif err < 0.3:
			out_color = Color(0.9, 0.9, 0.3)
		else:
			out_color = Color(0.9, 0.4, 0.3)
		draw_string(ThemeDB.fallback_font, Vector2(table_x + col_w * 3.5 - 25, y + row_h * 0.65), "%.3f" % output_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, out_color)
	# Row separators.
	for row in range(1, 4):
		var ly: float = table_y + header_h + row * row_h
		draw_line(Vector2(table_x, ly), Vector2(table_x + table_w, ly), Color(0.25, 0.25, 0.3), 1.0)
	# Footer.
	var fitness: float = pow(maxf(0.0, 4.0 - total_error), 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(table_x, table_y + table_h + 22), "Total Error: %.4f  |  Fitness: %.4f / 16.0" % [total_error, fitness], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.8, 0.8))
