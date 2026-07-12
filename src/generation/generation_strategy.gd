## Produces the next generation's genomes from the current species.
##
## Implementations:
##   - [Asexual]:  each child is a mutated clone of a parent chosen from its
##                 species (no crossover).
##   - [Crossover]: each child is the crossover of two parents chosen from the
##                 same species.
##   - [Mixed]:    each child is either asexual or crossover with probability
##                 [member crossover_rate].
##
## All three honour elitism (the top [member elite_count] genomes of each
## species are copied unchanged) and interspecies mating (with probability
## [member interspecies_rate], a crossover parent is chosen from a different
## species). Species with [member Species.allocated_children] <= 0 are skipped
## (they have been culled by the evaluation strategy).
class_name GenerationStrategy
extends RefCounted

# Number of top genomes per species copied unchanged into the next generation.
var elite_count: int = 1
# Probability of interspecies mating (crossover with a parent from another species).
var interspecies_rate: float = 0.001
# Randomization method used to pick parents within a species.
# One of "gaussian", "triangular", "roulette", "inverse_roulette", "uniform".
var selection_method: String = "roulette"
# Mutation policy applied to children (asexual or after crossover).
var mutation_policy: MutationPolicy = null
# Overall crossover strategy.
var overall_crossover: OverallCrossover = null

func _init(p_mutation_policy: MutationPolicy = null, p_overall_crossover: OverallCrossover = null) -> void:
		mutation_policy = p_mutation_policy
		overall_crossover = p_overall_crossover

## Produce the next generation's genomes.
## [param species_list] is the current generation's species (with allocated_children
## set by the evaluation strategy).
## [param ctx] provides RNG + tracker.
func produce(species_list: Array, ctx: MutationContext) -> Array:
		return []

# Pick a parent genome from a species using [member selection_method].
func _pick_parent(sp: Species, ctx: MutationContext) -> Genome:
		if sp.members.is_empty():
				return null
		var items: Array = sp.members
		var values: Array = []
		for g: Genome in sp.members:
				values.append(g.fitness)
		var picked: Variant = RandomSelectors.select(selection_method, items, values, ctx.rng)
		return picked

# Pick a parent genome from any species (for interspecies mating).
func _pick_parent_any_species(species_list: Array, ctx: MutationContext) -> Genome:
		# Build a flat list of all genomes.
		var all: Array = []
		for sp: Species in species_list:
				for g: Genome in sp.members:
						all.append(g)
		if all.is_empty():
				return null
		return all[ctx.rng.randi_range(0, all.size() - 1)]

# Sort species members by fitness descending.
func _sort_by_fitness(sp: Species) -> void:
		sp.members.sort_custom(func(a, b): return a.fitness > b.fitness)


class Asexual:
		extends GenerationStrategy

		func _init(p_mutation_policy: MutationPolicy = null) -> void:
				super(p_mutation_policy, null)

		func produce(species_list: Array, ctx: MutationContext) -> Array:
				var children: Array = []
				for sp: Species in species_list:
						if sp.allocated_children <= 0:
								continue
						_sort_by_fitness(sp)
						# Elitism: copy top elite_count unchanged.
						var elite_n := mini(elite_count, sp.members.size())
						for i in range(elite_n):
								children.append(sp.members[i].duplicate())
						# Fill remaining slots with mutated clones.
						var remaining := sp.allocated_children - elite_n
						for _i in range(maxi(0, remaining)):
								var parent := _pick_parent(sp, ctx)
								if parent == null:
										break
								var child := parent.duplicate()
								child.parent_species_id = sp.id
								child.fitness = 0.0
								child.adjusted_fitness = 0.0
								if mutation_policy != null:
										# Use species mutation rate multiplier.
										var old_mult := ctx.rate_multiplier
										ctx.rate_multiplier = sp.mutation_rate_multiplier
										mutation_policy.apply(child, ctx)
										ctx.rate_multiplier = old_mult
								children.append(child)
				return children


class Crossover:
		extends GenerationStrategy

		func _init(p_mutation_policy: MutationPolicy = null, p_overall_crossover: OverallCrossover = null) -> void:
				super(p_mutation_policy, p_overall_crossover)

		func produce(species_list: Array, ctx: MutationContext) -> Array:
				var children: Array = []
				for sp: Species in species_list:
						if sp.allocated_children <= 0:
								continue
						_sort_by_fitness(sp)
						var elite_n := mini(elite_count, sp.members.size())
						for i in range(elite_n):
								children.append(sp.members[i].duplicate())
						var remaining := sp.allocated_children - elite_n
						for _i in range(maxi(0, remaining)):
								var parent_a := _pick_parent(sp, ctx)
								var parent_b: Genome = null
								# Interspecies mating?
								if ctx.rng.randf() < interspecies_rate:
										parent_b = _pick_parent_any_species(species_list, ctx)
								else:
										parent_b = _pick_parent(sp, ctx)
								if parent_a == null or parent_b == null:
										break
								# Order parents by fitness (a is fitter).
								var fitter: Genome = parent_a if parent_a.fitness >= parent_b.fitness else parent_b
								var less_fit: Genome = parent_b if parent_a.fitness >= parent_b.fitness else parent_a
								var child: Genome
								if overall_crossover != null:
										child = overall_crossover.crossover(fitter, less_fit, ctx)
								else:
										child = fitter.duplicate()
								child.parent_species_id = sp.id
								child.fitness = 0.0
								child.adjusted_fitness = 0.0
								if mutation_policy != null:
										var old_mult := ctx.rate_multiplier
										ctx.rate_multiplier = sp.mutation_rate_multiplier
										mutation_policy.apply(child, ctx)
										ctx.rate_multiplier = old_mult
								children.append(child)
				return children


class Mixed:
		extends GenerationStrategy
		# Probability of using crossover (vs asexual reproduction) for each child.
		var crossover_rate: float = 0.5

		func _init(p_mutation_policy: MutationPolicy = null, p_overall_crossover: OverallCrossover = null, p_crossover_rate: float = 0.5) -> void:
				super(p_mutation_policy, p_overall_crossover)
				crossover_rate = p_crossover_rate

		func produce(species_list: Array, ctx: MutationContext) -> Array:
				var children: Array = []
				for sp: Species in species_list:
						if sp.allocated_children <= 0:
								continue
						_sort_by_fitness(sp)
						var elite_n := mini(elite_count, sp.members.size())
						for i in range(elite_n):
								children.append(sp.members[i].duplicate())
						var remaining := sp.allocated_children - elite_n
						for _i in range(maxi(0, remaining)):
								var use_crossover := ctx.rng.randf() < crossover_rate and sp.members.size() >= 2
								if use_crossover:
										var parent_a := _pick_parent(sp, ctx)
										var parent_b: Genome = null
										if ctx.rng.randf() < interspecies_rate:
												parent_b = _pick_parent_any_species(species_list, ctx)
										else:
												parent_b = _pick_parent(sp, ctx)
										if parent_a == null or parent_b == null:
												continue
										var fitter: Genome = parent_a if parent_a.fitness >= parent_b.fitness else parent_b
										var less_fit: Genome = parent_b if parent_a.fitness >= parent_b.fitness else parent_a
										var child: Genome
										if overall_crossover != null:
												child = overall_crossover.crossover(fitter, less_fit, ctx)
										else:
												child = fitter.duplicate()
										child.parent_species_id = sp.id
										if mutation_policy != null:
												var old_mult := ctx.rate_multiplier
												ctx.rate_multiplier = sp.mutation_rate_multiplier
												mutation_policy.apply(child, ctx)
												ctx.rate_multiplier = old_mult
										children.append(child)
								else:
										var parent := _pick_parent(sp, ctx)
										if parent == null:
												break
										var child := parent.duplicate()
										child.parent_species_id = sp.id
										child.fitness = 0.0
										child.adjusted_fitness = 0.0
										if mutation_policy != null:
												var old_mult := ctx.rate_multiplier
												ctx.rate_multiplier = sp.mutation_rate_multiplier
												mutation_policy.apply(child, ctx)
												ctx.rate_multiplier = old_mult
										children.append(child)
				return children
