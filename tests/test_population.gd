extends Node
## End-to-end smoke test of the Population orchestrator.
## Run with: godot --headless --path . res://tests/test_population.tscn

func _ready() -> void:
        print("=== test_population ===")
        # Build a config for XOR: 2 inputs + 1 bias, 1 output.
        var cfg := NeatConfig.new()
        cfg.num_inputs = 2
        cfg.num_outputs = 1
        cfg.use_bias = true
        cfg.population_size = 30
        cfg.forward_mode = "topological"
        cfg.speciation_method = "standard"
        cfg.compatibility_threshold = 3.0
        cfg.target_species_count = 5
        cfg.generation_method = "asexual"
        cfg.enable_weight_mutation = true
        cfg.weight_mutation_rate = 0.8
        cfg.enable_connection_mutation = true
        cfg.connection_mutation_rate = 0.1
        cfg.enable_neuron_mutation = true
        cfg.neuron_mutation_rate = 0.05
        cfg.enable_prune_mutation = false
        cfg.enable_enable_mutation = false

        var pop := Population.new(cfg)
        pop.initialize()
        print("  Initial: gen=%d, pop=%d, species=%d" % [pop.generation, pop.size(), pop.species_count()])

        # Sanity check: every genome should have at least inputs+bias+outputs.
        # With the new random init, genomes may also have 0-3 hidden nodes and
        # 5-20 connections, so we just check the minimum.
        for g: Genome in pop.genomes:
                assert(g.node_count() >= 3 + 1, "Initial genome should have at least 2 inputs + 1 bias + 1 output = 4 nodes, got %d" % g.node_count())
                assert(g.connection_count() >= 1, "Initial genome should have at least 1 connection, got %d" % g.connection_count())
                assert(not g.has_loop(), "No loops in topological mode")

        # Forward pass should work.
        var g0: Genome = pop.genomes[0]
        var out := g0.forward({0: 1.0, 1: 0.0}, "topological")
        assert(out.size() == 1, "Should have 1 output")
        print("  Initial forward pass: OK (out[3]=%.3f)" % float(out[3]))

        # Run a few generations with a trivial fitness (favor networks that
        # output 0.5 for input (0,0)).
        for _i in range(5):
                pop.step(_xor_fitness)
        print("  After 5 generations: gen=%d, pop=%d, species=%d, best_fit=%.3f" % [pop.generation, pop.size(), pop.species_count(), pop.best_fitness])

        # After evolution, population should still be the same size.
        assert(pop.size() == cfg.population_size, "Population size should remain constant")

        # Test config with crossover.
        var cfg2 := NeatConfig.new()
        cfg2.num_inputs = 2
        cfg2.num_outputs = 1
        cfg2.use_bias = true
        cfg2.population_size = 20
        cfg2.generation_method = "mixed"
        cfg2.crossover_rate = 0.5
        cfg2.overall_crossover_method = "combine"
        cfg2.neuron_crossover_method = "average"
        var pop2 := Population.new(cfg2)
        pop2.initialize()
        for _i in range(3):
                pop2.step(_xor_fitness)
        assert(pop2.size() == cfg2.population_size, "Crossover population size should be stable")
        print("  Crossover after 3 generations: OK (pop=%d, species=%d)" % [pop2.size(), pop2.species_count()])

        # Test config with single speciation.
        var cfg3 := NeatConfig.new()
        cfg3.num_inputs = 2
        cfg3.num_outputs = 1
        cfg3.use_bias = true
        cfg3.population_size = 15
        cfg3.speciation_method = "single"
        var pop3 := Population.new(cfg3)
        pop3.initialize()
        for _i in range(2):
                pop3.step(_xor_fitness)
        assert(pop3.species_count() == 1, "Single speciation should produce 1 species, got %d" % pop3.species_count())
        print("  Single speciation: OK")

        # Test config with purge speciation.
        var cfg4 := NeatConfig.new()
        cfg4.num_inputs = 2
        cfg4.num_outputs = 1
        cfg4.use_bias = true
        cfg4.population_size = 15
        cfg4.speciation_method = "purge"
        cfg4.target_species_count = 5
        var pop4 := Population.new(cfg4)
        pop4.initialize()
        # First generation after purge: should produce N=target species count.
        assert(pop4.species_count() == 5, "Purge first-gen should produce 5 species (target), got %d" % pop4.species_count())
        for _i in range(2):
                pop4.step(_xor_fitness)
        print("  Purge after 2 more generations: OK (species=%d)" % pop4.species_count())

        print("\n=== test_population: ALL PASSED ===")
        get_tree().quit()

# Trivial fitness: 1.0 - |out - 0.5| for input (0, 0).
func _xor_fitness(g: Genome) -> float:
        var out := g.forward({0: 0.0, 1: 0.0}, "topological")
        var v: float = float(out.get(3, 0.0))
        return maxf(0.0, 1.0 - absf(v - 0.5))
