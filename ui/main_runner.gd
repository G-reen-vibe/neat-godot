extends Control
## Main runner: trains NEAT on a choice of environments and shows both the
## graph visualizer (top-right) and a live simulation viewport (left/center).
##
## Run with: godot --path . res://ui/main_runner.tscn
##
## Controls:
##   1..6       Switch environment (1=XOR, 2=CartPole, 3=Acrobot, 4=Pong, 5=Spider2D, 6=Spider3D)
##   SPACE      Step one generation manually
##   R          Toggle auto-run
##   V          Cycle simulation view mode (Off -> Top -> Parallel -> Off)
##   N / B      In Top view: next genome / best genome
##   Arrows     Pan camera
##   +/-/0      Zoom in / out / reset

const MAX_GENERATIONS: int = 500

var cfg: NeatConfig
var pop: Population
var evaluator: Evaluator
var env_factory: Callable
var auto_run: bool = true
var steps_per_frame: int = 1
var current_env: int = 1  # default to CartPole (it has a nice visualization)

# UI elements.
var _visualizer: GraphVisualizer
var _info_label: Label
var _gen_label: Label
var _sim_viewport: SimulationViewport

# Pong-specific: track previous-generation top genomes for tournament opponents.
var _pong_opponents: Array = []  # Array[Genome]; top 3 from previous gen

func _ready() -> void:
        set_anchors_preset(PRESET_FULL_RECT)
        var bg := ColorRect.new()
        bg.set_anchors_preset(PRESET_FULL_RECT)
        bg.color = Color(0.08, 0.08, 0.12)
        add_child(bg)
        # Info label (top-left, above sim viewport).
        _info_label = Label.new()
        _info_label.position = Vector2(8, 8)
        _info_label.size = Vector2(640, 100)
        _info_label.add_theme_font_size_override("font_size", 13)
        _info_label.text = "Initializing..."
        add_child(_info_label)
        # Generation label (below info).
        _gen_label = Label.new()
        _gen_label.position = Vector2(8, 110)
        _gen_label.size = Vector2(640, 100)
        _gen_label.add_theme_font_size_override("font_size", 12)
        _gen_label.text = ""
        add_child(_gen_label)
        # Simulation viewport (fills remaining area on the left).
        _sim_viewport = SimulationViewport.new()
        _sim_viewport.position = Vector2(8, 220)
        _sim_viewport.size = Vector2(get_viewport().size.x - 400, get_viewport().size.y - 230)
        add_child(_sim_viewport)
        # Visualizer (top-right).
        _visualizer = GraphVisualizer.new()
        _visualizer.position = Vector2(get_viewport().size.x - 380, 8)
        _visualizer.size = Vector2(370, get_viewport().size.y - 16)
        add_child(_visualizer)
        # Initialize.
        _init_env(current_env)

func _init_env(env_idx: int) -> void:
        current_env = env_idx
        _pong_opponents.clear()
        match env_idx:
                0:
                        cfg = _make_xor_config()
                        env_factory = Callable(self, "_make_xor_env")
                        evaluator = Evaluator.new(env_factory, 100, "topological")
                1:
                        cfg = _make_cartpole_config()
                        env_factory = Callable(self, "_make_cartpole_env")
                        evaluator = Evaluator.new(env_factory, 600, "topological")
                        evaluator.episodes_per_genome = 3
                2:
                        cfg = _make_acrobot_config()
                        env_factory = Callable(self, "_make_acrobot_env")
                        evaluator = Evaluator.new(env_factory, 600, "topological")
                        evaluator.episodes_per_genome = 2
                3:
                        cfg = _make_pong_config()
                        env_factory = Callable(self, "_make_pong_env")
                        evaluator = Evaluator.new(env_factory, 1200, "topological")
                        evaluator.episodes_per_genome = 3  # best of 3
                4:
                        cfg = _make_spider2d_config()
                        env_factory = Callable(self, "_make_spider2d_env")
                        evaluator = Evaluator.new(env_factory, 1000, "topological")
                        evaluator.episodes_per_genome = 1
                5:
                        cfg = _make_spider3d_config()
                        env_factory = Callable(self, "_make_spider3d_env")
                        evaluator = Evaluator.new(env_factory, 1000, "topological")
                        evaluator.episodes_per_genome = 1
        evaluator.num_threads = 4
        pop = Population.new(cfg)
        pop.initialize()
        _visualizer.population = pop
        _sim_viewport.population = pop
        _sim_viewport.env_factory = env_factory
        _sim_viewport.forward_mode = cfg.forward_mode
        _info_label.text = "Env: %s\nPopulation: %d  Species: %d\n1..6=env  SPACE=step  R=run  V=view  N/B=genome  arrows=cam  +/-/0=zoom" % [
                _env_name(env_idx), pop.size(), pop.species_count()
        ]

func _env_name(idx: int) -> String:
        match idx:
                0: return "XOR"
                1: return "CartPole"
                2: return "Acrobot"
                3: return "Pong"
                4: return "Spider2D"
                5: return "Spider3D"
                _: return "?"

func _process(_delta: float) -> void:
        if auto_run and pop != null and pop.generation < MAX_GENERATIONS:
                for _i in range(steps_per_frame):
                        _step_generation()
                _visualizer.refresh()
                _update_gen_label()

func _step_generation() -> void:
        # For Pong: pass the previous generation's best genomes as opponents.
        if current_env == 3 and not _pong_opponents.is_empty():
                _evaluate_pong_with_tournament()
        else:
                var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
                for i in range(pop.genomes.size()):
                        pop.genomes[i].fitness = fitnesses[i]
                        if fitnesses[i] > pop.best_fitness:
                                pop.best_fitness = fitnesses[i]
                                pop.best_genome = pop.genomes[i].duplicate()
        # Update Pong opponents for next generation (top 3 from different species).
        if current_env == 3:
                _update_pong_opponents()
        pop.evolve()

func _evaluate_pong_with_tournament() -> void:
        # For each genome, run a best-of-3 tournament against the opponents.
        # We do this single-threaded for simplicity (Pong is fast).
        for i in range(pop.genomes.size()):
                var g: Genome = pop.genomes[i]
                var total_score: float = 0.0
                for opp: Genome in _pong_opponents:
                        var env: PongEnvironment = _make_pong_env()
                        env.set_player_a(g)
                        env.set_player_b(opp)
                        env.reset()
                        var state: Dictionary = env.initial_state()
                        var steps: int = 0
                        while not env.is_done() and steps < 1200:
                                # Both players act.
                                var out_a: Dictionary = g.forward(state, "topological")
                                var out_b: Dictionary = opp.forward(state, "topological")
                                var action: Dictionary = env.interpret_output(out_a, out_b)
                                state = env.step(action)
                                steps += 1
                        total_score += env.current_fitness()
                # Also play against nonmoving paddle.
                var env_static: PongEnvironment = _make_pong_env()
                env_static.set_player_a(g)
                env_static.set_player_b(null)  # nonmoving
                env_static.reset()
                var state2: Dictionary = env_static.initial_state()
                var steps2: int = 0
                while not env_static.is_done() and steps2 < 1200:
                        var out_a2: Dictionary = g.forward(state2, "topological")
                        var action2: Dictionary = env_static.interpret_output(out_a2, {})
                        state2 = env_static.step(action2)
                        steps2 += 1
                total_score += env_static.current_fitness() * 2.0  # weight static higher (easier)
                g.fitness = total_score / float(maxi(1, _pong_opponents.size() + 1))
                if g.fitness > pop.best_fitness:
                        pop.best_fitness = g.fitness
                        pop.best_genome = g.duplicate()

func _update_pong_opponents() -> void:
        # Pick top 3 genomes from different species.
        var candidates: Array = []
        for sp: Species in pop.species_list:
                # Sort species members by fitness descending.
                var members := sp.members.duplicate()
                members.sort_custom(func(a, b): return a.fitness > b.fitness)
                if not members.is_empty():
                        candidates.append(members[0])
        # Sort candidates by fitness and take top 3.
        candidates.sort_custom(func(a, b): return a.fitness > b.fitness)
        _pong_opponents = candidates.slice(0, mini(3, candidates.size()))

func _update_gen_label() -> void:
        var avg_conns: float = 0.0
        var avg_nodes: float = 0.0
        for g: Genome in pop.genomes:
                avg_conns += g.connection_count()
                avg_nodes += g.node_count()
        avg_conns /= float(maxi(1, pop.genomes.size()))
        avg_nodes /= float(maxi(1, pop.genomes.size()))
        _gen_label.text = "Generation: %d / %d\nBest fitness: %.3f\nSpecies: %d\nAvg nodes: %.1f  conns: %.1f" % [
                pop.generation, MAX_GENERATIONS, pop.best_fitness, pop.species_count(), avg_nodes, avg_conns
        ]

func _input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed:
                match event.keycode:
                        KEY_SPACE:
                                _step_generation()
                                _visualizer.refresh()
                                _update_gen_label()
                        KEY_R:
                                auto_run = not auto_run
                        KEY_1:
                                _init_env(0)
                        KEY_2:
                                _init_env(1)
                        KEY_3:
                                _init_env(2)
                        KEY_4:
                                _init_env(3)
                        KEY_5:
                                _init_env(4)
                        KEY_6:
                                _init_env(5)

# --- Configs ---

func _make_xor_config() -> NeatConfig:
        var c := NeatConfig.new()
        c.num_inputs = 2
        c.num_outputs = 1
        c.use_bias = true
        c.output_activation = ActivationFunctions.Func.SIGMOID
        c.population_size = 150
        c.forward_mode = "topological"
        c.speciation_method = "standard"
        c.compatibility_threshold = 6.0
        c.target_species_count = 10
        c.generation_method = "asexual"
        c.elite_count = 1
        c.enable_weight_mutation = true
        c.weight_mutation_rate = 0.8
        c.weight_mutation_min = 1
        c.enable_connection_mutation = true
        c.connection_mutation_rate = 0.3
        c.connection_mutation_min = 0
        c.enable_neuron_mutation = true
        c.neuron_mutation_rate = 0.2
        c.neuron_mutation_min = 0
        c.enable_enable_mutation = true
        c.enable_mutation_rate = 0.3
        c.enable_mutation_min = 0
        c.selection_method = "roulette"
        return c

func _make_cartpole_config() -> NeatConfig:
        var c := NeatConfig.new()
        c.num_inputs = 4
        c.num_outputs = 1
        c.use_bias = true
        c.output_activation = ActivationFunctions.Func.TANH
        c.population_size = 100
        c.forward_mode = "topological"
        c.speciation_method = "standard"
        c.compatibility_threshold = 6.0
        c.target_species_count = 10
        c.generation_method = "asexual"
        c.elite_count = 1
        c.enable_weight_mutation = true
        c.weight_mutation_rate = 0.8
        c.weight_mutation_min = 1
        c.enable_connection_mutation = true
        c.connection_mutation_rate = 0.3
        c.connection_mutation_min = 0
        c.enable_neuron_mutation = true
        c.neuron_mutation_rate = 0.2
        c.neuron_mutation_min = 0
        c.enable_enable_mutation = true
        c.enable_mutation_rate = 0.3
        c.enable_mutation_min = 0
        c.selection_method = "roulette"
        return c

func _make_acrobot_config() -> NeatConfig:
        var c := NeatConfig.new()
        c.num_inputs = 6
        c.num_outputs = 1
        c.use_bias = true
        c.output_activation = ActivationFunctions.Func.TANH
        c.population_size = 100
        c.forward_mode = "topological"
        c.speciation_method = "standard"
        c.compatibility_threshold = 6.0
        c.target_species_count = 10
        c.generation_method = "asexual"
        c.elite_count = 1
        c.enable_weight_mutation = true
        c.weight_mutation_rate = 0.8
        c.weight_mutation_min = 1
        c.enable_connection_mutation = true
        c.connection_mutation_rate = 0.3
        c.connection_mutation_min = 0
        c.enable_neuron_mutation = true
        c.neuron_mutation_rate = 0.2
        c.neuron_mutation_min = 0
        c.enable_enable_mutation = true
        c.enable_mutation_rate = 0.3
        c.enable_mutation_min = 0
        c.selection_method = "roulette"
        return c

func _make_pong_config() -> NeatConfig:
        var c := NeatConfig.new()
        c.num_inputs = 6  # ball_x, ball_y, ball_vx, ball_vy, own_paddle_y, opp_paddle_y
        c.num_outputs = 1  # paddle direction (-1, 0, +1)
        c.use_bias = true
        c.output_activation = ActivationFunctions.Func.TANH
        c.population_size = 80
        c.forward_mode = "topological"
        c.speciation_method = "standard"
        c.compatibility_threshold = 6.0
        c.target_species_count = 10
        c.generation_method = "asexual"
        c.elite_count = 1
        c.enable_weight_mutation = true
        c.weight_mutation_rate = 0.8
        c.weight_mutation_min = 1
        c.enable_connection_mutation = true
        c.connection_mutation_rate = 0.3
        c.connection_mutation_min = 0
        c.enable_neuron_mutation = true
        c.neuron_mutation_rate = 0.2
        c.neuron_mutation_min = 0
        c.enable_enable_mutation = true
        c.enable_mutation_rate = 0.3
        c.enable_mutation_min = 0
        c.selection_method = "roulette"
        return c

func _make_spider2d_config() -> NeatConfig:
        var c := NeatConfig.new()
        c.num_inputs = 12  # 4 legs * (touch_sensor, angle, target_angle_diff, body_lean)
        c.num_outputs = 8  # 4 legs * 2 (target angle delta, extend/retract)
        c.use_bias = true
        c.output_activation = ActivationFunctions.Func.TANH
        c.population_size = 80
        c.forward_mode = "topological"
        c.speciation_method = "standard"
        c.compatibility_threshold = 6.0
        c.target_species_count = 10
        c.generation_method = "asexual"
        c.elite_count = 1
        c.enable_weight_mutation = true
        c.weight_mutation_rate = 0.8
        c.weight_mutation_min = 1
        c.enable_connection_mutation = true
        c.connection_mutation_rate = 0.3
        c.connection_mutation_min = 0
        c.enable_neuron_mutation = true
        c.neuron_mutation_rate = 0.2
        c.neuron_mutation_min = 0
        c.enable_enable_mutation = true
        c.enable_mutation_rate = 0.3
        c.enable_mutation_min = 0
        c.selection_method = "roulette"
        return c

func _make_spider3d_config() -> NeatConfig:
        var c := NeatConfig.new()
        c.num_inputs = 16  # 4 legs * 4 (touch, angle_x, angle_y, target_diff)
        c.num_outputs = 12  # 4 legs * 3 (target angle delta x/y, extend)
        c.use_bias = true
        c.output_activation = ActivationFunctions.Func.TANH
        c.population_size = 60
        c.forward_mode = "topological"
        c.speciation_method = "standard"
        c.compatibility_threshold = 6.0
        c.target_species_count = 10
        c.generation_method = "asexual"
        c.elite_count = 1
        c.enable_weight_mutation = true
        c.weight_mutation_rate = 0.8
        c.weight_mutation_min = 1
        c.enable_connection_mutation = true
        c.connection_mutation_rate = 0.3
        c.connection_mutation_min = 0
        c.enable_neuron_mutation = true
        c.neuron_mutation_rate = 0.2
        c.neuron_mutation_min = 0
        c.enable_enable_mutation = true
        c.enable_mutation_rate = 0.3
        c.enable_mutation_min = 0
        c.selection_method = "roulette"
        return c

# --- Env factories ---

func _make_xor_env() -> XorEnvironment:
        return XorEnvironment.new([0, 1], 2, 3)

func _make_cartpole_env() -> CartPoleEnvironment:
        return CartPoleEnvironment.new([0, 1, 2, 3], 4, 5, 500)

func _make_acrobot_env() -> AcrobotEnvironment:
        return AcrobotEnvironment.new([0, 1, 2, 3, 4, 5], 6, 7, 500)

func _make_pong_env() -> PongEnvironment:
        # 6 inputs: ball_x, ball_y, ball_vx, ball_vy, own_paddle_y, opp_paddle_y
        # 1 output: paddle direction
        return PongEnvironment.new([0, 1, 2, 3, 4, 5], 6, 7)

func _make_spider2d_env() -> SpiderWalker2DEnvironment:
        # 12 inputs, 8 outputs, bias id 12.
        var input_ids: Array[int] = []
        for i in range(12):
                input_ids.append(i)
        return SpiderWalker2DEnvironment.new(input_ids, 12, [13, 14, 15, 16, 17, 18, 19, 20])

func _make_spider3d_env() -> SpiderWalker3DEnvironment:
        var input_ids: Array[int] = []
        for i in range(16):
                input_ids.append(i)
        return SpiderWalker3DEnvironment.new(input_ids, 16, [17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28])
