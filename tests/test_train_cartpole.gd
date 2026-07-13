extends Node
## End-to-end test: NEAT training on CartPole via the NeatCartPoleEnv adapter.
##
## Verifies the full training loop works: SceneEvaluator + NeatCartPoleEnv +
## Population.evolve(). Checks that fitnesses are produced, the population
## evolves, and best fitness is non-zero. Uses small params to keep runtime
## under ~3 minutes in headless mode (physics is 60 Hz, so each step is real
## wall-clock time).
##
## Run with:
##   godot --headless --path . res://tests/test_train_cartpole.tscn

const MAX_GENERATIONS: int = 5
const POP_SIZE: int = 15
const NUM_SLOTS: int = 15
const MAX_STEPS: int = 200

var _failed: bool = false

func _ready() -> void:
        print("=== test_train_cartpole: NEAT training via NeatCartPoleEnv ===")
        await _test()
        if _failed:
                printerr("\n=== test_train_cartpole: FAILED ===")
                get_tree().quit(1)
        else:
                print("\n=== test_train_cartpole: PASSED ===")
                get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
        if not cond:
                push_error("ASSERT FAILED: " + msg)
                _failed = true

func _test() -> void:
        var cfg := NeatConfig.new()
        cfg.num_inputs = 4
        cfg.num_outputs = 1
        cfg.use_bias = true
        cfg.output_activation = ActivationFunctions.Func.TANH
        cfg.population_size = POP_SIZE
        cfg.forward_mode = "topological"
        cfg.forbid_loops = true
        cfg.speciation_method = "standard"
        cfg.compatibility_threshold = 6.0
        cfg.target_species_count = 5
        cfg.generation_method = "asexual"
        cfg.elite_count = 1
        cfg.enable_weight_mutation = true
        cfg.weight_mutation_rate = 0.8
        cfg.weight_mutation_min = 1
        cfg.enable_connection_mutation = true
        cfg.connection_mutation_rate = 0.3
        cfg.enable_neuron_mutation = true
        cfg.neuron_mutation_rate = 0.2
        cfg.enable_enable_mutation = true
        cfg.enable_mutation_rate = 0.3
        cfg.selection_method = "roulette"
        var pop := Population.new(cfg)
        pop.initialize()
        var env_scene: PackedScene = load("res://environments/cartpole/neat_cartpole_env.tscn")
        var input_ids: Array[int] = [0, 1, 2, 3]
        var output_ids: Array[int] = [5]
        var evaluator := SceneEvaluator.new(self, env_scene, NUM_SLOTS, MAX_STEPS + 10, "topological")
        evaluator.episodes_per_genome = 1
        evaluator.env_setup_fn = func(env: Node) -> void:
                env.input_node_ids = input_ids
                env.bias_node_id = 4
                env.output_node_id = 5
                env.output_node_ids = output_ids
                env.set_max_steps(MAX_STEPS)
        var best_f: float = -1e9
        var first_gen_best: float = -1e9
        var elapsed: float = Time.get_ticks_msec()
        for gen in range(MAX_GENERATIONS):
                var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
                for i in range(pop.genomes.size()):
                        pop.genomes[i].fitness = fitnesses[i]
                        if fitnesses[i] > best_f:
                                best_f = fitnesses[i]
                        if fitnesses[i] > pop.best_fitness:
                                pop.best_fitness = fitnesses[i]
                                pop.best_genome = pop.genomes[i].duplicate()
                        if gen == 0 and fitnesses[i] > first_gen_best:
                                first_gen_best = fitnesses[i]
                var avg_f: float = fitnesses.reduce(func(a, b): return a + b, 0.0) / fitnesses.size()
                print("    gen=%d  best=%.1f  avg=%.1f  max=%.1f  species=%d  elapsed_ms=%d" % [
                        pop.generation, best_f, avg_f, fitnesses.max(), pop.species_count(),
                        Time.get_ticks_msec() - elapsed])
                pop.evolve()
        evaluator.dispose()
        # Assertions:
        # 1. Best fitness > 0 (at least one genome survived some steps).
        _assert(best_f > 0.0, "best fitness > 0 after %d gens, got %.3f" % [MAX_GENERATIONS, best_f])
        # 2. Population size stable.
        _assert(pop.size() == cfg.population_size, "pop size stable at %d, got %d" % [cfg.population_size, pop.size()])
        # 3. Generation counter advanced.
        _assert(pop.generation == MAX_GENERATIONS, "generation = %d, expected %d" % [pop.generation, MAX_GENERATIONS])
        # 4. Best genome exists.
        _assert(pop.best_genome != null, "best genome is set")
        print("    RESULT: best=%.3f (first gen best=%.3f)" % [best_f, first_gen_best])
