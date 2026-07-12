extends Node
## Test crossover: neuron-level and overall strategies.
## Run with: godot --headless --path . res://tests/test_crossover.tscn

var tracker: InnovationTracker
var rng: RandomNumberGenerator
var ctx: MutationContext

func _ready() -> void:
	print("=== test_crossover ===")
	tracker = InnovationTracker.new()
	for i in range(4):
		tracker.reserve_node_id(i)
	rng = RandomNumberGenerator.new()
	rng.seed = 7
	ctx = MutationContext.new(rng, tracker, null)
	ctx.forward_mode = "topological"
	ctx.forbid_loops = true

	_test_standard()
	_test_average()
	_test_biased_average()
	_test_standard_all()
	_test_fitter()
	_test_bigger()
	_test_combine()
	_test_excluded()
	_test_loop_handling()

	print("\n=== test_crossover: ALL PASSED ===")
	get_tree().quit()

func _test_standard() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	# Tweak weights so we can verify random pick.
	for c: ConnectionGene in b.connections.values():
		c.weight = 9.9
	a.fitness = 1.0
	b.fitness = 0.5
	var nc := NeuronCrossover.Standard.new()
	var oc := OverallCrossover.Fitter.new(nc)
	var child := oc.crossover(a, b, ctx)
	# Child should have same topology as a (3 conns).
	assert(child.connection_count() == 3, "Standard crossover should keep topology")
	# Each weight should be either from a or from b (9.9).
	for c: ConnectionGene in child.connections.values():
		assert(c.weight == 0.5 or c.weight == 9.9 or c.weight == -0.5 or c.weight == 0.3, "Standard should pick a or b weight: got %f" % c.weight)
	print("  standard: OK")

func _test_average() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	for c: ConnectionGene in b.connections.values():
		c.weight = 9.9
	a.fitness = 1.0
	b.fitness = 0.5
	var nc := NeuronCrossover.Average.new()
	var oc := OverallCrossover.Fitter.new(nc)
	var child := oc.crossover(a, b, ctx)
	# Each shared weight should be the average.
	# a's weights: 0.5, -0.5, 0.3. b's weights all 9.9.
	# Expected averages: (0.5+9.9)/2=5.2, (-0.5+9.9)/2=4.7, (0.3+9.9)/2=5.1
	var expected: Array[float] = [5.2, 4.7, 5.1]
	var actual: Array[float] = []
	for c: ConnectionGene in child.connections.values():
		actual.append(c.weight)
	actual.sort()
	expected.sort()
	for i in range(3):
		assert(absf(actual[i] - expected[i]) < 1e-3, "Average mismatch: got %f expected %f" % [actual[i], expected[i]])
	print("  average: OK")

func _test_biased_average() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	for c: ConnectionGene in b.connections.values():
		c.weight = 9.9
	a.fitness = 2.0  # fitter
	b.fitness = 0.0
	var nc := NeuronCrossover.BiasedAverage.new(1.0)  # full bias
	var oc := OverallCrossover.Fitter.new(nc)
	var child := oc.crossover(a, b, ctx)
	# With full bias toward fitter (a), each weight should be closer to a's.
	for c: ConnectionGene in child.connections.values():
		var w_a: float = 0.0
		var w_b: float = 9.9
		# Find a's weight for this innov.
		for ca: ConnectionGene in a.connections.values():
			if ca.innovation == c.innovation:
				w_a = ca.weight
		# Child should be biased toward w_a (i.e., closer to w_a than to w_b).
		var dist_a := absf(c.weight - w_a)
		var dist_b := absf(c.weight - w_b)
		assert(dist_a < dist_b or absf(dist_a - dist_b) < 1e-3, "Biased average should lean toward fitter parent")
	print("  biased_average: OK")

func _test_standard_all() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	for c: ConnectionGene in b.connections.values():
		c.weight = 9.9
	a.fitness = 1.0
	b.fitness = 0.5
	var nc := NeuronCrossover.StandardAll.new()
	var oc := OverallCrossover.Fitter.new(nc)
	var child := oc.crossover(a, b, ctx)
	# Each weight should be either from a or b.
	for c: ConnectionGene in child.connections.values():
		assert(c.weight == 0.5 or c.weight == 9.9 or c.weight == -0.5 or c.weight == 0.3, "StandardAll should pick a or b weight")
	print("  standard_all: OK")

func _test_fitter() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	# Add extra connection to b (disjoint in b).
	var extra_id := tracker.new_node_id()
	b.add_node(NodeGene.new(extra_id, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov_extra := tracker.get_connection_innov(0, extra_id)
	b.add_connection(ConnectionGene.new(innov_extra, 0, extra_id, 0.4))
	a.fitness = 2.0  # fitter
	b.fitness = 1.0
	var nc := NeuronCrossover.Standard.new()
	var oc := OverallCrossover.Fitter.new(nc)
	var child := oc.crossover(a, b, ctx)
	# Fitter strategy: only inherit disjoints from a (the fitter). b's disjoint should NOT appear.
	assert(not child.connections.has(innov_extra), "Fitter strategy should not inherit disjoints from less-fit parent")
	print("  fitter: OK")

func _test_bigger() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	# Add extra connections to b (so b is bigger).
	var extra_id := tracker.new_node_id()
	b.add_node(NodeGene.new(extra_id, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov_extra := tracker.get_connection_innov(0, extra_id)
	b.add_connection(ConnectionGene.new(innov_extra, 0, extra_id, 0.4))
	var innov_extra2 := tracker.get_connection_innov(extra_id, 3)
	b.add_connection(ConnectionGene.new(innov_extra2, extra_id, 3, 0.6))
	a.fitness = 2.0
	b.fitness = 1.0
	var nc := NeuronCrossover.Standard.new()
	var oc := OverallCrossover.Bigger.new(nc)
	var child := oc.crossover(a, b, ctx)
	# Bigger strategy: inherit disjoints from b (the bigger).
	assert(child.connections.has(innov_extra), "Bigger strategy should inherit disjoints from bigger parent")
	assert(child.connections.has(innov_extra2), "Bigger strategy should inherit disjoints from bigger parent")
	print("  bigger: OK")

func _test_combine() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	# Add a disjoint to each parent.
	var extra_a := tracker.new_node_id()
	a.add_node(NodeGene.new(extra_a, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov_a := tracker.get_connection_innov(0, extra_a)
	a.add_connection(ConnectionGene.new(innov_a, 0, extra_a, 0.4))
	var innov_a2 := tracker.get_connection_innov(extra_a, 3)
	a.add_connection(ConnectionGene.new(innov_a2, extra_a, 3, 0.6))
	var extra_b := tracker.new_node_id()
	b.add_node(NodeGene.new(extra_b, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov_b := tracker.get_connection_innov(1, extra_b)
	b.add_connection(ConnectionGene.new(innov_b, 1, extra_b, 0.5))
	var innov_b2 := tracker.get_connection_innov(extra_b, 3)
	b.add_connection(ConnectionGene.new(innov_b2, extra_b, 3, 0.7))
	a.fitness = 2.0  # fitter
	b.fitness = 1.0
	var nc := NeuronCrossover.Standard.new()
	var oc := OverallCrossover.Combine.new(nc)
	var child := oc.crossover(a, b, ctx)
	# Combine should inherit disjoints from both.
	assert(child.connections.has(innov_a), "Combine should inherit a's disjoints")
	assert(child.connections.has(innov_b), "Combine should inherit b's disjoints")
	assert(not child.has_loop(), "Combine should not create loops")
	print("  combine: OK")

func _test_excluded() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	# Add disjoints to both parents.
	var extra_a := tracker.new_node_id()
	a.add_node(NodeGene.new(extra_a, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov_a := tracker.get_connection_innov(0, extra_a)
	a.add_connection(ConnectionGene.new(innov_a, 0, extra_a, 0.4))
	var innov_a2 := tracker.get_connection_innov(extra_a, 3)
	a.add_connection(ConnectionGene.new(innov_a2, extra_a, 3, 0.6))
	var extra_b := tracker.new_node_id()
	b.add_node(NodeGene.new(extra_b, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov_b := tracker.get_connection_innov(1, extra_b)
	b.add_connection(ConnectionGene.new(innov_b, 1, extra_b, 0.5))
	a.fitness = 2.0  # fitter
	b.fitness = 1.0
	var nc := NeuronCrossover.Standard.new()
	var oc := OverallCrossover.Excluded.new(nc)
	var child := oc.crossover(a, b, ctx)
	# Excluded: shared connections kept. Disjoints from less-fit (b) NOT inherited.
	# Disjoints from more-fit (a) added only if needed for connectivity.
	# In this case, output 3 is already reachable via shared (0->3, 1->3, 2->3),
	# so no disjoints should be needed.
	assert(child.connections.has(tracker.get_connection_innov(0, 3)), "Shared connections should be kept")
	assert(not child.connections.has(innov_b), "Excluded should not inherit less-fit disjoints when not needed")
	print("  excluded: OK")

func _test_loop_handling() -> void:
	# Construct two parents whose disjoints would create a loop if all inherited.
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	a.fitness = 2.0
	b.fitness = 1.0
	# Add (3 -> 0) to b: this would create a loop with the existing (0 -> 3) in shared.
	var innov_loop := tracker.get_connection_innov(3, 0)
	b.add_connection(ConnectionGene.new(innov_loop, 3, 0, 0.5))
	var nc := NeuronCrossover.Standard.new()
	var oc := OverallCrossover.Combine.new(nc)
	var child := oc.crossover(a, b, ctx)
	# The loop-creating disjoint should be dropped.
	assert(not child.connections.has(innov_loop), "Combine should drop disjoints that create loops")
	assert(not child.has_loop(), "Child should be acyclic")
	print("  loop_handling: OK")

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
