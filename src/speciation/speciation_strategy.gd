## Assigns genomes to species using some clustering strategy.
##
## Implementations:
##   - [Single]:   all genomes in one species (testing purposes).
##   - [KMedian]:  K-median clustering. Slow but explicit; matches new species
##                 with similar old species and transfers info.
##   - [Standard]: classic NEAT speciation with adaptive threshold, parent-species
##                 first-match optimization, and species merging when too many.
##   - [Purge]:    first-generation only: keeps only the best genome, fills the
##                 species with mutated copies, then computes an ideal similarity
##                 rate that would let all those genomes coexist in one species.
##                 After the first generation, delegates to [Standard].
class_name SpeciationStrategy
extends RefCounted

## Assign [param genomes] to species. [param prev_species] is the previous
## generation's species list (may be empty on the first generation).
## Returns the new species list. Each genome in [param genomes] must end up
## in exactly one species (or be discarded, but in practice all should be assigned).
func speciate(genomes: Array, prev_species: Array, similarity: SimilarityTest, ctx: MutationContext) -> Array:
	return []


class Single:
	extends SpeciationStrategy

	func speciate(genomes: Array, prev_species: Array, _similarity: SimilarityTest, _ctx: MutationContext) -> Array:
		var sp: Species
		if prev_species.is_empty():
			sp = Species.new(0)
		else:
			sp = prev_species[0]
			sp.clear_members()
		for g: Genome in genomes:
			sp.add_member(g)
		# Representative: first member.
		if sp.members.size() > 0:
			sp.representative = sp.members[0]
		return [sp]


class Standard:
	extends SpeciationStrategy
	# Initial compatibility threshold.
	var compatibility_threshold: float = 3.0
	# Target species count. Threshold adapts to drive the count toward this.
	var target_species_count: int = 10
	# Hard cap on species count; above this, similar species are merged.
	var max_species_count: int = 20
	# Threshold adjustment factor per generation.
	var threshold_adjustment_factor: float = 0.3
	# Species whose representative is within this fraction of the threshold are
	# considered "too similar" and may be merged.
	var merge_ratio: float = 0.5
	# Internal: next species id to allocate.
	var _next_species_id: int = 0

	func _init(p_threshold: float = 3.0, p_target: int = 10) -> void:
		compatibility_threshold = p_threshold
		target_species_count = p_target

	func speciate(genomes: Array, prev_species: Array, similarity: SimilarityTest, ctx: MutationContext) -> Array:
		# Reset prev species members; keep representatives.
		var species_list: Array = []
		for sp: Species in prev_species:
			sp.clear_members()
			species_list.append(sp)
		# Determine next species id.
		_next_species_id = 0
		for sp: Species in species_list:
			if sp.id >= _next_species_id:
				_next_species_id = sp.id + 1
		# Assign each genome to a species.
		for g: Genome in genomes:
			var assigned: bool = false
			# Try parent's species first (optimization).
			if g.parent_species_id >= 0:
				for sp: Species in species_list:
					if sp.id == g.parent_species_id and sp.representative != null:
						var d: float = similarity.distance(g, sp.representative)
						if d < compatibility_threshold:
							sp.add_member(g)
							assigned = true
							break
			# Try other species.
			if not assigned:
				for sp: Species in species_list:
					if sp.representative == null:
						continue
					var d: float = similarity.distance(g, sp.representative)
					if d < compatibility_threshold:
						sp.add_member(g)
						assigned = true
						break
			# No match: create new species.
			if not assigned:
				var new_sp := Species.new(_next_species_id)
				_next_species_id += 1
				new_sp.representative = g
				new_sp.add_member(g)
				species_list.append(new_sp)
		# Remove empty species.
		var non_empty: Array = []
		for sp: Species in species_list:
			if sp.members.size() > 0:
				non_empty.append(sp)
		# Update representatives to a random member (best practice: keep previous
		# rep if still in the species; else pick the first member).
		for sp: Species in non_empty:
			if sp.representative == null or not sp.members.has(sp.representative):
				sp.representative = sp.members[0]
		# Adaptive threshold: drive species count toward target.
		var count := non_empty.size()
		if count > target_species_count:
			compatibility_threshold += threshold_adjustment_factor
		elif count < target_species_count:
			compatibility_threshold = maxf(0.1, compatibility_threshold - threshold_adjustment_factor)
		# Merge if too many species.
		if count > max_species_count:
			_merge_similar(non_empty, similarity)
		return non_empty

	func _merge_similar(species_list: Array, similarity: SimilarityTest) -> void:
		# Sort by id for determinism.
		species_list.sort_custom(func(a, b): return a.id < b.id)
		var merge_threshold := compatibility_threshold * merge_ratio
		var i := 0
		while i < species_list.size():
			var j := i + 1
			while j < species_list.size():
				var sp_a: Species = species_list[i]
				var sp_b: Species = species_list[j]
				if sp_a.representative != null and sp_b.representative != null:
					var d: float = similarity.distance(sp_a.representative, sp_b.representative)
					if d < merge_threshold:
						# Merge sp_b into sp_a.
						for g: Genome in sp_b.members:
							sp_a.add_member(g)
						species_list.remove_at(j)
						continue
				j += 1
			i += 1


class KMedian:
	extends SpeciationStrategy
	# K-median clustering. Pick K medioids, assign each genome to nearest
	# medioid, recompute medioids as the member with min total distance to
	# others. Iterate.
	# Very slow: O(K * N * iterations) similarity computations.

	var k: int = 5
	var iterations: int = 5
	var _next_species_id: int = 0

	func _init(p_k: int = 5, p_iterations: int = 5) -> void:
		k = p_k
		iterations = p_iterations

	func speciate(genomes: Array, prev_species: Array, similarity: SimilarityTest, ctx: MutationContext) -> Array:
		if genomes.is_empty():
			return []
		_next_species_id = 0
		for sp: Species in prev_species:
			if sp.id >= _next_species_id:
				_next_species_id = sp.id + 1
		var n := genomes.size()
		var kk := mini(k, n)
		# Initialize medioids: pick K random genomes.
		var indices := range(n)
		indices.shuffle()
		var medioid_idx: Array[int] = []
		for i in range(kk):
			medioid_idx.append(indices[i])
		# Iterate.
		var assignment: Array[int] = []
		assignment.resize(n)
		for _iter in range(iterations):
			# Assign each genome to nearest medioid.
			for i in range(n):
				var best_m := 0
				var best_d: float = 1e9
				for m_idx in range(medioid_idx.size()):
					var d: float = similarity.distance(genomes[i], genomes[medioid_idx[m_idx]])
					if d < best_d:
						best_d = d
						best_m = m_idx
				assignment[i] = best_m
			# Recompute medioids.
			for m_idx in range(medioid_idx.size()):
				# Find members of this cluster.
				var members: Array[int] = []
				for i in range(n):
					if assignment[i] == m_idx:
						members.append(i)
				if members.is_empty():
					continue
				# Find the member with min total distance to others.
				var best_member := members[0]
				var best_total: float = 1e9
				for cand in members:
					var total: float = 0.0
					for other in members:
						if cand == other:
							continue
						total += similarity.distance(genomes[cand], genomes[other])
					if total < best_total:
						best_total = total
						best_member = cand
				medioid_idx[m_idx] = best_member
		# Build species from final assignment.
		# Try to match new clusters with old species by similarity of medioids.
		var species_list: Array = []
		for m_idx in range(medioid_idx.size()):
			var sp := Species.new(_next_species_id)
			_next_species_id += 1
			# Try to match with a previous species.
			var best_old: Species = null
			var best_old_d: float = 1e9
			for old_sp: Species in prev_species:
				if old_sp.representative == null:
					continue
				var d: float = similarity.distance(genomes[medioid_idx[m_idx]], old_sp.representative)
				if d < best_old_d:
					best_old_d = d
					best_old = old_sp
			if best_old != null:
				# Transfer info.
				sp.id = best_old.id
				sp.best_fitness = best_old.best_fitness
				sp.best_fitness_history = best_old.best_fitness_history.duplicate()
				sp.staleness = best_old.staleness
				sp.selection_counts = best_old.selection_counts.duplicate()
				sp.node_selection_counts = best_old.node_selection_counts.duplicate()
				if _next_species_id <= sp.id:
					_next_species_id = sp.id + 1
			sp.representative = genomes[medioid_idx[m_idx]]
			species_list.append(sp)
		# Assign genomes.
		for i in range(n):
			(species_list[assignment[i]] as Species).add_member(genomes[i])
		# Remove empty species.
		var non_empty: Array = []
		for sp: Species in species_list:
			if sp.members.size() > 0:
				non_empty.append(sp)
		return non_empty


class Purge:
	extends SpeciationStrategy
	# First-generation behavior: keep only the best genome, fill the species
	# with mutated copies, compute ideal similarity rate.
	# Subsequent generations: delegate to Standard.

	var standard: Standard = null
	var first_generation: bool = true
	var mutation_policy: MutationPolicy = null
	var ideal_threshold: float = 3.0

	func _init(p_mutation_policy: MutationPolicy = null, p_standard: Standard = null) -> void:
		mutation_policy = p_mutation_policy
		standard = p_standard if p_standard != null else Standard.new()

	func speciate(genomes: Array, prev_species: Array, similarity: SimilarityTest, ctx: MutationContext) -> Array:
		if not first_generation:
			return standard.speciate(genomes, prev_species, similarity, ctx)
		first_generation = false
		# Find best genome.
		var best: Genome = genomes[0]
		for g: Genome in genomes:
			if g.fitness > best.fitness:
				best = g
		# Replace every other genome with a mutated clone of the best.
		for i in range(genomes.size()):
			var clone := best.duplicate()
			if mutation_policy != null:
				mutation_policy.apply(clone, ctx)
			genomes[i] = clone
		# Compute ideal similarity: the threshold needed so all genomes stay in one species.
		# Find the max distance between any two genomes.
		var max_d: float = 0.0
		for i in range(genomes.size()):
			for j in range(i + 1, genomes.size()):
				var d: float = similarity.distance(genomes[i], genomes[j])
				if d > max_d:
					max_d = d
		ideal_threshold = max_d + 0.1
		standard.compatibility_threshold = ideal_threshold
		# Put all in one species.
		var sp := Species.new(0)
		for g: Genome in genomes:
			sp.add_member(g)
		sp.representative = genomes[0]
		return [sp]
