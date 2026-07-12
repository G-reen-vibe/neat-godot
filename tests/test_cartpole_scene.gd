extends Node
## Phase 0 / Phase 1 PoC: Verify that SubViewport-batched physics evaluation
## with real RigidBody2D works for CartPole and that NEAT can learn it.
##
## Run with:
##   godot --headless --path . res://tests/test_cartpole_scene.tscn

const MAX_GENERATIONS: int = 30
const POP_SIZE: int = 40
const NUM_SLOTS: int = 40
const MAX_STEPS: int = 500
const SPEEDUP: float = 2.0

var _failed: bool = false

func _ready() -> void:
        print("=== test_cartpole_scene: real-physics CartPole via SceneEvaluator ===")
        await _test_cartpole()
        if _failed:
                printerr("\n=== test_cartpole_scene: FAILED ===")
                get_tree().quit(1)
        else:
                print("\n=== test_cartpole_scene: PASSED ===")
                get_tree().quit(0)

func _assert(cond: bool, msg: String) -> void:
        if not cond:
                push_error("ASSERT FAILED: " + msg)
                _failed = true

func _test_cartpole() -> void:
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
        cfg.target_species_count = 8
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
        # Load the cartpole scene and build the SceneEvaluator.
        var env_scene: PackedScene = load("res://environments/cartpole/cartpole_environment.tscn")
        var input_ids: Array[int] = [0, 1, 2, 3]
        var bias_id: int = 4
        var output_id: int = 5
        var evaluator := SceneEvaluator.new(self, env_scene, NUM_SLOTS, MAX_STEPS + 10, "topological")
        evaluator.speedup = SPEEDUP
        evaluator.episodes_per_genome = 1
        evaluator.env_setup_fn = func(env: Node) -> void:
                env.input_node_ids = input_ids
                env.bias_node_id = bias_id
                env.output_node_id = output_id
                env.set_max_steps(MAX_STEPS)
        var best_f: float = -1e9
        var first_gen_best: float = -1e9
        var elapsed: float = Time.get_ticks_msec()
        for gen in range(MAX_GENERATIONS):
                # Configure each env's IO + max_steps (must be done before reset).
                var fitnesses: Array[float] = await evaluator.evaluate_all(pop.genomes)
                for i in range(pop.genomes.size()):
                        pop.genomes[i].fitness = fitnesses[i]
                        if fitnesses[i] > best_f:
                                best_f = fitnesses[i]
                        if gen == 0 and fitnesses[i] > first_gen_best:
                                first_gen_best = fitnesses[i]
                if gen == 0:
                        print("    gen 0 fitnesses: %s" % str(fitnesses.slice(0, 10)))
                        print("    gen 0 fitness range: min=%.1f max=%.1f avg=%.1f" % [
                                fitnesses.min(), fitnesses.max(),
                                fitnesses.reduce(func(a, b): return a + b, 0.0) / fitnesses.size()])
                if gen % 3 == 0 or gen == MAX_GENERATIONS - 1:
                        print("    gen=%d  best=%.3f  species=%d  elapsed_ms=%d" % [
                                pop.generation, best_f, pop.species_count(), Time.get_ticks_msec() - elapsed])
                pop.evolve()
        evaluator.dispose()
        # Assertions.
        _assert(best_f > 0.0, "CartPole: best fitness should be > 0 after %d gens, got %.3f" % [MAX_GENERATIONS, best_f])
        _assert(best_f >= 50.0, "CartPole: best fitness should reach at least 50 steps (basic learning), got %.3f" % best_f)
        _assert(pop.size() == cfg.population_size, "CartPole: pop size stable at %d, got %d" % [cfg.population_size, pop.size()])
        print("    RESULT: best=%.3f (first gen best=%.3f)" % [best_f, first_gen_best])
