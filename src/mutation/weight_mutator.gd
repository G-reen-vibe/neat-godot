## Mutates the weight of an existing connection.
##
## Two implementations:
##   - [WeightMutatorStandard]: adds a uniform random value in [min_delta, max_delta].
##   - [WeightMutatorNormal]:   adds a value sampled from a normal distribution
##                              with mean 0 and std [member std].
class_name WeightMutator
extends RefCounted

## Clamp applied to the resulting weight. Set to +/-INF to disable.
var clamp_min: float = -1e9
var clamp_max: float = 1e9

func _init(p_clamp_min: float = -1e9, p_clamp_max: float = 1e9) -> void:
	clamp_min = p_clamp_min
	clamp_max = p_clamp_max

## Apply the mutation to a single connection.
func mutate(connection: ConnectionGene, ctx: MutationContext) -> void:
	# Default: no-op. Subclasses override.
	pass


class Standard:
	extends WeightMutator

	var min_delta: float = -1.0
	var max_delta: float = 1.0

	func _init(p_min_delta: float = -1.0, p_max_delta: float = 1.0, p_clamp_min: float = -1e9, p_clamp_max: float = 1e9) -> void:
		super(p_clamp_min, p_clamp_max)
		min_delta = p_min_delta
		max_delta = p_max_delta

	func mutate(connection: ConnectionGene, ctx: MutationContext) -> void:
		var delta := ctx.rng.randf_range(min_delta, max_delta)
		connection.weight = clampf(connection.weight + delta, clamp_min, clamp_max)


class Normal:
	extends WeightMutator

	var mean: float = 0.0
	var std: float = 0.5

	func _init(p_mean: float = 0.0, p_std: float = 0.5, p_clamp_min: float = -1e9, p_clamp_max: float = 1e9) -> void:
		super(p_clamp_min, p_clamp_max)
		mean = p_mean
		std = p_std

	func mutate(connection: ConnectionGene, ctx: MutationContext) -> void:
		# randfn returns a sample from N(0, 1).
		var delta := mean + ctx.rng.randfn() * std
		connection.weight = clampf(connection.weight + delta, clamp_min, clamp_max)
