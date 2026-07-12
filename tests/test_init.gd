extends Node
## Test the new random initialization method.
## Run with: godot --headless --path . res://tests/test_init.tscn

func _ready() -> void:
	print("=== test_init: random initialization ===")
	var cfg := NeatConfig.new()
	cfg.num_inputs = 4
	cfg.num_outputs = 2
	cfg.use_bias = true
	cfg.population_size = 50
	cfg.forward_mode = "topological"
	cfg.init_min_hidden_nodes = 0
	cfg.init_max_hidden_nodes = 3
	cfg.init_min_connections = 5
	cfg.init_max_connections = 20
	cfg.init_weight_min = -1.0
	cfg.init_weight_max = 1.0

	var pop := Population.new(cfg)
	pop.initialize()
	print("  Population: %d genomes" % pop.size())
	# Check diversity: genomes should have varying node/connection counts.
	var node_counts: Dictionary = {}
	var conn_counts: Dictionary = {}
	var any_has_hidden: bool = false
	var total_conns: int = 0
	var total_nodes: int = 0
	for g: Genome in pop.genomes:
		var nc: int = g.node_count()
		var cc: int = g.connection_count()
		node_counts[nc] = int(node_counts.get(nc, 0)) + 1
		conn_counts[cc] = int(conn_counts.get(cc, 0)) + 1
		total_conns += cc
		total_nodes += nc
		if nc > 4 + 1 + 2:  # inputs + bias + outputs = 7
			any_has_hidden = true
	print("  Node count distribution: %s" % node_counts)
	print("  Conn count distribution: %s" % conn_counts)
	print("  Avg nodes: %.1f  Avg conns: %.1f" % [float(total_nodes) / pop.size(), float(total_conns) / pop.size()])
	print("  Any genome with hidden nodes: %s" % any_has_hidden)
	# Verify constraints.
	for g: Genome in pop.genomes:
		assert(g.node_count() >= 4 + 1 + 2, "Genome should have at least inputs+bias+outputs")
		# Max feasible connections for a genome with n nodes (excluding self-loops):
		# sources = non-output nodes, targets = non-input/bias nodes.
		# But we just check it's reasonable (< 50).
		assert(g.connection_count() <= 50, "Connection count should be reasonable")
		# Verify no self-loops.
		for c: ConnectionGene in g.connections.values():
			assert(c.from_node != c.to_node, "No self-loops allowed")
		# Verify no loops in topological mode.
		assert(not g.has_loop(), "No loops in topological mode")
	# Verify diversity.
	assert(node_counts.size() >= 2, "Should have diverse node counts")
	assert(conn_counts.size() >= 2, "Should have diverse connection counts")
	print("  All constraints verified.")
	# Test forward pass works.
	var g0: Genome = pop.genomes[0]
	var out := g0.forward({0: 1.0, 1: 0.5, 2: -0.5, 3: 0.0}, "topological")
	print("  Forward pass output: %s" % out)
	assert(out.size() == 2, "Should have 2 outputs")
	print("\n=== test_init: ALL PASSED ===")
	get_tree().quit()
