extends Node
## Final gameplay simulation test: exercises the main runner UI logic
## (species/genome navigation, stats, env switching) as if a user was playing.
## Run with: godot --headless --path . res://tests/test_gameplay.tscn

func _ready() -> void:
	print("=== test_gameplay: simulating user interaction ===")
	# Build the visualizer directly (we can't instantiate the full MainRunner
	# in headless mode because it uses _input and viewport size).
	var viz := GraphVisualizer.new()
	add_child(viz)
	# Initialize with XOR.
	var cfg := _make_xor_config()
	var pop := Population.new(cfg)
	pop.initialize()
	# Evaluate initial population.
	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	evaluator.num_threads = 0
	var fitnesses := evaluator.evaluate_all(pop.genomes)
	for i in range(pop.genomes.size()):
		pop.genomes[i].fitness = fitnesses[i]
	viz.population = pop
	viz.refresh()
	print("  Initial: gen=%d, species=%d, pop=%d" % [pop.generation, pop.species_count(), pop.size()])

	# Simulate 10 generations of training.
	for gen in range(10):
		fitnesses = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
	viz.refresh()
	print("  After 10 gens: gen=%d, species=%d, best=%.3f" % [pop.generation, pop.species_count(), pop.best_fitness])

	# Navigate species forward.
	var n_species := pop.species_list.size()
	print("  Navigating species forward (%d species)..." % n_species)
	for i in range(mini(n_species, 5)):
		viz._next_species()
		viz.refresh()
		var sp := viz._current_species()
		assert(sp != null, "Species should not be null after navigation")
		print("    -> species %d (members=%d, best=%.3f)" % [sp.id, sp.members.size(), sp.best_fitness])

	# Navigate species backward.
	print("  Navigating species backward...")
	for i in range(mini(n_species, 3)):
		viz._prev_species()
		viz.refresh()
		var sp := viz._current_species()
		assert(sp != null, "Species should not be null after navigation")

	# Navigate genomes within current species.
	var cur_sp := viz._current_species()
	if cur_sp != null and cur_sp.members.size() > 1:
		print("  Navigating genomes in species %d (%d genomes)..." % [cur_sp.id, cur_sp.members.size()])
		for i in range(mini(cur_sp.members.size(), 5)):
			viz._next_genome()
			viz.refresh()
		for i in range(mini(cur_sp.members.size(), 3)):
			viz._prev_genome()
			viz.refresh()

	# Verify the graph view has a genome set.
	assert(viz._graph_view.genome != null, "Graph view should have a genome after navigation")
	print("  Graph view genome: %s" % viz._graph_view.genome)

	# Test stats are non-empty.
	assert(not viz._stats_label.text.is_empty(), "Stats label should not be empty")
	print("  Stats label length: %d chars" % viz._stats_label.text.length())

	# Switch to CartPole.
	print("  Switching to CartPole...")
	cfg = _make_cartpole_config()
	pop = Population.new(cfg)
	pop.initialize()
	evaluator = Evaluator.new(Callable(self, "_make_cartpole_env"), 600, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 0
	fitnesses = evaluator.evaluate_all(pop.genomes)
	for i in range(pop.genomes.size()):
		pop.genomes[i].fitness = fitnesses[i]
	viz.population = pop
	viz.refresh()
	print("  CartPole: gen=%d, species=%d, best=%.1f" % [pop.generation, pop.species_count(), fitnesses.max()])

	# Train CartPole for 3 generations.
	for gen in range(3):
		fitnesses = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
	viz.refresh()
	print("  CartPole after 3 gens: gen=%d, species=%d, best=%.1f" % [pop.generation, pop.species_count(), pop.best_fitness])

	# Navigate species in CartPole.
	var cp_species := pop.species_list.size()
	for i in range(mini(cp_species, 3)):
		viz._next_species()
		viz.refresh()

	# Switch to Acrobot.
	print("  Switching to Acrobot...")
	cfg = _make_acrobot_config()
	pop = Population.new(cfg)
	pop.initialize()
	evaluator = Evaluator.new(Callable(self, "_make_acrobot_env"), 600, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 0
	fitnesses = evaluator.evaluate_all(pop.genomes)
	for i in range(pop.genomes.size()):
		pop.genomes[i].fitness = fitnesses[i]
	viz.population = pop
	viz.refresh()
	print("  Acrobot: gen=%d, species=%d, best=%.3f" % [pop.generation, pop.species_count(), fitnesses.max()])

	# Train Acrobot for 2 generations.
	for gen in range(2):
		fitnesses = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
	viz.refresh()
	print("  Acrobot after 2 gens: gen=%d, species=%d, best=%.3f" % [pop.generation, pop.species_count(), pop.best_fitness])

	# Final navigation test.
	var ab_species := pop.species_list.size()
	for i in range(mini(ab_species, 3)):
		viz._next_species()
		viz.refresh()
	for i in range(mini(ab_species, 2)):
		viz._prev_genome()
		viz.refresh()

	print("\n=== test_gameplay: ALL PASSED ===")
	get_tree().quit()

func _make_xor_config() -> NeatConfig:
	var c := NeatConfig.new()
	c.num_inputs = 2
	c.num_outputs = 1
	c.use_bias = true
	c.output_activation = ActivationFunctions.Func.SIGMOID
	c.population_size = 50
	c.forward_mode = "topological"
	c.speciation_method = "standard"
	c.compatibility_threshold = 6.0
	c.target_species_count = 10
	c.generation_method = "asexual"
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
	return c

func _make_cartpole_config() -> NeatConfig:
	var c := NeatConfig.new()
	c.num_inputs = 4
	c.num_outputs = 1
	c.use_bias = true
	c.output_activation = ActivationFunctions.Func.TANH
	c.population_size = 30
	c.forward_mode = "topological"
	c.speciation_method = "standard"
	c.compatibility_threshold = 6.0
	c.target_species_count = 10
	c.generation_method = "asexual"
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
	return c

func _make_acrobot_config() -> NeatConfig:
	var c := NeatConfig.new()
	c.num_inputs = 6
	c.num_outputs = 1
	c.use_bias = true
	c.output_activation = ActivationFunctions.Func.TANH
	c.population_size = 30
	c.forward_mode = "topological"
	c.speciation_method = "standard"
	c.compatibility_threshold = 6.0
	c.target_species_count = 10
	c.generation_method = "asexual"
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
	return c

func _make_xor_env() -> XorEnvironment:
	return XorEnvironment.new([0, 1], 2, 3)

func _make_cartpole_env() -> CartPoleEnvironment:
	return CartPoleEnvironment.new([0, 1, 2, 3], 4, 5, 500)

func _make_acrobot_env() -> AcrobotEnvironment:
	return AcrobotEnvironment.new([0, 1, 2, 3, 4, 5], 6, 7, 500)
