## Custom Control that draws a genome's network graph. Nodes are positioned by
## a simple spring-mass physics simulation: connected nodes are pulled together
## by springs, all nodes repel each other with an inverse-square force, and
## input/bias/output nodes are softly pinned to their respective columns.
class_name GraphView
extends Control

const NODE_RADIUS: float = 14.0
const SPRING_K: float = 0.02
const REPULSION_K: float = 800.0
const DAMPING: float = 0.85
const PIN_K: float = 0.1
const INPUT_X: float = 0.12
const OUTPUT_X: float = 0.88
const MAX_VELOCITY: float = 30.0

var genome: Genome = null:
	set(g):
		genome = g
		_rebuild_layout = true

var _positions: Dictionary = {}  # node_id -> Vector2
var _velocities: Dictionary = {}  # node_id -> Vector2
var _rebuild_layout: bool = true

func _ready() -> void:
	custom_minimum_size = Vector2(300, 300)

func _process(delta: float) -> void:
	if genome == null:
		return
	if _rebuild_layout:
		_init_layout()
		_rebuild_layout = false
	_step_physics(delta)
	queue_redraw()

func _init_layout() -> void:
	_positions.clear()
	_velocities.clear()
	if genome == null:
		return
	var size := get_size()
	if size.x < 1 or size.y < 1:
		size = custom_minimum_size
	# Place inputs/bias on left, outputs on right, hidden in middle.
	var inputs: Array = genome.input_nodes()
	var biases: Array = genome.bias_nodes()
	var outputs: Array = genome.output_nodes()
	var hidden: Array = genome.hidden_nodes()
	var left_nodes := inputs + biases
	for i in range(left_nodes.size()):
		var n: NodeGene = left_nodes[i]
		var y: float = (float(i) + 0.5) / float(maxi(1, left_nodes.size())) * size.y
		_positions[n.id] = Vector2(INPUT_X * size.x, y)
		_velocities[n.id] = Vector2.ZERO
	for i in range(outputs.size()):
		var n: NodeGene = outputs[i]
		var y: float = (float(i) + 0.5) / float(maxi(1, outputs.size())) * size.y
		_positions[n.id] = Vector2(OUTPUT_X * size.x, y)
		_velocities[n.id] = Vector2.ZERO
	for i in range(hidden.size()):
		var n: NodeGene = hidden[i]
		# Random initial position in the middle.
		var x: float = randf_range(0.3, 0.7) * size.x
		var y: float = randf_range(0.1, 0.9) * size.y
		_positions[n.id] = Vector2(x, y)
		_velocities[n.id] = Vector2.ZERO

func _step_physics(delta: float) -> void:
	if genome == null or _positions.is_empty():
		return
	var size := get_size()
	if size.x < 1 or size.y < 1:
		return
	# Compute forces.
	var forces: Dictionary = {}
	for nid: int in _positions:
		forces[nid] = Vector2.ZERO
	# Repulsion between all pairs.
	var ids: Array = _positions.keys()
	for i in range(ids.size()):
		var a: int = ids[i]
		var pa: Vector2 = _positions[a]
		for j in range(i + 1, ids.size()):
			var b: int = ids[j]
			var pb: Vector2 = _positions[b]
			var diff := pa - pb
			var d2: float = diff.x * diff.x + diff.y * diff.y + 1.0
			var f: float = REPULSION_K / d2
			var diff_n: Vector2 = diff / sqrt(d2)
			forces[a] += diff_n * f
			forces[b] -= diff_n * f
	# Spring forces along connections.
	for c: ConnectionGene in genome.connections.values():
		if not c.enabled:
			continue
		if not _positions.has(c.from_node) or not _positions.has(c.to_node):
			continue
		var pa: Vector2 = _positions[c.from_node]
		var pb: Vector2 = _positions[c.to_node]
		var diff := pb - pa
		var d: float = diff.length() + 0.01
		var f: float = SPRING_K * (d - 80.0)
		var diff_n: Vector2 = diff / d
		forces[c.from_node] += diff_n * f
		forces[c.to_node] -= diff_n * f
	# Pin forces (pull input/bias left, output right).
	for n: NodeGene in genome.nodes.values():
		if not _positions.has(n.id):
			continue
		var p: Vector2 = _positions[n.id]
		var target_x: float
		if n.kind == NodeGene.Kind.INPUT or n.kind == NodeGene.Kind.BIAS:
			target_x = INPUT_X * size.x
		elif n.kind == NodeGene.Kind.OUTPUT:
			target_x = OUTPUT_X * size.x
		else:
			continue
		forces[n.id].x += (target_x - p.x) * PIN_K
	# Update velocities and positions.
	for nid: int in _positions:
		var v: Vector2 = _velocities[nid]
		var f: Vector2 = forces[nid]
		v = (v + f * delta) * DAMPING
		# Clamp velocity.
		var speed: float = v.length()
		if speed > MAX_VELOCITY:
			v = v * (MAX_VELOCITY / speed)
		_velocities[nid] = v
		var p: Vector2 = _positions[nid]
		p += v * delta * 60.0  # scale up for visible motion
		# Keep inside bounds.
		p.x = clampf(p.x, NODE_RADIUS, size.x - NODE_RADIUS)
		p.y = clampf(p.y, NODE_RADIUS, size.y - NODE_RADIUS)
		_positions[nid] = p

func _draw() -> void:
	if genome == null:
		return
	var size := get_size()
	# Draw connections first (under nodes).
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
		draw_line(pa, pb, color, 2.0)
		# Draw arrowhead.
		_draw_arrowhead(pa, pb, color)
	# Draw nodes.
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
		draw_circle(p, NODE_RADIUS, fill)
		draw_circle(p, NODE_RADIUS, Color(1, 1, 1, 0.8), false, 1.5)
		# Label with last 2 digits of id.
		draw_string(ThemeDB.fallback_font, p + Vector2(-6, 4), str(n.id % 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1))

func _draw_arrowhead(from: Vector2, to: Vector2, color: Color) -> void:
	var dir := (to - from).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var tip := to - dir * NODE_RADIUS
	var base := tip - dir * 8.0
	var p1 := base + perp * 4.0
	var p2 := base - perp * 4.0
	draw_polygon(PackedVector2Array([tip, p1, p2]), PackedColorArray([color, color, color]))
