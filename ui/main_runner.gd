extends Control
## Main runner: trains NEAT on XOR (default) and shows the graph visualizer.
## Run with: godot --path . res://ui/main_runner.tscn
##
## Controls:
##   - The visualizer panel (top-right) lets you browse species and genomes.
##   - Press SPACE to step one generation manually.
##   - Press R to toggle auto-run.
##   - Press 1/2/3 to switch environment (XOR / CartPole / Acrobot).

const MAX_GENERATIONS: int = 200

var cfg: NeatConfig
var pop: Population
var evaluator: Evaluator
var env_factory: Callable
var auto_run: bool = true
var steps_per_frame: int = 1  # generations per frame when auto-running
var current_env: int = 0  # 0=XOR, 1=CartPole, 2=Acrobot

var _visualizer: GraphVisualizer
var _info_label: Label
var _gen_label: Label

func _ready() -> void:
	# Build the UI.
	set_anchors_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.12)
	add_child(bg)
	# Info label (top-left).
	_info_label = Label.new()
	_info_label.position = Vector2(8, 8)
	_info_label.size = Vector2(400, 200)
	_info_label.add_theme_font_size_override("font_size", 14)
	_info_label.text = "Initializing..."
	add_child(_info_label)
	# Generation label (bottom-left).
	_gen_label = Label.new()
	_gen_label.position = Vector2(8, 220)
	_gen_label.size = Vector2(400, 200)
	_gen_label.add_theme_font_size_override("font_size", 12)
	_gen_label.text = ""
	add_child(_gen_label)
	# Visualizer (top-right).
	_visualizer = GraphVisualizer.new()
	_visualizer.position = Vector2(get_viewport().size.x - 380, 8)
	_visualizer.size = Vector2(370, 470)
	add_child(_visualizer)
	# Initialize with XOR.
	_init_env(0)

func _init_env(env_idx: int) -> void:
	current_env = env_idx
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
			evaluator.episodes_per_genome = 3
	evaluator.num_threads = 4
	pop = Population.new(cfg)
	pop.initialize()
	_visualizer.population = pop
	_info_label.text = "Env: %s\nPopulation: %d\nSpecies: %d\nPress SPACE to step, R to toggle auto-run, 1/2/3 to switch env" % [
		_env_name(env_idx), pop.size(), pop.species_count()
	]

func _env_name(idx: int) -> String:
	match idx:
		0: return "XOR"
		1: return "CartPole"
		2: return "Acrobot"
		_: return "?"

func _process(_delta: float) -> void:
	if auto_run and pop != null and pop.generation < MAX_GENERATIONS:
		for _i in range(steps_per_frame):
			_step_generation()
		_visualizer.refresh()
		_update_gen_label()

func _step_generation() -> void:
	var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
	for i in range(pop.genomes.size()):
		pop.genomes[i].fitness = fitnesses[i]
		if fitnesses[i] > pop.best_fitness:
			pop.best_fitness = fitnesses[i]
			pop.best_genome = pop.genomes[i].duplicate()
	pop.evolve()

func _update_gen_label() -> void:
	var avg_conns: float = 0.0
	var avg_nodes: float = 0.0
	for g: Genome in pop.genomes:
		avg_conns += g.connection_count()
		avg_nodes += g.node_count()
	avg_conns /= float(maxi(1, pop.genomes.size()))
	avg_nodes /= float(maxi(1, pop.genomes.size()))
	_gen_label.text = "Generation: %d / %d\nBest fitness: %.3f\nSpecies: %d\nAvg nodes: %.1f\nAvg conns: %.1f" % [
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

# --- Env factories ---

func _make_xor_env() -> XorEnvironment:
	return XorEnvironment.new([0, 1], 2, 3)

func _make_cartpole_env() -> CartPoleEnvironment:
	return CartPoleEnvironment.new([0, 1, 2, 3], 4, 5, 500)

func _make_acrobot_env() -> AcrobotEnvironment:
	return AcrobotEnvironment.new([0, 1, 2, 3, 4, 5], 6, 7, 500)
