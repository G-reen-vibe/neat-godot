## Visualizes a Genome's network as a directed graph. Nodes are positioned by
## a simple layered layout (inputs/bias left, outputs right, hidden in middle
## by topological depth). Connections are drawn as arrows colored by sign.
extends Control
class_name GraphView

const NODE_RADIUS: float = 14.0

var genome: Genome = null:
	set(g):
		genome = g
		_rebuild_layout = true

var _positions: Dictionary = {}  # node_id -> Vector2
var _rebuild_layout: bool = true

@onready var _draw_layer: Control = $DrawLayer

func _ready() -> void:
	_draw_layer.draw.connect(_on_draw)

func _process(_delta: float) -> void:
	if genome == null:
		return
	if _rebuild_layout:
		_init_layout()
		_rebuild_layout = false
	_draw_layer.queue_redraw()

func _init_layout() -> void:
	_positions.clear()
	if genome == null:
		return
	var size := get_size()
	if size.x < 1 or size.y < 1:
		size = custom_minimum_size
	if genome.compute_topological_order():
		pass
	var inputs: Array = genome.input_nodes()
	var biases: Array = genome.bias_nodes()
	var outputs: Array = genome.output_nodes()
	var hidden: Array = genome.hidden_nodes()
	var left_nodes := inputs + biases
	# Layer inputs/bias on the left.
	for i in range(left_nodes.size()):
		var n: NodeGene = left_nodes[i]
		var y: float = (float(i) + 0.5) / float(maxi(1, left_nodes.size())) * size.y
		_positions[n.id] = Vector2(0.12 * size.x, y)
	# Layer outputs on the right.
	for i in range(outputs.size()):
		var n: NodeGene = outputs[i]
		var y: float = (float(i) + 0.5) / float(maxi(1, outputs.size())) * size.y
		_positions[n.id] = Vector2(0.88 * size.x, y)
	# Layer hidden by topological depth in the middle.
	var max_depth: int = 0
	for n: NodeGene in hidden:
		if n.depth > max_depth:
			max_depth = n.depth
	var by_depth: Dictionary = {}
	for n: NodeGene in hidden:
		if not by_depth.has(n.depth):
			by_depth[n.depth] = []
		by_depth[n.depth].append(n)
	for depth: int in by_depth:
		var group: Array = by_depth[depth]
		var x_frac: float = 0.3 + (0.5 * (float(depth) + 0.5) / float(maxi(1, max_depth + 1)))
		for i in range(group.size()):
			var n: NodeGene = group[i]
			var y: float = (float(i) + 0.5) / float(maxi(1, group.size())) * size.y
			_positions[n.id] = Vector2(x_frac * size.x, y)

func _on_draw() -> void:
	if genome == null:
		return
	# Connections.
	for c: ConnectionGene in genome.connections.values():
		if not _positions.has(c.from_node) or not _positions.has(c.to_node):
			continue
		var pa: Vector2 = _positions[c.from_node]
		var pb: Vector2 = _positions[c.to_node]
		var color: Color
		if not c.enabled:
			color = Color(0.4, 0.4, 0.4, 0.3)
		elif c.weight >= 0:
			color = Color(0.2, 0.8, 1.0, clampf(absf(c.weight) / 3.0, 0.3, 1.0))
		else:
			color = Color(1.0, 0.4, 0.3, clampf(absf(c.weight) / 3.0, 0.3, 1.0))
		_draw_layer.draw_line(pa, pb, color, 2.0)
		_draw_arrowhead(pa, pb, color)
	# Nodes.
	for n: NodeGene in genome.nodes.values():
		if not _positions.has(n.id):
			continue
		var p: Vector2 = _positions[n.id]
		var fill: Color
		match n.kind:
			NodeGene.Kind.INPUT:
				fill = Color(0.3, 0.7, 0.3)
			NodeGene.Kind.BIAS:
				fill = Color(0.5, 0.5, 0.5)
			NodeGene.Kind.OUTPUT:
				fill = Color(0.7, 0.3, 0.7)
			_:
				fill = Color(0.3, 0.5, 0.8)
		_draw_layer.draw_circle(p, NODE_RADIUS, fill)
		_draw_layer.draw_circle(p, NODE_RADIUS, Color(1, 1, 1, 0.8), false, 1.5)
		_draw_layer.draw_string(ThemeDB.fallback_font, p + Vector2(-6, 4),
				str(n.id % 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1))

func _draw_arrowhead(from: Vector2, to: Vector2, color: Color) -> void:
	var dir := (to - from).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var tip := to - dir * NODE_RADIUS
	var base := tip - dir * 8.0
	var p1 := base + perp * 4.0
	var p2 := base - perp * 4.0
	_draw_layer.draw_polygon(PackedVector2Array([tip, p1, p2]), PackedColorArray([color, color, color]))
