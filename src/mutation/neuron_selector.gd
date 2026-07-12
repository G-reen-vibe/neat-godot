## Selects which existing (enabled) connections to "split" by inserting a new
## hidden neuron in their middle.
##
## Implementations:
##   - [Standard]: uniform random.
##   - [LeastCommon]: biases toward connections whose innovation has been split
##     infrequently in the species (uses [member Species.node_selection_counts]
##     keyed by the would-be split node id).
class_name NeuronSelector
extends RefCounted

var min_count: int = 1
var rate: float = 0.0

func _init(p_min_count: int = 1, p_rate: float = 0.0) -> void:
        min_count = p_min_count
        rate = p_rate

func _count_to_select(total: int, ctx: MutationContext) -> int:
        var eff_rate := rate * ctx.rate_multiplier
        var by_rate := int(ceil(eff_rate * float(total)))
        var n := maxi(min_count, by_rate)
        return mini(n, total)

func select(genome: Genome, ctx: MutationContext) -> Array:
        var enabled := genome.enabled_connections()
        var n := _count_to_select(enabled.size(), ctx)
        enabled.shuffle()
        if n < enabled.size():
                enabled.resize(n)
        return enabled


class Standard:
        extends NeuronSelector

        func _init(p_min_count: int = 1, p_rate: float = 0.0) -> void:
                super(p_min_count, p_rate)


class LeastCommon:
        extends NeuronSelector

        func _init(p_min_count: int = 1, p_rate: float = 0.0) -> void:
                super(p_min_count, p_rate)

        func select(genome: Genome, ctx: MutationContext) -> Array:
                var enabled := genome.enabled_connections()
                if enabled.is_empty():
                        return []
                var weights: Array[float] = []
                weights.resize(enabled.size())
                for i in range(enabled.size()):
                        var c: ConnectionGene = enabled[i]
                        # Look up the would-be split node id from the tracker.
                        var split_id := ctx.tracker.get_split_node_id(c.innovation)
                        var cnt: int = 0
                        if ctx.species != null:
                                cnt = ctx.species.node_selection_count(split_id)
                        weights[i] = 1.0 / (1.0 + float(cnt))
                var n := _count_to_select(enabled.size(), ctx)
                return ConnectionSelector.LeastUsed._weighted_sample_without_replacement(enabled, weights, n, ctx)
