extends Node
## Quick perf test to find the bottleneck.
## Run with: godot --headless --path . res://tests/test_perf.tscn

func _ready() -> void:
	print("=== test_perf ===")
	var cfg := NeatConfig.new()
	cfg.num_inputs = 2
	cfg.num_outputs = 1
	cfg.use_bias = true
	cfg.population_size = 150
	cfg.forward_mode = "topological"
	cfg.speciation_method = "standard"
	cfg.compatibility_threshold = 3.0
	cfg.generation_method = "asexual"

	var t0 := Time.get_ticks_msec()
	var pop := Population.new(cfg)
	pop.initialize()
	var t1 := Time.get_ticks_msec()
	print("  init: %d ms (species=%d)" % [t1 - t0, pop.species_count()])

	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	evaluator.num_threads = 0

	var t2 := Time.get_ticks_msec()
	var fitnesses := evaluator.evaluate_all(pop.genomes)
	var t3 := Time.get_ticks_msec()
	print("  eval: %d ms (best=%.3f)" % [t3 - t2, fitnesses.max()])

	for i in range(pop.genomes.size()):
		pop.genomes[i].fitness = fitnesses[i]
		if fitnesses[i] > pop.best_fitness:
			pop.best_fitness = fitnesses[i]
			pop.best_genome = pop.genomes[i].duplicate()

	var t4 := Time.get_ticks_msec()
	pop.evolve()
	var t5 := Time.get_ticks_msec()
	print("  evolve: %d ms (species=%d, pop=%d)" % [t5 - t4, pop.species_count(), pop.size()])

	# Run 9 more generations.
	for gen in range(9):
		t0 = Time.get_ticks_msec()
		fitnesses = evaluator.evaluate_all(pop.genomes)
		t1 = Time.get_ticks_msec()
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
		t2 = Time.get_ticks_msec()
		print("  gen %d: eval=%dms evolve=%dms species=%d pop=%d" % [gen + 1, t1 - t0, t2 - t1, pop.species_count(), pop.size()])

	print("\n=== test_perf: DONE ===")
	get_tree().quit()

func _make_xor_env() -> XorEnvironment:
	return XorEnvironment.new([0, 1], 2, 3)
