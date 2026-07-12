extends VBoxContainer
class_name XorTruthTable

var genome: Genome = null:
	set(g):
		genome = g
		_refresh()

@onready var _grid: GridContainer = $Grid

const INPUTS: Array = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]
const TARGETS: Array = [0.0, 1.0, 1.0, 0.0]

func _ready() -> void:
	# Add 4 rows for the truth table (header is already in scene).
	for i in range(4):
		var a_label := Label.new()
		a_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		a_label.add_theme_font_size_override("font_size", 14)
		a_label.text = str(int(INPUTS[i][0]))
		_grid.add_child(a_label)
		var b_label := Label.new()
		b_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b_label.add_theme_font_size_override("font_size", 14)
		b_label.text = str(int(INPUTS[i][1]))
		_grid.add_child(b_label)
		var exp_label := Label.new()
		exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		exp_label.add_theme_font_size_override("font_size", 14)
		exp_label.text = str(int(TARGETS[i]))
		_grid.add_child(exp_label)
		var act_label := Label.new()
		act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		act_label.add_theme_font_size_override("font_size", 14)
		act_label.text = "-"
		_grid.add_child(act_label)

func _refresh() -> void:
	if genome == null:
		return
	# Grid has 4 header labels + 4 rows * 4 labels = 20 children.
	# Each row's "actual" label is the 4th child of each row.
	# Header (children 0-3) + row 0 (children 4-7) + row 1 (children 8-11) + ...
	for i in range(4):
		var input_id_0: int = 0
		var input_id_1: int = 1
		var state: Dictionary = {input_id_0: INPUTS[i][0], input_id_1: INPUTS[i][1]}
		var out: Dictionary = genome.forward(state, "topological")
		# Output node id is 3 (per env factory: inputs 0,1, bias 2, output 3).
		var actual: float = float(out.get(3, 0.0))
		var act_label: Label = _grid.get_child(4 + i * 4 + 3)
		act_label.text = "%.3f" % actual
		# Color: green if close to target, red if far.
		var diff: float = absf(actual - TARGETS[i])
		if diff < 0.1:
			act_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		elif diff < 0.3:
			act_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		else:
			act_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
