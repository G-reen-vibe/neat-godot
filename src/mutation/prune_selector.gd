## Selects which connections to prune (remove) from a genome.
##
## Implementations:
##   - [Standard]: uniform random over all connections.
##   - [LeastWeight]: biases toward connections whose weight magnitude is small
##     within the species average (proxy for "unimportant").
class_name PruneSelector
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
	var conns: Array = []
	conns.assign(genome.connections.values())
	var n := _count_to_select(conns.size(), ctx)
	conns.shuffle()
	if n < conns.size():
		conns.resize(n)
	return conns


class Standard:
	extends PruneSelector

	func _init(p_min_count: int = 1, p_rate: float = 0.0) -> void:
		super(p_min_count, p_rate)


class LeastWeight:
	extends PruneSelector
	# Bias toward connections whose absolute weight is small.

	func _init(p_min_count: int = 1, p_rate: float = 0.0) -> void:
		super(p_min_count, p_rate)

	func select(genome: Genome, ctx: MutationContext) -> Array:
		var conns: Array = []
		conns.assign(genome.connections.values())
		if conns.is_empty():
			return []
		var weights: Array[float] = []
		weights.resize(conns.size())
		for i in range(conns.size()):
			var c: ConnectionGene = conns[i]
			# Larger weight = less likely to be pruned => use 1/(|w|+eps).
			weights[i] = 1.0 / (absf(c.weight) + 0.01)
		var n := _count_to_select(conns.size(), ctx)
		return ConnectionSelector.LeastUsed._weighted_sample_without_replacement(conns, weights, n, ctx)
