extends Node
## Pong training test with best-of-3 tournament vs top-3-from-prev-gen.
## Run with: godot --headless --path . res://tests/test_pong.tscn

const MAX_GENERATIONS: int = 30
const POP_SIZE: int = 40

var tracker: InnovationTracker
var rng: RandomNumberGenerator
var input_ids: Array[int] = [0, 1, 2, 3, 4, 5]
var bias_id: int = 6
var output_ids: Array[int] = [7]

func _ready() -> void:
        print("=== test_pong: training with tournament ===")
        tracker = InnovationTracker.new()
        rng = RandomNumberGenerator.new()
        rng.seed = 7

        var cfg := NeatConfig.new()
        cfg.num_inputs = 6
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

        var pop := Population.new(cfg)
        pop.initialize()
        print("  Initialized: pop=%d, species=%d" % [pop.size(), pop.species_count()])

        var opponents: Array = []  # top 3 from prev gen (different species)
        var start_time := Time.get_ticks_msec()
        for gen in range(MAX_GENERATIONS):
                _evaluate_generation(pop, opponents)
                # Update opponents.
                opponents = _pick_top_from_different_species(pop, 3)
                if gen % 5 == 0:
                        print("  gen=%d  best=%.2f  species=%d  opponents=%d" % [pop.generation, pop.best_fitness, pop.species_count(), opponents.size()])
                pop.evolve()

        var elapsed := Time.get_ticks_msec() - start_time
        print("  Total time: %d ms (%.1f s)" % [elapsed, elapsed / 1000.0])
        print("  Best fitness: %.2f" % pop.best_fitness)
        if pop.best_genome != null:
                print("  Best genome: %s" % pop.best_genome)
        print("\n=== test_pong: DONE ===")
        get_tree().quit()

func _evaluate_generation(pop: Population, opponents: Array) -> void:
        for i in range(pop.genomes.size()):
                var g: Genome = pop.genomes[i]
                var total_score: float = 0.0
                # Play against nonmoving paddle.
                var env_static := PongEnvironment.new(input_ids, bias_id, output_ids[0])
                env_static.set_player_a(g)
                env_static.set_player_b(null)
                env_static.reset(rng)
                var state: Dictionary = env_static.initial_state()
                var steps: int = 0
                while not env_static.is_done() and steps < 1200:
                        var out: Dictionary = g.forward(state, "topological")
                        var action: Dictionary = env_static.interpret_output(out, {})
                        state = env_static.step(action)
                        steps += 1
                total_score += env_static.current_fitness() * 2.0  # weight static higher (easier)
                # Play against each opponent (best of 3 effectively).
                for opp: Genome in opponents:
                        var env := PongEnvironment.new(input_ids, bias_id, output_ids[0])
                        env.set_player_a(g)
                        env.set_player_b(opp)
                        env.reset(rng)
                        state = env.initial_state()
                        steps = 0
                        while not env.is_done() and steps < 1200:
                                # Player A sees A's perspective; Player B sees B's (mirrored).
                                var state_b: Dictionary = env.get_state_for_player(1)
                                var out_a: Dictionary = g.forward(state, "topological")
                                var out_b: Dictionary = opp.forward(state_b, "topological")
                                var action: Dictionary = env.interpret_output(out_a, out_b)
                                state = env.step(action)
                                steps += 1
                        total_score += env.current_fitness()
                g.fitness = total_score / float(maxi(1, opponents.size() + 1))
                if g.fitness > pop.best_fitness:
                        pop.best_fitness = g.fitness
                        pop.best_genome = g.duplicate()

func _pick_top_from_different_species(pop: Population, k: int) -> Array:
        var candidates: Array = []
        for sp: Species in pop.species_list:
                var members := sp.members.duplicate()
                members.sort_custom(func(a, b): return a.fitness > b.fitness)
                if not members.is_empty():
                        candidates.append(members[0])
        candidates.sort_custom(func(a, b): return a.fitness > b.fitness)
        return candidates.slice(0, mini(k, candidates.size()))
