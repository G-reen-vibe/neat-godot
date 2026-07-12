## Selects which enabled connections in a genome will have their weights mutated.
##
## Two implementations:
##   - [WeightSelectorStandard]: uniform random selection.
##   - [WeightSelectorCapped]:   biases toward connections whose weights are
##                               pinned at [member min_weight] /
##                               [member max_weight], and self-adjusts the
##                               effective rate to keep the population off
##                               the bounds.
##
## All selectors honour the same {x}/{y} formula:
## [code]
##   n_to_select = max(min_count, ceil(rate * enabled_count))
## [/code]
class_name WeightSelector
extends RefCounted

# Minimum number of connections to mutate (the spec's {x}, default 1).
var min_count: int = 1
# Mutation rate as a fraction in [0, 1] (the spec's {y}%, default 0).
var rate: float = 0.0

func _init(p_min_count: int = 1, p_rate: float = 0.0) -> void:
        min_count = p_min_count
        rate = p_rate

## Effective number of items to select given [param total] available.
func _count_to_select(total: int, ctx: MutationContext) -> int:
        var eff_rate := rate * ctx.rate_multiplier
        var by_rate := int(ceil(eff_rate * float(total)))
        var n := maxi(min_count, by_rate)
        return mini(n, total)

## Override in subclasses. Returns Array[ConnectionGene] to mutate.
func select(genome: Genome, ctx: MutationContext) -> Array:
        var enabled := genome.enabled_connections()
        var n := _count_to_select(enabled.size(), ctx)
        _shuffle_with_rng(enabled, ctx.rng)
        if n < enabled.size():
                enabled.resize(n)
        return enabled

# Fisher-Yates shuffle using a specific RNG (for reproducibility).
static func _shuffle_with_rng(arr: Array, rng: RandomNumberGenerator) -> void:
        for i in range(arr.size() - 1, 0, -1):
                var j := rng.randi_range(0, i)
                var tmp = arr[i]
                arr[i] = arr[j]
                arr[j] = tmp


## Standard uniform-random weight selector.
class Standard:
        extends WeightSelector

        func _init(p_min_count: int = 1, p_rate: float = 0.0) -> void:
                super(p_min_count, p_rate)


## "All" weight selector: returns ALL enabled connections so the mutator
## perturbs every weight by a small amount. Used when weight_mutation_mode = "all".
class All:
        extends WeightSelector

        func _init() -> void:
                super(0, 1.0)

        func select(genome: Genome, ctx: MutationContext) -> Array:
                return genome.enabled_connections()


## Capped weight selector. Biases selection toward connections whose weight is
## at [member min_weight] or [member max_weight], and self-adjusts the rate so
## that the more connections are stuck at the bounds, the more aggressive the
## mutation becomes.
class Capped:
        extends WeightSelector

        var min_weight: float = -3.0
        var max_weight: float = 3.0
        # If the proportion of pinned connections exceeds this, multiply rate by 2.
        var pin_aggravation_threshold: float = 0.3
        var pin_aggravation_factor: float = 2.0
        # If the proportion is below this, multiply rate by 0.5.
        var pin_relief_threshold: float = 0.05
        var pin_relief_factor: float = 0.5
        # Epsilon for "at bound" comparison.
        var bound_eps: float = 1e-4

        func _init(p_min_count: int = 1, p_rate: float = 0.0, p_min_weight: float = -3.0, p_max_weight: float = 3.0) -> void:
                super(p_min_count, p_rate)
                min_weight = p_min_weight
                max_weight = p_max_weight

        func _is_pinned(w: float) -> bool:
                return absf(w - min_weight) < bound_eps or absf(w - max_weight) < bound_eps

        func select(genome: Genome, ctx: MutationContext) -> Array:
                var enabled := genome.enabled_connections()
                if enabled.is_empty():
                        return []
                # Count pinned connections.
                var pinned_count: int = 0
                for c: ConnectionGene in enabled:
                        if _is_pinned(c.weight):
                                pinned_count += 1
                var pin_ratio := float(pinned_count) / float(enabled.size())
                # Self-adjust rate (also multiply by the context's rate_multiplier).
                var eff_rate := rate * ctx.rate_multiplier
                if pin_ratio > pin_aggravation_threshold:
                        eff_rate *= pin_aggravation_factor
                elif pin_ratio < pin_relief_threshold:
                        eff_rate *= pin_relief_factor
                var by_rate := int(ceil(eff_rate * float(enabled.size())))
                var n := mini(maxi(min_count, by_rate), enabled.size())
                # Bias selection: pinned connections get higher probability.
                # We implement this by sorting pinned-first and then taking a uniform
                # sample weighted toward the front.
                # Simpler approach: shuffle, but ensure at least min(pinned_count, n) of
                # the selected items are pinned when possible.
                var pinned: Array = []
                var unpinned: Array = []
                for c: ConnectionGene in enabled:
                        if _is_pinned(c.weight):
                                pinned.append(c)
                        else:
                                unpinned.append(c)
                _shuffle_with_rng(pinned, ctx.rng)
                _shuffle_with_rng(unpinned, ctx.rng)
                var out: Array = []
                # Take as many pinned as possible (up to n).
                var take_pinned := mini(pinned.size(), n)
                for i in range(take_pinned):
                        out.append(pinned[i])
                # Fill the rest with unpinned.
                var remaining := n - take_pinned
                for i in range(mini(remaining, unpinned.size())):
                        out.append(unpinned[i])
                return out
