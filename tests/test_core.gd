extends Node
## Smoke test for the core data structures.
## Run with: godot --headless --path . res://tests/test_core.tscn

func _ready() -> void:
	print("=== test_core: smoke test for NodeGene / ConnectionGene / InnovationTracker / Genome ===")

	var tracker := InnovationTracker.new()
	tracker.reserve_node_id(0)
	tracker.reserve_node_id(1)
	tracker.reserve_node_id(2)
	tracker.reserve_node_id(3)
	# ids: 0,1 inputs; 2 bias; 3 output.

	var g := Genome.new()
	var n0 := NodeGene.new(0, NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR)
	var n1 := NodeGene.new(1, NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR)
	var n2 := NodeGene.new(2, NodeGene.Kind.BIAS, ActivationFunctions.Func.LINEAR)
	var n3 := NodeGene.new(3, NodeGene.Kind.OUTPUT, ActivationFunctions.Func.TANH)
	g.add_node(n0)
	g.add_node(n1)
	g.add_node(n2)
	g.add_node(n3)

	# Initial fully-connected input/output topology (3 inputs+bias -> 1 output).
	var innov0 := tracker.get_connection_innov(0, 3)
	var innov1 := tracker.get_connection_innov(1, 3)
	var innov2 := tracker.get_connection_innov(2, 3)
	g.add_connection(ConnectionGene.new(innov0, 0, 3, 0.5))
	g.add_connection(ConnectionGene.new(innov1, 1, 3, -0.5))
	g.add_connection(ConnectionGene.new(innov2, 2, 3, 0.3))

	print("Initial genome: ", g)
	print("Topological order computed: ", g.compute_topological_order())
	print("Has loop? ", g.has_loop())
	print("Topo order: ", g._topo_order)

	# Forward pass: topological mode.
	var out_topo := g.forward({0: 1.0, 1: 0.0}, "topological")
	print("Topological forward {0:1, 1:0} -> out = ", out_topo)

	# Forward pass: timestep mode.
	var out_ts := g.forward({0: 1.0, 1: 0.0}, "timestep", 5)
	print("Timestep forward {0:1, 1:0} -> out = ", out_ts)

	# Should match (no recurrent connections in this simple graph).
	var diff: float = absf(float(out_topo[3]) - float(out_ts[3]))
	print("Diff topo vs timestep: ", diff)
	assert(diff < 1e-5, "Topo and timestep should match for feedforward graphs")

	# Cycle detection: adding 3 -> 3 should be flagged as a loop.
	assert(g.would_create_loop(3, 3), "Self-loop should be detected")
	# Adding 3 -> 0 should be flagged (closes cycle 0->3->0).
	assert(g.would_create_loop(3, 0), "Reverse-edge cycle should be detected")
	# Adding 0 -> 1 should be fine.
	assert(not g.would_create_loop(0, 1), "0->1 should not create a cycle")

	# Test cloning.
	var g2 := g.duplicate()
	assert(g2.node_count() == g.node_count(), "Clone should match node count")
	assert(g2.connection_count() == g.connection_count(), "Clone should match connection count")
	g2.fitness = 42.0
	assert(g.fitness != 42.0, "Clone should be independent")

	# Test mutation visibility: enable/disable a connection.
	g.get_connection(innov0).enabled = false
	g.mark_dirty()
	assert(g.enabled_connections().size() == 2, "Should have 2 enabled connections")
	g.get_connection(innov0).enabled = true
	g.mark_dirty()
	assert(g.enabled_connections().size() == 3, "Should have 3 enabled connections")

	print("\n=== test_core: ALL PASSED ===")
	get_tree().quit()
