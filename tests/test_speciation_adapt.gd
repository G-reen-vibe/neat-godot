extends Node
## Test that speciation species count actually changes when params change.
## Run with: godot --headless --path . res://tests/test_speciation_adapt.tscn

var _failed: bool = false

func _ready() -> void:
        print("=== test_speciation_adapt: species count adapts ===")
        _test_standard_adapts_to_target()
        if _failed: _halt()
        _test_purge_adapts_after_first_gen()
        if _failed: _halt()
        _test_standard_threshold_changes()
        if _failed: _halt()
        print("\n=== test_speciation_adapt: ALL PASSED ===")
        get_tree().quit()

func _assert(cond: bool, msg: String) -> void:
        if not cond:
                push_error("ASSERT FAILED: " + msg)
                _failed = true

func _halt() -> void:
        printerr("\n=== test_speciation_adapt: FAILED ===")
        get_tree().quit(1)

func _test_standard_adapts_to_target() -> void:
        # With Standard speciation and target=5, the species count should
        # converge toward 5 over generations.
        var cfg := NeatConfig.new()
        cfg.num_inputs = 2
        cfg.num_outputs = 1
        cfg.use_bias = true
        cfg.population_size = 100
        cfg.forward_mode = "topological"
        cfg.speciation_method = "standard"
        cfg.compatibility_threshold = 3.0
        cfg.target_species_count = 5
        cfg.generation_method = "asexual"
        cfg.enable_weight_mutation = true
        cfg.weight_mutation_rate = 0.8
        cfg.enable_connection_mutation = true
        cfg.connection_mutation_rate = 0.3
        cfg.enable_neuron_mutation = true
        cfg.neuron_mutation_rate = 0.2
        cfg.enable_enable_mutation = true
        cfg.enable_mutation_rate = 0.3
        cfg.forbid_loops = true
        
        var pop := Population.new(cfg)
        pop.initialize()
        var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
        evaluator.num_threads = 0
        
        var counts: Array[int] = []
        for _g in range(20):
                var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
                for i in range(pop.genomes.size()):
                        pop.genomes[i].fitness = fitnesses[i]
                pop.evolve()
                counts.append(pop.species_count())
        
        print("  Standard target=5: species counts over 20 gens: %s" % str(counts))
        # After 20 generations, the count should be closer to 5 than the initial count.
        var initial: int = counts[0]
        var final: int = counts[-1]
        _assert(absi(final - 5) < absi(initial - 5), "Standard should converge toward target: initial=%d final=%d target=5" % [initial, final])
        print("  Standard adapts to target: OK (initial=%d -> final=%d, target=5)" % [initial, final])

func _test_purge_adapts_after_first_gen() -> void:
        # With Purge speciation, the first gen creates N species.
        # After that, Standard takes over and the count should change if the
        # genomes diverge enough.
        var cfg := NeatConfig.new()
        cfg.num_inputs = 2
        cfg.num_outputs = 1
        cfg.use_bias = true
        cfg.population_size = 100
        cfg.forward_mode = "topological"
        cfg.speciation_method = "purge"
        cfg.target_species_count = 10
        cfg.compatibility_threshold = 3.0
        cfg.generation_method = "asexual"
        cfg.enable_weight_mutation = true
        cfg.weight_mutation_rate = 0.8
        cfg.enable_connection_mutation = true
        cfg.connection_mutation_rate = 0.3
        cfg.enable_neuron_mutation = true
        cfg.neuron_mutation_rate = 0.2
        cfg.enable_enable_mutation = true
        cfg.enable_mutation_rate = 0.3
        cfg.forbid_loops = true
        
        var pop := Population.new(cfg)
        pop.initialize()
        var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
        evaluator.num_threads = 0
        
        var counts: Array[int] = [pop.species_count()]
        for _g in range(15):
                var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
                for i in range(pop.genomes.size()):
                        pop.genomes[i].fitness = fitnesses[i]
                pop.evolve()
                counts.append(pop.species_count())
        
        print("  Purge target=10: species counts over 15 gens: %s" % str(counts))
        # The first gen should have ~10 species (from Purge).
        _assert(counts[0] == 10, "Purge first gen should have 10 species, got %d" % counts[0])
        # After several generations, the count should change (either increase due
        # to mutation creating new species, or decrease due to merging).
        # It should NOT stay exactly at 10 forever.
        var any_change: bool = false
        for i in range(1, counts.size()):
                if counts[i] != 10:
                        any_change = true
                        break
        _assert(any_change, "Purge species count should change after first gen (was stuck at 10)")
        print("  Purge adapts after first gen: OK (initial=%d, later counts vary)" % counts[0])

func _test_standard_threshold_changes() -> void:
        # Verify that the compatibility_threshold actually changes over generations.
        var cfg := NeatConfig.new()
        cfg.num_inputs = 2
        cfg.num_outputs = 1
        cfg.use_bias = true
        cfg.population_size = 100
        cfg.forward_mode = "topological"
        cfg.speciation_method = "standard"
        cfg.compatibility_threshold = 3.0
        cfg.target_species_count = 5
        cfg.generation_method = "asexual"
        cfg.enable_weight_mutation = true
        cfg.weight_mutation_rate = 0.8
        cfg.enable_connection_mutation = true
        cfg.connection_mutation_rate = 0.3
        cfg.enable_neuron_mutation = true
        cfg.neuron_mutation_rate = 0.2
        cfg.enable_enable_mutation = true
        cfg.enable_mutation_rate = 0.3
        cfg.forbid_loops = true
        
        var pop := Population.new(cfg)
        # Read the threshold BEFORE initialize (which adjusts it).
        var std_sp: SpeciationStrategy.Standard = pop.speciation
        var initial_threshold: float = std_sp.compatibility_threshold
        pop.initialize()
        var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
        evaluator.num_threads = 0
        
        for _g in range(10):
                var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
                for i in range(pop.genomes.size()):
                        pop.genomes[i].fitness = fitnesses[i]
                pop.evolve()
        var final_threshold: float = std_sp.compatibility_threshold
        
        print("  Standard threshold: initial=%.3f -> after init+10 gens=%.3f" % [initial_threshold, final_threshold])
        _assert(absf(final_threshold - initial_threshold) > 0.01, "Threshold should change: initial=%.3f final=%.3f" % [initial_threshold, final_threshold])
        print("  Standard threshold changes: OK")

func _make_xor_env() -> MockTestEnv:
        return MockTestEnv.new([0, 1], 2, 3)
