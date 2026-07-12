## Selects which *not-yet-existing* connections to add to a genome.
##
## Implementations:
##   - [Standard]: uniform random over candidate (from, to) pairs.
##   - [LeastUsed]: biases toward pairs involving nodes with low degree.
##   - [LeastCommon]: biases toward innovation numbers that have been selected
##     infrequently across the species (uses the species's
##     [member Species.selection_counts] table).
class_name ConnectionSelector
extends RefCounted

var min_count: int = 1
var rate: float = 0.0
# If true, candidate pairs that would close a cycle in the enabled subgraph
# are filtered out before selection. Required for topological-sort forward pass.
var forbid_loops: bool = true

func _init(p_min_count: int = 1, p_rate: float = 0.0, p_forbid_loops: bool = true) -> void:
        min_count = p_min_count
        rate = p_rate
        forbid_loops = p_forbid_loops

func _count_to_select(total: int, ctx: MutationContext) -> int:
        # Probabilistic interpretation: when rate < 1.0, treat it as the probability
        # of applying 1 mutation (standard NEAT practice). When rate >= 1.0, treat it
        # as a count. min_count acts as a floor in both cases.
        var eff_rate := rate * ctx.rate_multiplier
        var n: int
        if eff_rate < 1.0:
                n = 1 if ctx.rng.randf() < eff_rate else 0
        else:
                n = int(eff_rate)
        n = maxi(min_count, n)
        return mini(n, total)

## Override in subclasses. Returns Array[Vector2i] of (from_id, to_id) pairs.
func select(genome: Genome, ctx: MutationContext) -> Array:
        var candidates := genome.candidate_new_connections(forbid_loops)
        var n := _count_to_select(candidates.size(), ctx)
        candidates.shuffle()
        if n < candidates.size():
                candidates.resize(n)
        return candidates


class Standard:
        extends ConnectionSelector

        func _init(p_min_count: int = 1, p_rate: float = 0.0, p_forbid_loops: bool = true) -> void:
                super(p_min_count, p_rate, p_forbid_loops)


class LeastUsed:
        extends ConnectionSelector
        # Bias selection toward pairs (a, b) where degree(a) + degree(b) is small.
        # Implemented as: compute inverse-degree-weighted roulette over candidates.

        func _init(p_min_count: int = 1, p_rate: float = 0.0, p_forbid_loops: bool = true) -> void:
                super(p_min_count, p_rate, p_forbid_loops)

        func select(genome: Genome, ctx: MutationContext) -> Array:
                var candidates := genome.candidate_new_connections(forbid_loops)
                if candidates.is_empty():
                        return []
                # Build degree map.
                var degree: Dictionary = {}
                for n_id: int in genome.nodes:
                        degree[n_id] = 0
                for c: ConnectionGene in genome.connections.values():
                        if not c.enabled:
                                continue
                        degree[c.from_node] = int(degree.get(c.from_node, 0)) + 1
                        degree[c.to_node] = int(degree.get(c.to_node, 0)) + 1
                # Inverse-degree weight = 1 / (1 + deg(a) + deg(b)).
                var weights: Array[float] = []
                weights.resize(candidates.size())
                for i in range(candidates.size()):
                        var pair: Vector2i = candidates[i]
                        var d_sum := float(int(degree.get(pair.x, 0)) + int(degree.get(pair.y, 0)))
                        weights[i] = 1.0 / (1.0 + d_sum)
                var n := _count_to_select(candidates.size(), ctx)
                # Weighted sample without replacement.
                return _weighted_sample_without_replacement(candidates, weights, n, ctx)

        # Weighted sample without replacement using roulette per draw.
        static func _weighted_sample_without_replacement(items: Array, weights: Array, k: int, ctx: MutationContext) -> Array:
                var pool_items := items.duplicate()
                var pool_weights := weights.duplicate()
                var out: Array = []
                for _i in range(mini(k, pool_items.size())):
                        var picked: Variant = RandomSelectors.roulette(pool_items, pool_weights, ctx.rng)
                        # Remove the picked item.
                        var idx: int = pool_items.find(picked)
                        pool_items.remove_at(idx)
                        pool_weights.remove_at(idx)
                        out.append(picked)
                return out


class LeastCommon:
        extends ConnectionSelector
        # Biases selection toward innovation numbers that have been selected
        # infrequently in this species. Since the connection doesn't exist yet, we
        # use the species's selection count for the would-be innovation number
        # (which is tracked even for connection-add selections).

        func _init(p_min_count: int = 1, p_rate: float = 0.0, p_forbid_loops: bool = true) -> void:
                super(p_min_count, p_rate, p_forbid_loops)

        func select(genome: Genome, ctx: MutationContext) -> Array:
                var candidates := genome.candidate_new_connections(forbid_loops)
                if candidates.is_empty():
                        return []
                var weights: Array[float] = []
                weights.resize(candidates.size())
                for i in range(candidates.size()):
                        var pair: Vector2i = candidates[i]
                        # Look up the would-be innovation number WITHOUT allocating it.
                        # Selectors must not mutate the tracker; allocation happens only
                        # in the mutator when the connection is actually added.
                        var innov := ctx.tracker.peek_connection_innov(pair.x, pair.y)
                        var cnt: int = 0
                        if innov >= 0 and ctx.species != null:
                                cnt = ctx.species.connection_selection_count(innov)
                        weights[i] = 1.0 / (1.0 + float(cnt))
                var n := _count_to_select(candidates.size(), ctx)
                return LeastUsed._weighted_sample_without_replacement(candidates, weights, n, ctx)
