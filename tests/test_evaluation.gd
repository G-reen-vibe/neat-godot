extends Node
## Test evaluation strategies.
## Run with: godot --headless --path . res://tests/test_evaluation.tscn

var tracker: InnovationTracker
var rng: RandomNumberGenerator
var ctx: MutationContext
var similarity: SimilarityTest

func _ready() -> void:
	print("=== test_evaluation ===")
	tracker = InnovationTracker.new()
	for i in range(4):
		tracker.reserve_node_id(i)
	rng = RandomNumberGenerator.new()
	rng.seed = 1
	ctx = MutationContext.new(rng, tracker, null)
	similarity = SimilarityTest.Standard.new()

	_test_equal()
	_test_improvement_rate()
	_test_novelty()

	print("\n=== test_evaluation: ALL PASSED ===")
	get_tree().quit()

func _test_equal() -> void:
	var species_list: Array = []
	for i in range(3):
		var sp := Species.new(i)
		# Add some members with fitnesses.
		for j in range(5):
			var g := _build_starter_genome()
			g.fitness = float(j) * 0.1
			sp.add_member(g)
		sp.record_generation_stats()
		species_list.append(sp)
	var ev := EvaluationStrategy.Equal.new()
	ev.evaluate(species_list, 30, ctx)
	var total: int = 0
	for sp: Species in species_list:
		total += sp.allocated_children
		assert(sp.allocated_children > 0, "Equal should give every species > 0 children")
		assert(sp.mutation_rate_multiplier == 1.0, "Equal should not change mutation rate")
	assert(total == 30, "Total allocated children should be 30, got %d" % total)
	print("  equal: OK (total=%d)" % total)

func _test_improvement_rate() -> void:
	var species_list: Array = []
	for i in range(2):
		var sp := Species.new(i)
		for j in range(5):
			var g := _build_starter_genome()
			g.fitness = float(j) * 0.1 + (0.5 if i == 0 else 0.0)
			sp.add_member(g)
		sp.record_generation_stats()
		species_list.append(sp)
	# First generation: no improvement data. Should still allocate children.
	var ev := EvaluationStrategy.ImprovementRate.new()
	ev.evaluate(species_list, 20, ctx)
	var total: int = 0
	for sp: Species in species_list:
		total += sp.allocated_children
		assert(sp.allocated_children > 0, "ImprovementRate should give every species > 0 children")
	assert(total == 20, "Total should be 20, got %d" % total)
	print("  improvement_rate: OK (total=%d)" % total)

func _test_novelty() -> void:
	var species_list: Array = []
	# Two species with very different representatives.
	var sp1 := Species.new(0)
	var g1 := _build_starter_genome()
	sp1.representative = g1
	for j in range(3):
		var g := _build_starter_genome()
		g.fitness = 1.0
		sp1.add_member(g)
	sp1.record_generation_stats()
	species_list.append(sp1)
	var sp2 := Species.new(1)
	var g2 := _build_starter_genome()
	# Add many extras to make it novel.
	for _i in range(10):
		var extra := tracker.new_node_id()
		g2.add_node(NodeGene.new(extra, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
		var innov := tracker.get_connection_innov(0, extra)
		g2.add_connection(ConnectionGene.new(innov, 0, extra, 0.5))
	sp2.representative = g2
	for j in range(3):
		var g := _build_starter_genome()
		g.fitness = 1.0
		sp2.add_member(g)
	sp2.record_generation_stats()
	species_list.append(sp2)
	var ev := EvaluationStrategy.Novelty.new(similarity, 1.0)
	ev.evaluate(species_list, 20, ctx)
	var total: int = 0
	for sp: Species in species_list:
		total += sp.allocated_children
	assert(total == 20, "Total should be 20, got %d" % total)
	# Novel species (sp2) should get more children than non-novel (sp1).
	assert(sp2.allocated_children >= sp1.allocated_children, "Novelty should favor the more novel species")
	print("  novelty: OK (sp1=%d, sp2=%d)" % [sp1.allocated_children, sp2.allocated_children])

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
