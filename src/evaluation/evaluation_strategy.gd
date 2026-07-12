## Scores each species for the purpose of allocating children in the next
## generation. Higher-scoring species get more children; lower-scoring species
## get a higher mutation rate (encouraging exploration); very-low-scoring
## species may be deleted.
##
## Implementations:
##   - [Equal]:          every species gets the same score (= its average fitness).
##   - [ImprovementRate]: species with higher recent improvement get higher scores.
##   - [Novelty]:        species with more novel behaviour get higher scores.
class_name EvaluationStrategy
extends RefCounted

## Compute the score for each species and update [member Species.allocated_children]
## and [member Species.mutation_rate_multiplier] accordingly.
## [param species_list] is the current generation's species (with stats already
## recorded via [method Species.record_generation_stats]).
## [param total_population] is the target population size for next generation.
func evaluate(species_list: Array, total_population: int, ctx: MutationContext) -> void:
        pass

## Default child allocation: proportional to species score * species size.
## Subclasses provide per-species scores via [method _score_species].
func _allocate_proportional(species_list: Array, scores: Array[float], total_population: int) -> void:
        var total_score: float = 0.0
        for s in scores:
                total_score += s
        if total_score < 1e-9:
                # Equal split fallback.
                var equal := maxi(1, total_population / maxi(1, species_list.size()))
                for sp: Species in species_list:
                        sp.allocated_children = equal
                return
        var allocated: int = 0
        for i in range(species_list.size()):
                var sp: Species = species_list[i]
                var share := int(round(scores[i] / total_score * float(total_population)))
                sp.allocated_children = maxi(1, share)
                allocated += sp.allocated_children
        # Adjust for rounding: add/subtract from the largest species.
        if allocated != total_population and not species_list.is_empty():
                var diff := total_population - allocated
                # Find the species with the most allocated.
                var biggest_idx := 0
                for i in range(1, species_list.size()):
                        if (species_list[i] as Species).allocated_children > (species_list[biggest_idx] as Species).allocated_children:
                                biggest_idx = i
                (species_list[biggest_idx] as Species).allocated_children += diff
                if (species_list[biggest_idx] as Species).allocated_children < 1:
                        (species_list[biggest_idx] as Species).allocated_children = 1

## Delete species (mark for removal) below this score threshold.
## Returns the updated species_list (without the deleted ones).
func _cull_low_species(species_list: Array, scores: Array[float], min_score: float) -> Array:
        var kept: Array = []
        for i in range(species_list.size()):
                if scores[i] >= min_score:
                        kept.append(species_list[i])
        return kept


class Equal:
        extends EvaluationStrategy
        # All species scored equally; children split evenly.

        func evaluate(species_list: Array, total_population: int, _ctx: MutationContext) -> void:
                if species_list.is_empty():
                        return
                # Reset all species first so stale allocations from previous generations
                # don't leak into species that are not receiving new children.
                for sp: Species in species_list:
                        sp.allocated_children = 0
                        sp.mutation_rate_multiplier = 1.0
                var n := species_list.size()
                # If we have more species than population slots, some species get 0 children.
                # Use floor division; the remainder is distributed one-per-species up to the
                # first (total_population % n) species.
                var per := maxi(0, total_population / n)
                var remainder := maxi(0, total_population) - per * n
                for i in range(n):
                        var sp: Species = species_list[i]
                        sp.allocated_children = per
                        if i < remainder:
                                sp.allocated_children += 1


class ImprovementRate:
        extends EvaluationStrategy
        # Score = current_avg_fitness * (1 + improvement_rate)
        # improvement_rate = (cur_avg - prev_avg) / (|prev_avg| + eps)
        # Species with higher improvement get a higher score.
        # Species with no improvement get penalized (and very stale species deleted).

        var min_score_for_survival: float = 0.01
        # Mutation rate adjustment: low-improvement species get higher mutation rate.
        var low_improvement_threshold: float = 0.0
        var low_improvement_mutation_multiplier: float = 2.0
        var high_improvement_mutation_multiplier: float = 0.5

        func evaluate(species_list: Array, total_population: int, _ctx: MutationContext) -> void:
                if species_list.is_empty():
                        return
                # Reset all species first so stale allocations from previous generations
                # don't leak into species that are culled or not receiving new children.
                for sp: Species in species_list:
                        sp.allocated_children = 0
                var scores: Array[float] = []
                scores.resize(species_list.size())
                for i in range(species_list.size()):
                        var sp: Species = species_list[i]
                        var cur_avg: float = sp.average_fitness
                        # Compare current AVERAGE to previous AVERAGE (not best) for a
                        # fair improvement-rate calculation.
                        var prev_avg: float = sp.average_fitness_history[-2] if sp.average_fitness_history.size() >= 2 else cur_avg
                        var improvement: float = (cur_avg - prev_avg) / (absf(prev_avg) + 1e-6)
                        scores[i] = maxf(0.0, cur_avg) * (1.0 + maxf(0.0, improvement))
                        # Mutation rate: low improvement -> higher mutation.
                        if improvement <= low_improvement_threshold:
                                sp.mutation_rate_multiplier = low_improvement_mutation_multiplier
                        else:
                                sp.mutation_rate_multiplier = high_improvement_mutation_multiplier
                # Cull species below min_score_for_survival (only after we have history).
                var kept: Array = species_list
                var kept_scores: Array[float] = scores
                if species_list[0].best_fitness_history.size() >= 2:
                        kept = []
                        kept_scores = []
                        for i in range(species_list.size()):
                                if scores[i] >= min_score_for_survival:
                                        kept.append(species_list[i])
                                        kept_scores.append(scores[i])
                # Safeguard: never cull all species; keep at least the best one.
                if kept.is_empty() and not species_list.is_empty():
                        var best_idx := 0
                        for i in range(1, species_list.size()):
                                if scores[i] > scores[best_idx]:
                                        best_idx = i
                        kept = [species_list[best_idx]]
                        kept_scores = [scores[best_idx]]
                _allocate_proportional(kept, kept_scores, total_population)


class Novelty:
        extends EvaluationStrategy
        # Score = average_fitness * novelty_bonus
        # novelty_bonus is computed by comparing the species's representative to
        # other species' representatives. More distant => more novel.
        # Uses the similarity test from ctx (if available).

        var similarity: SimilarityTest = null
        var novelty_weight: float = 1.0

        func _init(p_similarity: SimilarityTest = null, p_novelty_weight: float = 1.0) -> void:
                similarity = p_similarity
                novelty_weight = p_novelty_weight

        func evaluate(species_list: Array, total_population: int, _ctx: MutationContext) -> void:
                if species_list.is_empty():
                        return
                # Reset all species first so stale allocations from previous generations
                # don't leak into species that are not receiving new children.
                for sp: Species in species_list:
                        sp.allocated_children = 0
                var scores: Array[float] = []
                scores.resize(species_list.size())
                for i in range(species_list.size()):
                        var sp: Species = species_list[i]
                        var avg: float = maxf(0.0, sp.average_fitness)
                        var novelty: float = 1.0
                        if similarity != null and species_list.size() > 1:
                                # Average distance to other species' representatives.
                                var total_d: float = 0.0
                                var count: int = 0
                                for j in range(species_list.size()):
                                        if i == j:
                                                continue
                                        var other: Species = species_list[j]
                                        if other.representative != null and sp.representative != null:
                                                total_d += similarity.distance(sp.representative, other.representative)
                                                count += 1
                                if count > 0:
                                        novelty = 1.0 + novelty_weight * (total_d / float(count))
                        scores[i] = avg * novelty
                        # More novel species get lower mutation rate (they're already exploring).
                        sp.mutation_rate_multiplier = 1.0 / (1.0 + novelty * 0.1)
                _allocate_proportional(species_list, scores, total_population)
