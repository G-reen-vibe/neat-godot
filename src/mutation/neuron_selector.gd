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
						# Look up the would-be split node id WITHOUT allocating it.
						# Selectors must not mutate the tracker; allocation happens only
						# in the mutator when the neuron is actually added.
						var split_id := ctx.tracker.peek_split_node_id(c.innovation)
						var cnt: int = 0
						if split_id >= 0 and ctx.species != null:
								cnt = ctx.species.node_selection_count(split_id)
						weights[i] = 1.0 / (1.0 + float(cnt))
				var n := _count_to_select(enabled.size(), ctx)
				return ConnectionSelector.LeastUsed._weighted_sample_without_replacement(enabled, weights, n, ctx)
