extends Node
## Comprehensive end-to-end test: exercises every strategy and config combination.
## Run with: godot --headless --path . res://tests/test_e2e.tscn

var tracker: InnovationTracker
var rng: RandomNumberGenerator
var ctx: MutationContext

func _ready() -> void:
	print("=== test_e2e: comprehensive end-to-end ===")
	tracker = InnovationTracker.new()
	for i in range(4):
		tracker.reserve_node_id(i)
	rng = RandomNumberGenerator.new()
	rng.seed = 42
	ctx = MutationContext.new(rng, tracker, null)
	ctx.forward_mode = "topological"
	ctx.forbid_loops = true

	_test_all_activation_functions()
	_test_all_randomization_methods()
	_test_all_weight_selectors()
	_test_all_weight_mutators()
	_test_all_connection_selectors()
	_test_all_connection_mutators()
	_test_all_neuron_selectors()
	_test_all_prune_selectors()
	_test_all_prune_mutators()
	_test_all_neuron_crossovers()
	_test_all_overall_crossovers()
	_test_all_similarity_tests()
	_test_all_speciation_strategies()
	_test_all_evaluation_strategies()
	_test_all_generation_strategies()
	_test_all_mutation_policies()
	_test_forward_modes_match()
	_test_loop_prevention()
	_test_xor_with_crossover()
	_test_xor_with_mixed_generation()
	_test_xor_with_phased_pruning()
	_test_xor_with_improvement_rate()
	_test_xor_with_novelty()
	_test_cartpole_quick()
	_test_acrobot_quick()
	_test_parallel_vs_serial()

	print("\n=== test_e2e: ALL PASSED ===")
	get_tree().quit()

# --- Activation functions ---

func _test_all_activation_functions() -> void:
	for f in ActivationFunctions.all_ids():
		var v: float = ActivationFunctions.activate(f, 0.5)
		assert(not is_nan(v), "Activation %d returned NaN" % f)
		var v2: float = ActivationFunctions.activate(f, -0.5)
		assert(not is_nan(v2), "Activation %d returned NaN for negative input" % f)
		# Name round-trip.
		var n := ActivationFunctions.name_of(f)
		assert(ActivationFunctions.from_name(n) == f, "Activation name round-trip failed for %d" % f)
	print("  activation functions: OK")

# --- Randomization methods ---

func _test_all_randomization_methods() -> void:
	var items := [0, 1, 2, 3, 4]
	var values := [1.0, 2.0, 3.0, 4.0, 5.0]
	for method in ["gaussian", "triangular", "roulette", "inverse_roulette", "uniform"]:
		var picked: Variant = RandomSelectors.select(method, items, values, rng)
		assert(picked != null, "Method %s returned null" % method)
		assert(items.has(picked), "Method %s returned invalid item" % method)
	print("  randomization methods: OK")

# --- Weight selectors ---

func _test_all_weight_selectors() -> void:
	var g := _build_starter_genome()
	var ws1 := WeightSelector.Standard.new(1, 0.5)
	var out1: Array = ws1.select(g, ctx)
	assert(not out1.is_empty(), "Standard weight selector returned empty")
	var g2 := _build_starter_genome()
	for c: ConnectionGene in g2.connections.values():
		c.weight = 3.0
	var ws2 := WeightSelector.Capped.new(1, 0.5, -3.0, 3.0)
	var out2: Array = ws2.select(g2, ctx)
	assert(not out2.is_empty(), "Capped weight selector returned empty")
	print("  weight selectors: OK")

# --- Weight mutators ---

func _test_all_weight_mutators() -> void:
	var g := _build_starter_genome()
	var c: ConnectionGene = g.connections.values()[0]
	var w_before: float = c.weight
	var wm1 := WeightMutator.Standard.new(-0.5, 0.5)
	wm1.mutate(c, ctx)
	assert(absf(c.weight - w_before) < 1.0, "Standard weight mutator changed weight too much")
	# Normal.
	var c2: ConnectionGene = g.connections.values()[1]
	var w_before2: float = c2.weight
	var wm2 := WeightMutator.Normal.new(0.0, 0.5)
	wm2.mutate(c2, ctx)
	# Should have changed (with high probability).
	assert(not is_nan(c2.weight), "Normal weight mutator produced NaN")
	print("  weight mutators: OK")

# --- Connection selectors ---

func _test_all_connection_selectors() -> void:
	# Need a genome with hidden nodes for connection candidates.
	var g := _build_starter_genome()
	var nm := NeuronMutator.Standard.new(ActivationFunctions.Func.RELU)
	var ns := NeuronSelector.Standard.new(1, 1.0)
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.neuron_selector = ns
	pol.neuron_mutator = nm
	pol.apply(g, ctx)
	for cs_class in [ConnectionSelector.Standard, ConnectionSelector.LeastUsed, ConnectionSelector.LeastCommon]:
		var cs: ConnectionSelector = cs_class.new(1, 0.5)
		var out: Array = cs.select(g, ctx)
		# May be empty if no candidates, but shouldn't crash.
		pass
	print("  connection selectors: OK")

# --- Connection mutators ---

func _test_all_connection_mutators() -> void:
	var g := _build_starter_genome()
	# Add hidden node for connection opportunities.
	var nm := NeuronMutator.Standard.new(ActivationFunctions.Func.RELU)
	var ns := NeuronSelector.Standard.new(1, 1.0)
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.neuron_selector = ns
	pol.neuron_mutator = nm
	pol.apply(g, ctx)
	var candidates := g.candidate_new_connections(false)
	if not candidates.is_empty():
		var pair: Vector2i = candidates[0]
		# Standard.
		var g1 := g.duplicate()
		var cm1 := ConnectionMutator.Standard.new(-1.0, 1.0)
		cm1.mutate(g1, [pair], ctx)
		# Normal.
		var g2 := g.duplicate()
		var cm2 := ConnectionMutator.Normal.new(0.0, 0.5)
		cm2.mutate(g2, [pair], ctx)
		# SafeGradient (no callback - uses probe).
		var g3 := g.duplicate()
		var cm3 := ConnectionMutator.SafeGradient.new()
		cm3.mutate(g3, [pair], ctx)
	print("  connection mutators: OK")

# --- Neuron selectors ---

func _test_all_neuron_selectors() -> void:
	var g := _build_starter_genome()
	for ns_class in [NeuronSelector.Standard, NeuronSelector.LeastCommon]:
		var ns: NeuronSelector = ns_class.new(1, 0.5)
		var out: Array = ns.select(g, ctx)
		# May be empty if no enabled connections.
		pass
	print("  neuron selectors: OK")

# --- Prune selectors ---

func _test_all_prune_selectors() -> void:
	var g := _build_starter_genome()
	for ps_class in [PruneSelector.Standard, PruneSelector.LeastWeight]:
		var ps: PruneSelector = ps_class.new(1, 0.5)
		var out: Array = ps.select(g, ctx)
		assert(not out.is_empty(), "Prune selector returned empty")
	print("  prune selectors: OK")

# --- Prune mutators ---

func _test_all_prune_mutators() -> void:
	# PruneDisabled.
	var g1 := _build_starter_genome()
	for c: ConnectionGene in g1.connections.values():
		c.enabled = false
	g1.mark_dirty()
	var pm1 := PruneMutator.PruneDisabled.new()
	var out1: Array[int] = pm1.mutate(g1, g1.connections.values(), ctx)
	assert(out1.size() > 0, "PruneDisabled should remove disabled connections")
	# PruneNonEssential.
	var g2 := _build_starter_genome()
	var pm2 := PruneMutator.PruneNonEssential.new()
	var out2: Array[int] = pm2.mutate(g2, g2.connections.values(), ctx)
	# Should not prune essential connections (those feeding outputs).
	# MergePair.
	var g3 := _build_starter_genome()
	# Add a hidden neuron with 1 in, 1 out (chain).
	var extra := tracker.new_node_id()
	g3.add_node(NodeGene.new(extra, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov_in := tracker.get_connection_innov(0, extra)
	g3.add_connection(ConnectionGene.new(innov_in, 0, extra, 0.5))
	var innov_out := tracker.get_connection_innov(extra, 3)
	g3.add_connection(ConnectionGene.new(innov_out, extra, 3, 0.7))
	var pm3 := PruneMutator.MergePair.new()
	var out3: Array[int] = pm3.mutate(g3, [g3.connections[innov_in]], ctx)
	# Should have merged the chain.
	print("  prune mutators: OK")

# --- Neuron crossovers ---

func _test_all_neuron_crossovers() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	for c: ConnectionGene in b.connections.values():
		c.weight = 9.9
	a.fitness = 2.0
	b.fitness = 1.0
	for nc_class in [NeuronCrossover.Standard, NeuronCrossover.Average, NeuronCrossover.BiasedAverage]:
		var nc: NeuronCrossover = nc_class.new() if nc_class != NeuronCrossover.BiasedAverage else nc_class.new(0.5)
		var oc := OverallCrossover.Fitter.new(nc)
		var child := oc.crossover(a, b, ctx)
		assert(child.connection_count() == 3, "Neuron crossover should preserve connection count")
	# StandardAll.
	var nc4 := NeuronCrossover.StandardAll.new()
	var oc4 := OverallCrossover.Fitter.new(nc4)
	var child4 := oc4.crossover(a, b, ctx)
	assert(child4.connection_count() == 3, "StandardAll should preserve connection count")
	print("  neuron crossovers: OK")

# --- Overall crossovers ---

func _test_all_overall_crossovers() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	# Add disjoints to both.
	var extra_a := tracker.new_node_id()
	a.add_node(NodeGene.new(extra_a, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov_a := tracker.get_connection_innov(0, extra_a)
	a.add_connection(ConnectionGene.new(innov_a, 0, extra_a, 0.4))
	var extra_b := tracker.new_node_id()
	b.add_node(NodeGene.new(extra_b, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
	var innov_b := tracker.get_connection_innov(1, extra_b)
	b.add_connection(ConnectionGene.new(innov_b, 1, extra_b, 0.5))
	a.fitness = 2.0
	b.fitness = 1.0
	var nc := NeuronCrossover.Standard.new()
	for oc_class in [OverallCrossover.Fitter, OverallCrossover.Bigger, OverallCrossover.Combine, OverallCrossover.Excluded]:
		var oc: OverallCrossover = oc_class.new(nc)
		var child := oc.crossover(a, b, ctx)
		assert(child.node_count() >= 4, "Overall crossover should preserve at least the shared nodes")
		assert(not child.has_loop(), "Overall crossover should not create loops")
	print("  overall crossovers: OK")

# --- Similarity tests ---

func _test_all_similarity_tests() -> void:
	var a := _build_starter_genome()
	var b := _build_starter_genome()
	for sim_class in [SimilarityTest.Standard, SimilarityTest.Percentage]:
		var sim: SimilarityTest = sim_class.new()
		var d: float = sim.distance(a, b)
		assert(d >= 0.0, "Similarity distance should be non-negative")
		assert(not is_nan(d), "Similarity distance should not be NaN")
	print("  similarity tests: OK")

# --- Speciation strategies ---

func _test_all_speciation_strategies() -> void:
	var genomes: Array = []
	for i in range(20):
		var g := _build_starter_genome()
		# Add some diversity.
		if i % 3 == 0:
			var extra := tracker.new_node_id()
			g.add_node(NodeGene.new(extra, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
			var innov := tracker.get_connection_innov(0, extra)
			g.add_connection(ConnectionGene.new(innov, 0, extra, 0.5))
		genomes.append(g)
	var sim := SimilarityTest.Standard.new()
	for sp_class in [SpeciationStrategy.Single, SpeciationStrategy.Standard]:
		var sp: SpeciationStrategy = sp_class.new()
		var species: Array = sp.speciate(genomes.duplicate(true), [], sim, ctx)
		assert(not species.is_empty(), "Speciation should produce at least 1 species")
	# KMedian.
	var km := SpeciationStrategy.KMedian.new(3, 3)
	var species_km: Array = km.speciate(genomes.duplicate(true), [], sim, ctx)
	assert(species_km.size() <= 3, "KMedian with k=3 should produce <= 3 species")
	# Purge.
	for g: Genome in genomes:
		g.fitness = rng.randf()
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.weight_selector = WeightSelector.Standard.new(1, 1.0)
	pol.weight_mutator = WeightMutator.Standard.new(-0.5, 0.5)
	var purge := SpeciationStrategy.Purge.new(pol)
	var species_purge: Array = purge.speciate(genomes.duplicate(true), [], sim, ctx)
	assert(species_purge.size() == 1, "Purge first-gen should produce 1 species")
	print("  speciation strategies: OK")

# --- Evaluation strategies ---

func _test_all_evaluation_strategies() -> void:
	var species_list: Array = []
	for i in range(3):
		var sp := Species.new(i)
		for j in range(5):
			var g := _build_starter_genome()
			g.fitness = float(j) * 0.1 + float(i) * 0.5
			sp.add_member(g)
		sp.record_generation_stats()
		species_list.append(sp)
	var sim := SimilarityTest.Standard.new()
	for ev_class in [EvaluationStrategy.Equal, EvaluationStrategy.ImprovementRate]:
		var ev: EvaluationStrategy = ev_class.new()
		ev.evaluate(species_list.duplicate(true), 30, ctx)
	# Novelty.
	var ev_n := EvaluationStrategy.Novelty.new(sim, 1.0)
	ev_n.evaluate(species_list.duplicate(true), 30, ctx)
	# Check totals.
	for ev_class in [EvaluationStrategy.Equal, EvaluationStrategy.ImprovementRate]:
		var ev: EvaluationStrategy = ev_class.new()
		var sp_copy: Array = species_list.duplicate(true)
		ev.evaluate(sp_copy, 30, ctx)
		var total: int = 0
		for sp: Species in sp_copy:
			total += sp.allocated_children
		assert(total == 30, "Total allocated should be 30, got %d" % total)
	print("  evaluation strategies: OK")

# --- Generation strategies ---

func _test_all_generation_strategies() -> void:
	var species_list: Array = []
	for i in range(2):
		var sp := Species.new(i)
		sp.allocated_children = 10
		for j in range(5):
			var g := _build_starter_genome()
			g.fitness = float(j) * 0.1
			sp.add_member(g)
		species_list.append(sp)
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.weight_selector = WeightSelector.Standard.new(1, 0.5)
	pol.weight_mutator = WeightMutator.Standard.new(-0.5, 0.5)
	pol.connection_selector = ConnectionSelector.Standard.new(0, 0.3)
	pol.connection_mutator = ConnectionMutator.Standard.new(-1.0, 1.0)
	pol.neuron_selector = NeuronSelector.Standard.new(0, 0.2)
	pol.neuron_mutator = NeuronMutator.Standard.new(ActivationFunctions.Func.RELU)
	# Asexual.
	var gs1 := GenerationStrategy.Asexual.new(pol)
	var children1: Array = gs1.produce(species_list.duplicate(true), ctx)
	assert(children1.size() == 20, "Asexual should produce 20 children, got %d" % children1.size())
	# Crossover.
	var nc := NeuronCrossover.Standard.new()
	var oc := OverallCrossover.Fitter.new(nc)
	var gs2 := GenerationStrategy.Crossover.new(pol, oc)
	var children2: Array = gs2.produce(species_list.duplicate(true), ctx)
	assert(children2.size() == 20, "Crossover should produce 20 children, got %d" % children2.size())
	# Mixed.
	var gs3 := GenerationStrategy.Mixed.new(pol, oc, 0.5)
	var children3: Array = gs3.produce(species_list.duplicate(true), ctx)
	assert(children3.size() == 20, "Mixed should produce 20 children, got %d" % children3.size())
	print("  generation strategies: OK")

# --- Mutation policies ---

func _test_all_mutation_policies() -> void:
	var g := _build_starter_genome()
	var pol_general := MutationPolicy.General.new(true, 1.0)
	pol_general.weight_selector = WeightSelector.Standard.new(1, 0.5)
	pol_general.weight_mutator = WeightMutator.Standard.new(-0.5, 0.5)
	pol_general.apply(g, ctx)
	assert(not g.has_loop(), "General policy should not create loops")
	# Phased.
	var g2 := _build_starter_genome()
	var pol_phased := MutationPolicy.PhasedPruning.new(2, 5.0)
	pol_phased.weight_selector = WeightSelector.Standard.new(1, 1.0)
	pol_phased.weight_mutator = WeightMutator.Standard.new(-0.5, 0.5)
	pol_phased.prune_selector = PruneSelector.Standard.new(1, 0.5)
	pol_phased.prune_mutator = PruneMutator.new()
	# Growth phase.
	pol_phased.apply(g2, ctx)
	# Advance to pruning phase.
	pol_phased.advance_generation()
	pol_phased.advance_generation()
	pol_phased.apply(g2, ctx)
	print("  mutation policies: OK")

# --- Forward modes match ---

func _test_forward_modes_match() -> void:
	# For feedforward graphs, topological and timestep should give same result.
	var g := _build_starter_genome()
	var out_topo: Dictionary = g.forward({0: 1.0, 1: 0.5}, "topological")
	var out_ts: Dictionary = g.forward({0: 1.0, 1: 0.5}, "timestep", 8)
	for k in out_topo.keys():
		var diff: float = absf(float(out_topo[k]) - float(out_ts[k]))
		assert(diff < 1e-4, "Topo and timestep should match for feedforward, diff=%f" % diff)
	print("  forward modes match: OK")

# --- Loop prevention ---

func _test_loop_prevention() -> void:
	var g := _build_starter_genome()
	# With forbid_loops=true, connection mutations should never create loops.
	var pol := MutationPolicy.General.new(true, 1.0)
	pol.connection_selector = ConnectionSelector.Standard.new(1, 1.0, true)
	pol.connection_mutator = ConnectionMutator.Standard.new(-1.0, 1.0)
	pol.neuron_selector = NeuronSelector.Standard.new(1, 1.0)
	pol.neuron_mutator = NeuronMutator.Standard.new(ActivationFunctions.Func.RELU)
	for _i in range(20):
		pol.apply(g, ctx)
	assert(not g.has_loop(), "After 20 mutations with forbid_loops, no loop should exist")
	print("  loop prevention: OK")

# --- XOR with crossover ---

func _test_xor_with_crossover() -> void:
	var cfg := _make_xor_config()
	cfg.generation_method = "crossover"
	cfg.overall_crossover_method = "combine"
	cfg.neuron_crossover_method = "average"
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	for _i in range(5):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
	assert(pop.size() == cfg.population_size, "XOR+crossover: pop size stable")
	print("  xor with crossover: OK")

# --- XOR with mixed generation ---

func _test_xor_with_mixed_generation() -> void:
	var cfg := _make_xor_config()
	cfg.generation_method = "mixed"
	cfg.crossover_rate = 0.5
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	for _i in range(5):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
	assert(pop.size() == cfg.population_size, "XOR+mixed: pop size stable")
	print("  xor with mixed generation: OK")

# --- XOR with phased pruning ---

func _test_xor_with_phased_pruning() -> void:
	var cfg := _make_xor_config()
	cfg.mutation_policy_method = "phased_pruning"
	cfg.enable_prune_mutation = true
	cfg.prune_mutation_rate = 0.1
	cfg.prune_mutation_min = 0
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	for _i in range(5):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
	assert(pop.size() == cfg.population_size, "XOR+phased: pop size stable")
	print("  xor with phased pruning: OK")

# --- XOR with improvement rate ---

func _test_xor_with_improvement_rate() -> void:
	var cfg := _make_xor_config()
	cfg.evaluation_method = "improvement_rate"
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	for _i in range(5):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
	assert(pop.size() == cfg.population_size, "XOR+improvement: pop size stable")
	print("  xor with improvement rate: OK")

# --- XOR with novelty ---

func _test_xor_with_novelty() -> void:
	var cfg := _make_xor_config()
	cfg.evaluation_method = "novelty"
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	for _i in range(5):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
	assert(pop.size() == cfg.population_size, "XOR+novelty: pop size stable")
	print("  xor with novelty: OK")

# --- CartPole quick ---

func _test_cartpole_quick() -> void:
	var cfg := _make_cartpole_config()
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := Evaluator.new(Callable(self, "_make_cartpole_env"), 600, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 0
	for _i in range(3):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
	assert(pop.size() == cfg.population_size, "CartPole: pop size stable")
	print("  cartpole quick: OK")

# --- Acrobot quick ---

func _test_acrobot_quick() -> void:
	var cfg := _make_acrobot_config()
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator := Evaluator.new(Callable(self, "_make_acrobot_env"), 600, "topological")
	evaluator.episodes_per_genome = 1
	evaluator.num_threads = 0
	for _i in range(3):
		var fitnesses: Array[float] = evaluator.evaluate_all(pop.genomes)
		for i in range(pop.genomes.size()):
			pop.genomes[i].fitness = fitnesses[i]
		pop.evolve()
	assert(pop.size() == cfg.population_size, "Acrobot: pop size stable")
	print("  acrobot quick: OK")

# --- Parallel vs serial ---

func _test_parallel_vs_serial() -> void:
	var cfg := _make_xor_config()
	cfg.population_size = 50
	var pop := Population.new(cfg)
	pop.initialize()
	var evaluator_serial := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	evaluator_serial.num_threads = 0
	var evaluator_parallel := Evaluator.new(Callable(self, "_make_xor_env"), 100, "topological")
	evaluator_parallel.num_threads = 4
	var fit_serial: Array[float] = evaluator_serial.evaluate_all(pop.genomes)
	var fit_parallel: Array[float] = evaluator_parallel.evaluate_all(pop.genomes)
	# Should produce identical results (same genome, same env, no randomness in XOR env).
	for i in range(fit_serial.size()):
		assert(absf(fit_serial[i] - fit_parallel[i]) < 1e-3, "Parallel vs serial mismatch at %d" % i)
	print("  parallel vs serial: OK")

# --- Configs ---

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
	c.population_size = 30
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
	c.population_size = 30
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

# --- Helpers ---

func _build_starter_genome() -> Genome:
	var g := Genome.new()
	g.add_node(NodeGene.new(0, NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR))
	g.add_node(NodeGene.new(1, NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR))
	g.add_node(NodeGene.new(2, NodeGene.Kind.BIAS, ActivationFunctions.Func.LINEAR))
	g.add_node(NodeGene.new(3, NodeGene.Kind.OUTPUT, ActivationFunctions.Func.TANH))
	g.add_connection(ConnectionGene.new(tracker.get_connection_innov(0, 3), 0, 3, 0.5))
	g.add_connection(ConnectionGene.new(tracker.get_connection_innov(1, 3), 1, 3, -0.5))
	g.add_connection(ConnectionGene.new(tracker.get_connection_innov(2, 3), 2, 3, 0.3))
	return g
