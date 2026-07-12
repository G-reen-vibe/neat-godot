extends Node
## Test similarity tests: Standard (NEAT paper) and Percentage.
## Run with: godot --headless --path . res://tests/test_similarity.tscn

var tracker: InnovationTracker

func _ready() -> void:
	print("=== test_similarity ===")
	tracker = InnovationTracker.new()
	for i in range(4):
		tracker.reserve_node_id(i)

	_test_identical()
	_test_disjoint()
	_test_excess()
	_test_weight_diff()
	_test_percentage_zero_when_identical()
	_test_percentage_handles_missing()

	print("\n=== test_similarity: ALL PASSED ===")
	get_tree().quit()

func _test_identical() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	var std := SimilarityTest.Standard.new()
	var d := std.distance(a, b)
	assert(d < 1e-6, "Identical genomes should have 0 standard distance, got %f" % d)
	print("  standard identical: OK (d=%.4f)" % d)

func _test_disjoint() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	# Add a disjoint to b.
	var extra := tracker.new_node_id()
	b.add_node(NodeGene.new(extra, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov := tracker.get_connection_innov(0, extra)
	b.add_connection(ConnectionGene.new(innov, 0, extra, 0.5))
	var std := SimilarityTest.Standard.new()
	var d := std.distance(a, b)
	# 1 disjoint gene, N=1 (small genome), so d = c1*0 + c2*1 = 1.0
	assert(absf(d - 1.0) < 0.01, "1 disjoint small genome -> d≈1.0, got %f" % d)
	print("  standard disjoint: OK (d=%.4f)" % d)

func _test_excess() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	# Add an excess innovation to b (higher than any in a).
	var extra := tracker.new_node_id()
	b.add_node(NodeGene.new(extra, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	# Get a high innovation number.
	var innov := tracker.get_connection_innov(extra, 3)
	b.add_connection(ConnectionGene.new(innov, extra, 3, 0.5))
	var std := SimilarityTest.Standard.new()
	var d := std.distance(a, b)
	# 1 excess gene, N=1, so d ≈ 1.0
	assert(absf(d - 1.0) < 0.01, "1 excess small genome -> d≈1.0, got %f" % d)
	print("  standard excess: OK (d=%.4f)" % d)

func _test_weight_diff() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	# Modify weights in b.
	for c: ConnectionGene in b.connections.values():
		c.weight += 1.0  # +1 difference per shared connection
	var std := SimilarityTest.Standard.new()
	var d := std.distance(a, b)
	# All shared (3 conns), avg weight diff = 1.0, c3=0.4 -> 0.4 contribution.
	assert(absf(d - 0.4) < 0.01, "Pure weight diff -> d≈0.4, got %f" % d)
	print("  standard weight_diff: OK (d=%.4f)" % d)

func _test_percentage_zero_when_identical() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	var pct := SimilarityTest.Percentage.new()
	var d := pct.distance(a, b)
	assert(d < 1e-6, "Identical genomes -> 0%% distance, got %f" % d)
	print("  percentage identical: OK (d=%.4f)" % d)

func _test_percentage_handles_missing() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	# Add a disjoint to b with weight 1.0.
	var extra := tracker.new_node_id()
	b.add_node(NodeGene.new(extra, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov := tracker.get_connection_innov(0, extra)
	b.add_connection(ConnectionGene.new(innov, 0, extra, 1.0))
	var pct := SimilarityTest.Percentage.new()
	var d := pct.distance(a, b)
	# diff = |1.0 - 0| = 1.0 (the disjoint contributes).
	# total = |1.0| (only b's disjoint, since a's shared connections have weights
	#         that should match b's shared connections exactly).
	# Wait: a's shared connections also contribute to total.
	# a's weights: 0.5, -0.5, 0.3. b's weights (shared): 0.5, -0.5, 0.3. So shared contribute 0 to diff but 3.6 to total.
	# b's disjoint: w=1.0. contributes 1.0 to diff and 1.0 to total.
	# diff = 0 (shared) + 1.0 (disjoint) = 1.0
	# total = (|0.5|+|0.5|) + (|-0.5|+|-0.5|) + (|0.3|+|0.3|) + (|0|+|1.0|) = 1.0+1.0+0.6+1.0 = 3.6
	# pct = 1.0 / 3.6 ≈ 0.278
	print("  percentage missing: d=%.4f (expected ~0.278)" % d)
	assert(d > 0.0 and d < 1.0, "Percentage should be in (0, 1) when partially similar")

func _build_starter_genome() -> Genome:
	var g := Genome.new()
	g.add_node(NodeGene.new(0, NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR))
	g.add_node(NodeGene.new(1, NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR))
	g.add_node(NodeGene.new(2, NodeGene.Kind.BIAS, ActivationFunctions.Func.LINEAR))
	g.add_node(NodeGene.new(3, NodeGene.Kind.OUTPUT, ActivationFunctions.Func.TANH))
	g.add_connection(ConnectionGene.new(tracker.get_connection_innov(0, 3), 0, 3, 0.5))
	g.add_connection(ConnectionGene.new(tracker.get_connection_innov(1, 3), 1, 3, -0.5))
	g.add_connection(ConnectionGene.new(tracker.get_connection_innov(2, 3), 2, 3, 0.3))
	return g
