## Selects which disabled connections to re-enable.
##
## Only one implementation per spec: [Standard], which selects uniformly at
## random from the genome's disabled connections using the standard
## {x}/{y} count formula.
class_name EnableSelector
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
		var disabled := genome.disabled_connections()
		var n := _count_to_select(disabled.size(), ctx)
		_shuffle_with_rng(disabled, ctx.rng)
		if n < disabled.size():
				disabled.resize(n)
		return disabled

# Fisher-Yates shuffle using a specific RNG (for reproducibility).
static func _shuffle_with_rng(arr: Array, rng: RandomNumberGenerator) -> void:
		for i in range(arr.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = arr[i]
				arr[i] = arr[j]
				arr[j] = tmp


class Standard:
		extends EnableSelector

		func _init(p_min_count: int = 1, p_rate: float = 0.0) -> void:
				super(p_min_count, p_rate)
