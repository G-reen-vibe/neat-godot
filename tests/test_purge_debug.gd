extends Node
## Debug Purge speciation behavior.
## Run with: godot --headless --path . res://tests/test_purge_debug.tscn

func _ready() -> void:
        print("=== test_purge_debug ===")
        var cfg := NeatConfig.new()
        cfg.num_inputs = 2
        cfg.num_outputs = 1
        cfg.use_bias = true
        cfg.population_size = 60
        cfg.speciation_method = "purge"
        cfg.target_species_count = 8
        cfg.forward_mode = "topological"
        cfg.enable_weight_mutation = true
        cfg.weight_mutation_rate = 0.8
        cfg.enable_connection_mutation = true
        cfg.connection_mutation_rate = 0.05
        cfg.enable_neuron_mutation = true
        cfg.neuron_mutation_rate = 0.03
        cfg.enable_enable_mutation = true
        cfg.enable_mutation_rate = 0.05

        var pop := Population.new(cfg)
        # Manually build strategies so we can inspect.
        var strategies := cfg.build_strategies()
        pop.similarity = strategies["similarity"]
        pop.speciation = strategies["speciation"]
        pop.mutation_policy = strategies["mutation_policy"]
        pop.rng.seed = 42
        pop.initialize()
        print("  Gen 0 (after init/Purge): species=%d" % pop.species_count())
        if pop.speciation is SpeciationStrategy.Purge:
                var purge := pop.speciation as SpeciationStrategy.Purge
                print("    Purge ideal_threshold=%.3f" % purge.ideal_threshold)
                print("    Purge first_generation=%s" % purge.first_generation)
                print("    Standard threshold=%.3f" % purge.standard.compatibility_threshold)
        # Run a few generations and watch species count.
        var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
        evaluator.num_threads = 0
        for gen in range(8):
                var fitnesses := evaluator.evaluate_all(pop.genomes)
                var cur_best: float = -1e9
                for i in range(pop.genomes.size()):
                        pop.genomes[i].fitness = fitnesses[i]
                        if fitnesses[i] > cur_best:
                                cur_best = fitnesses[i]
                        if fitnesses[i] > pop.best_fitness:
                                pop.best_fitness = fitnesses[i]
                                pop.best_genome = pop.genomes[i].duplicate()
                pop.evolve()
                var threshold: float = 0.0
                if pop.speciation is SpeciationStrategy.Purge:
                        threshold = (pop.speciation as SpeciationStrategy.Purge).standard.compatibility_threshold
                # Compute avg pairwise distance in current population (sample).
                var avg_d: float = 0.0
                var samples: int = 0
                for i in range(mini(10, pop.genomes.size())):
                        for j in range(i + 1, mini(10, pop.genomes.size())):
                                avg_d += pop.similarity.distance(pop.genomes[i], pop.genomes[j])
                                samples += 1
                avg_d /= float(maxi(1, samples))
                print("  Gen %d: species=%d  threshold=%.3f  best=%.3f  avg_dist=%.3f" % [pop.generation, pop.species_count(), threshold, cur_best, avg_d])
        print("\n=== test_purge_debug: DONE ===")
        get_tree().quit()

func _make_xor_env() -> MockTestEnv:
        return MockTestEnv.new([0, 1], 2, 3)
