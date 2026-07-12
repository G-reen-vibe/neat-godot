extends Node
## Test mutation system: weight, connection, neuron, prune, enable operators.
## Run with: godot --headless --path . res://tests/test_mutation.tscn

var tracker: InnovationTracker
var rng: RandomNumberGenerator
var species: Species
var ctx: MutationContext

func _ready() -> void:
	print("=== test_mutation: selectors + mutators + policies ===")
	tracker = InnovationTracker.new()
	for i in range(4):
		tracker.reserve_node_id(i)
	rng = RandomNumberGenerator.new()
	rng.seed = 42
	species = Species.new(0)
	ctx = MutationContext.new(rng, tracker, species)
	ctx.forward_mode = "topological"
	ctx.forbid_loops = true

	_test_weight_mutation()
	_test_connection_mutation()
	_test_neuron_mutation()
	_test_enable_mutation()
	_test_prune_mutation()
	_test_capped_selector()
	_test_least_used_selector()
	_test_least_common_selector()
	_test_phased_pruning()
	_test_round_trip_forward()

	print("\n=== test_mutation: ALL PASSED ===")
	get_tree().quit()

func _test_weight_mutation() -> void:
	var g := _build_starter_genome()
	var ws := WeightSelector.Standard.new(1, 1.0)
	var wm := WeightMutator.Standard.new(-0.5, 0.5)
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.weight_selector = ws
	pol.weight_mutator = wm
	var before: Array[float] = []
	for c: ConnectionGene in g.connections.values():
		before.append(c.weight)
	pol.apply(g, ctx)
	var any_changed := false
	var i := 0
	for c: ConnectionGene in g.connections.values():
		if absf(c.weight - before[i]) > 1e-6:
			any_changed = true
		i += 1
	assert(any_changed, "Weight mutation should change at least one weight")
	print("  weight: OK")

func _test_connection_mutation() -> void:
	# Need hidden nodes to allow new connections; do neuron mutation first.
	var g := _build_starter_genome()
	var nm := NeuronMutator.Standard.new(ActivationFunctions.Func.RELU)
	var ns_sel := NeuronSelector.Standard.new(1, 1.0)
	var pol_n := MutationPolicy.General.new(true, 1.0)
	pol_n.neuron_selector = ns_sel
	pol_n.neuron_mutator = nm
	pol_n.apply(g, ctx)
	var conns_before := g.connection_count()
	# Now connection mutation has opportunities.
	var cs := ConnectionSelector.Standard.new(1, 1.0)
	var cm := ConnectionMutator.Standard.new(-1.0, 1.0)
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.connection_selector = cs
	pol.connection_mutator = cm
	pol.apply(g, ctx)
	var conns_after := g.connection_count()
	assert(conns_after > conns_before, "Connection mutation should add connections when opportunities exist")
	assert(not g.has_loop(), "Should remain loop-free")
	print("  connection: OK (conns %d -> %d)" % [conns_before, conns_after])

func _test_neuron_mutation() -> void:
	var g := _build_starter_genome()
	var ns := NeuronSelector.Standard.new(1, 1.0)
	var nm := NeuronMutator.Standard.new(ActivationFunctions.Func.RELU)
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.neuron_selector = ns
	pol.neuron_mutator = nm
	var nodes_before := g.node_count()
	pol.apply(g, ctx)
	var nodes_after := g.node_count()
	assert(nodes_after > nodes_before, "Neuron mutation should add nodes")
	assert(not g.has_loop(), "Should remain loop-free")
	print("  neuron: OK (nodes %d -> %d)" % [nodes_before, nodes_after])

func _test_enable_mutation() -> void:
	var g := _build_starter_genome()
	# Disable all connections first.
	for c: ConnectionGene in g.connections.values():
		c.enabled = false
	g.mark_dirty()
	assert(g.enabled_connections().size() == 0, "All disabled")
	var es := EnableSelector.Standard.new(0, 1.0)
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.enable_selector = es
	pol.apply(g, ctx)
	assert(g.enabled_connections().size() > 0, "Enable should re-enable connections")
	print("  enable: OK")

func _test_prune_mutation() -> void:
	var g := _build_starter_genome()
	# Add some extra connections to prune.
	var nm := NeuronMutator.Standard.new(ActivationFunctions.Func.RELU)
	var ns_sel := NeuronSelector.Standard.new(1, 1.0)
	var pol_n := MutationPolicy.General.new(true, 1.0)
	pol_n.neuron_selector = ns_sel
	pol_n.neuron_mutator = nm
	pol_n.apply(g, ctx)
	var before := g.connection_count()
	var ps := PruneSelector.Standard.new(1, 0.5)
	var pm := PruneMutator.new()
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.prune_selector = ps
	pol.prune_mutator = pm
	pol.apply(g, ctx)
	var after := g.connection_count()
	assert(after < before, "Prune should remove connections")
	print("  prune: OK (conns %d -> %d)" % [before, after])

func _test_capped_selector() -> void:
	var g := _build_starter_genome()
	for c: ConnectionGene in g.connections.values():
		c.weight = 3.0
	var capped := WeightSelector.Capped.new(1, 0.5, -3.0, 3.0)
	var out: Array = capped.select(g, ctx)
	assert(not out.is_empty(), "Capped selector should return items")
	for c: ConnectionGene in out:
		assert(absf(c.weight - 3.0) < 1e-4, "Capped should bias to pinned connections")
	print("  capped selector: OK")

func _test_least_used_selector() -> void:
	var g := _build_starter_genome()
	# Make input 0 high-degree by adding many hidden children.
	for _i in range(10):
		var extra_id := tracker.new_node_id()
		g.add_node(NodeGene.new(extra_id, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
		var innov := tracker.get_connection_innov(0, extra_id)
		g.add_connection(ConnectionGene.new(innov, 0, extra_id, 0.1))
	var lu := ConnectionSelector.LeastUsed.new(1, 1.0)
	var out: Array = lu.select(g, ctx)
	assert(not out.is_empty(), "LeastUsed should return candidates")
	print("  least_used: OK (%d candidates)" % out.size())

func _test_least_common_selector() -> void:
	var g := _build_starter_genome()
	var nm := NeuronMutator.Standard.new(ActivationFunctions.Func.RELU)
	var ns_sel := NeuronSelector.Standard.new(1, 1.0)
	var pol_n := MutationPolicy.General.new(true, 1.0)
	pol_n.neuron_selector = ns_sel
	pol_n.neuron_mutator = nm
	pol_n.apply(g, ctx)
	var lc := ConnectionSelector.LeastCommon.new(1, 1.0)
	var out: Array = lc.select(g, ctx)
	assert(not out.is_empty(), "LeastCommon should return candidates")
	print("  least_common: OK (%d candidates)" % out.size())

func _test_phased_pruning() -> void:
	var g := _build_starter_genome()
	var nm := NeuronMutator.Standard.new(ActivationFunctions.Func.RELU)
	var ns_sel := NeuronSelector.Standard.new(1, 1.0)
	var pol_n := MutationPolicy.General.new(true, 1.0)
	pol_n.neuron_selector = ns_sel
	pol_n.neuron_mutator = nm
	pol_n.apply(g, ctx)
	var phased := MutationPolicy.PhasedPruning.new(2, 5.0)
	phased.weight_selector = WeightSelector.Standard.new(1, 1.0)
	phased.weight_mutator = WeightMutator.Standard.new(-0.5, 0.5)
	phased.prune_selector = PruneSelector.Standard.new(1, 1.0)
	phased.prune_mutator = PruneMutator.new()
	# Generation 0 -> growth phase: weights mutate, no prune.
	var weights_before: Array[float] = []
	for c: ConnectionGene in g.connections.values():
		weights_before.append(c.weight)
	phased.apply(g, ctx)
	var weights_changed := false
	var i := 0
	for c: ConnectionGene in g.connections.values():
		if absf(c.weight - weights_before[i]) > 1e-6:
			weights_changed = true
		i += 1
	assert(weights_changed, "Growth phase should mutate weights")
	# Advance to pruning phase.
	phased.advance_generation()
	phased.advance_generation()
	var conns_before := g.connection_count()
	phased.apply(g, ctx)
	var conns_after := g.connection_count()
	assert(conns_after < conns_before, "Pruning phase should remove connections")
	print("  phased_pruning: OK (prune %d -> %d)" % [conns_before, conns_after])

func _test_round_trip_forward() -> void:
	var g := _build_starter_genome()
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.weight_selector = WeightSelector.Standard.new(1, 1.0)
	pol.weight_mutator = WeightMutator.Standard.new(-0.5, 0.5)
	pol.connection_selector = ConnectionSelector.Standard.new(1, 0.5)
	pol.connection_mutator = ConnectionMutator.Standard.new(-1.0, 1.0)
	pol.neuron_selector = NeuronSelector.Standard.new(1, 0.5)
	pol.neuron_mutator = NeuronMutator.Standard.new(ActivationFunctions.Func.RELU)
	pol.enable_selector = EnableSelector.Standard.new(0, 0.5)
	for _i in range(5):
		pol.apply(g, ctx)
	var out := g.forward({0: 1.0, 1: 0.5}, "topological")
	assert(out.size() == 1, "Should have 1 output")
	assert(not g.has_loop(), "Should remain loop-free")
	print("  round-trip forward: OK (out=%s)" % [out])

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
