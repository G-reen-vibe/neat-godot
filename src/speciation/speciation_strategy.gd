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
        # The compatibility threshold δ. Two genomes belong to the same species if
        # their compatibility distance < δ. This value is dynamically adjusted each
        # generation to drive the species count toward [member target_species_count].
        var compatibility_threshold: float = 3.0
        # Target number of species. The threshold adapts to drive species count
        # toward this value.
        var target_species_count: int = 10
        # Adjustment speed: how much to add/subtract from the threshold per
        # generation when species count is off target. (NEAT paper default: 0.3)
        var threshold_adjustment_speed: float = 0.3
        # Hard cap on species count; above this, similar species are merged.
        var max_species_count: int = 20
        # Species whose representative distance is below threshold * merge_ratio
        # are merged. Lower = more aggressive merging.
        var merge_ratio: float = 0.5
        # Min/max bounds for the threshold (prevents runaway).
        var min_threshold: float = 0.5
        var max_threshold: float = 15.0
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
                # Update representatives: keep the previous representative for stability
                # (standard NEAT practice). Only set a new one if the species is brand new.
                for sp: Species in non_empty:
                        if sp.representative == null:
                                sp.representative = sp.members[0]
                # Dynamic threshold adjustment (NEAT paper):
                # If we have more species than the target, increase δ to make speciation
                # stricter. If fewer, decrease δ to make it more permissive.
                # The adjustment is proportional to how far off we are, so it converges
                # quickly rather than creeping by a fixed amount each generation.
                var count := non_empty.size()
                if count > target_species_count:
                        # Adjust proportional to how far off we are (squared for faster convergence).
                        var ratio: float = float(count) / float(maxi(1, target_species_count))
                        compatibility_threshold += threshold_adjustment_speed * ratio * ratio
                elif count < target_species_count:
                        var ratio: float = float(maxi(1, target_species_count)) / float(maxi(1, count))
                        compatibility_threshold -= threshold_adjustment_speed * ratio * ratio
                compatibility_threshold = clampf(compatibility_threshold, min_threshold, max_threshold)
                # Merge if too many species (after threshold adjustment).
                if count > target_species_count:
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
        ## Purge speciation: on the first generation, keep only the top N genomes
        ## (where N = target_species_count), then duplicate each of them to fill
        ## the population. Each top genome becomes the representative of its own
        ## species. Compute the ideal compatibility threshold as the minimum
        ## pairwise distance between representatives (so each stays in its own
        ## species). Subsequent generations delegate to Standard with that threshold.
        ##
        ## This produces a stable N-species starting point with good genetic
        ## diversity (N distinct seeds) and a threshold calibrated to keep them
        ## separate.

        var standard: Standard = null
        var first_generation: bool = true
        var mutation_policy: MutationPolicy = null
        var ideal_threshold: float = 3.0
        var target_species_count: int = 10

        func _init(p_mutation_policy: MutationPolicy = null, p_standard: Standard = null, p_target: int = 10) -> void:
                mutation_policy = p_mutation_policy
                target_species_count = p_target
                standard = p_standard if p_standard != null else Standard.new()
                standard.target_species_count = p_target

        func speciate(genomes: Array, prev_species: Array, similarity: SimilarityTest, ctx: MutationContext) -> Array:
                if not first_generation:
                        return standard.speciate(genomes, prev_species, similarity, ctx)
                first_generation = false
                # Sort genomes by fitness descending.
                var sorted := genomes.duplicate()
                sorted.sort_custom(func(a, b): return a.fitness > b.fitness)
                # Pick the top N genomes as species seeds.
                var n: int = mini(target_species_count, sorted.size())
                var seeds: Array = sorted.slice(0, n)
                # Apply mutations to each seed so they diverge slightly.
                if mutation_policy != null:
                        for i in range(seeds.size()):
                                var clone := (seeds[i] as Genome).duplicate()
                                mutation_policy.apply(clone, ctx)
                                seeds[i] = clone
                # Fill the remaining population slots with mutated clones of the seeds,
                # round-robin. Each genome's parent_species_id is set to its seed index.
                var population_size: int = genomes.size()
                var new_genomes: Array = []
                for i in range(population_size):
                        var seed_idx: int = i % n
                        var seed: Genome = seeds[seed_idx]
                        var clone := seed.duplicate()
                        clone.parent_species_id = seed_idx
                        if mutation_policy != null:
                                mutation_policy.apply(clone, ctx)
                        new_genomes.append(clone)
                # Replace the genomes array contents in-place (so the caller sees the
                # new genomes).
                genomes.clear()
                for g in new_genomes:
                        genomes.append(g)
                # Compute the ideal threshold: we want a threshold that keeps the N
                # seed species separate but allows mutated offspring to stay with their
                # parent species. Use the average pairwise distance between seeds as
                # the threshold — this is large enough to absorb mutation drift while
                # keeping distinct seeds separate.
                var total_dist: float = 0.0
                var dist_count: int = 0
                var max_dist: float = 0.0
                for i in range(seeds.size()):
                        for j in range(i + 1, seeds.size()):
                                var d: float = similarity.distance(seeds[i], seeds[j])
                                total_dist += d
                                dist_count += 1
                                if d > max_dist:
                                        max_dist = d
                var avg_dist: float = total_dist / float(maxi(1, dist_count))
                if dist_count == 0:
                        # Only one seed; use a moderate threshold.
                        ideal_threshold = 3.0
                else:
                        # Threshold = avg_dist + buffer for mutation drift. Each generation,
                        # mutations add ~0-2 new genes (distance ~1-2 each). We want the
                        # threshold high enough to absorb several generations of drift before
                        # a genome is kicked out. Use avg_dist + 3.0 as a reasonable buffer.
                        ideal_threshold = avg_dist + 3.0
                standard.compatibility_threshold = ideal_threshold
                # Build species: assign each genome to its seed species (already set
                # via parent_species_id during fill).
                var species_list: Array = []
                for i in range(n):
                        var sp := Species.new(i)
                        sp.representative = (seeds[i] as Genome).duplicate()
                        species_list.append(sp)
                for g: Genome in genomes:
                        var sid: int = g.parent_species_id
                        if sid < 0 or sid >= species_list.size():
                                sid = 0
                        (species_list[sid] as Species).add_member(g)
                return species_list
