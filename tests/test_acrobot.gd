extends Node
## Acrobot training test: run NEAT until it solves Acrobot (or hits max gens).
## Run with: godot --headless --path . res://tests/test_acrobot.tscn

const MAX_GENERATIONS: int = 30
const SOLVED_FITNESS: float = 2.0  # tip_y > 1.0 + step bonus
const POP_SIZE: int = 60
const EPISODES: int = 2

func _ready() -> void:
        print("=== test_acrobot: full NEAT Acrobot training ===")
        var cfg := NeatConfig.new()
        cfg.num_inputs = 6  # cos(t1), sin(t1), cos(t2), sin(t2), t1_dot, t2_dot
        cfg.num_outputs = 1
        cfg.use_bias = true
        cfg.output_activation = ActivationFunctions.Func.TANH
        cfg.population_size = POP_SIZE
        cfg.forward_mode = "topological"
        cfg.speciation_method = "standard"
        cfg.compatibility_threshold = 6.0
        cfg.target_species_count = 10
        cfg.generation_method = "asexual"
        cfg.elite_count = 1
        cfg.enable_weight_mutation = true
        cfg.weight_mutation_rate = 0.8
        cfg.weight_mutation_min = 1
        cfg.weight_mutation_delta_min = -1.0
        cfg.weight_mutation_delta_max = 1.0
        cfg.enable_connection_mutation = true
        cfg.connection_mutation_rate = 0.3
        cfg.connection_mutation_min = 0
        cfg.enable_neuron_mutation = true
        cfg.neuron_mutation_rate = 0.2
        cfg.neuron_mutation_min = 0
        cfg.enable_enable_mutation = true
        cfg.enable_mutation_rate = 0.3
        cfg.enable_mutation_min = 0
        cfg.selection_method = "roulette"
        cfg.similarity_method = "standard"
        cfg.similarity_c1 = 1.0
        cfg.similarity_c2 = 1.0
        cfg.similarity_c3 = 0.4

        var pop := Population.new(cfg)
        pop.initialize()
        # 6 inputs (0..5), bias id 6, output id 7.
        var env_factory: Callable = Callable(self, "_make_acrobot_env")
        var evaluator := Evaluator.new(env_factory, 600, "topological")
        evaluator.episodes_per_genome = EPISODES
        evaluator.num_threads = 4

        print("  Initialized: pop=%d, species=%d" % [pop.size(), pop.species_count()])

        var start_time := Time.get_ticks_msec()
        var solved_gen: int = -1
        for gen in range(MAX_GENERATIONS):
                var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
                var cur_best: float = -1e9
                for i in range(pop.genomes.size()):
                        pop.genomes[i].fitness = fitnesses[i]
                        if fitnesses[i] > cur_best:
                                cur_best = fitnesses[i]
                        if fitnesses[i] > pop.best_fitness:
                                pop.best_fitness = fitnesses[i]
                                pop.best_genome = pop.genomes[i].duplicate()
                if cur_best >= SOLVED_FITNESS and solved_gen < 0:
                        solved_gen = pop.generation
                        print("  *** SOLVED at gen %d (fitness=%.3f) ***" % [pop.generation, cur_best])
                        break
                if gen % 5 == 0:
                        print("  gen=%d  best=%.3f  cur_best=%.3f  species=%d  avg_conns=%.1f" %
                                [pop.generation, pop.best_fitness, cur_best, pop.species_count(), _avg_conns(pop)])
                pop.evolve()

        var elapsed := Time.get_ticks_msec() - start_time
        print("  Total time: %d ms (%.1f s)" % [elapsed, elapsed / 1000.0])
        print("  Best fitness: %.3f" % pop.best_fitness)
        if pop.best_genome != null:
                print("  Best genome: %s" % pop.best_genome)
        if solved_gen >= 0:
                print("\n=== test_acrobot: SOLVED at gen %d ===" % solved_gen)
        else:
                print("\n=== test_acrobot: did NOT solve in %d generations ===" % MAX_GENERATIONS)
        get_tree().quit()

func _make_acrobot_env() -> AcrobotEnvironment:
        # 6 inputs (0..5), bias id 6, output id 7.
        return AcrobotEnvironment.new([0, 1, 2, 3, 4, 5], 6, 7, 500)

func _avg_conns(pop: Population) -> float:
        var total: int = 0
        for g: Genome in pop.genomes:
                total += g.connection_count()
        return float(total) / float(maxi(1, pop.genomes.size()))
