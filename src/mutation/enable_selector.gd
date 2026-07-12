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
        var eff_rate := rate * ctx.rate_multiplier
        var by_rate := int(ceil(eff_rate * float(total)))
        var n := maxi(min_count, by_rate)
        return mini(n, total)

func select(genome: Genome, ctx: MutationContext) -> Array:
        var disabled := genome.disabled_connections()
        var n := _count_to_select(disabled.size(), ctx)
        disabled.shuffle()
        if n < disabled.size():
                disabled.resize(n)
        return disabled


class Standard:
        extends EnableSelector

        func _init(p_min_count: int = 1, p_rate: float = 0.0) -> void:
                super(p_min_count, p_rate)
