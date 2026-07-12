## Determines how the weight of a *shared* connection (one present in both
## parents) is computed in the child.
##
## Implementations:
##   - [Standard]:      random pick between parent A and B.
##   - [StandardAll]:   per-neuron, choose one parent; all of that neuron's
##                       shared-connection weights come from that parent.
##   - [Average]:       arithmetic mean of the two weights.
##   - [BiasedAverage]: weighted mean biased toward the fitter parent.
##
## This is orthogonal to [OverallCrossover]: the overall strategy decides
## *which* connections exist in the child; the neuron-level strategy decides
## the *weight* of shared connections.
class_name NeuronCrossover
extends RefCounted

## Called once at the start of a crossover. Subclasses can use this to
## precompute per-neuron decisions.
func begin_crossover(parent_a: Genome, parent_b: Genome, ctx: MutationContext) -> void:
	pass

## Return the child's weight for a shared connection.
## [param w_a], [param w_b] are the two parents' weights.
## [param fit_a], [param fit_b] are the two parents' fitnesses.
func merge_weight(conn_innov: int, w_a: float, w_b: float, fit_a: float, fit_b: float, ctx: MutationContext) -> float:
	return w_a


class Standard:
	extends NeuronCrossover

	func merge_weight(_innov: int, w_a: float, w_b: float, _fa: float, _fb: float, ctx: MutationContext) -> float:
		return w_a if ctx.rng.randf() < 0.5 else w_b


class StandardAll:
	extends NeuronCrossover
	# Per-neuron: choose one parent (A or B). All shared connections touching
	# that neuron take their weight from the chosen parent.
	# If the two endpoints of a connection are owned by different parents,
	# fall back to random pick (Standard behaviour).

	var _node_owner: Dictionary = {}  # node_id -> 0 (A) or 1 (B)

	func begin_crossover(parent_a: Genome, parent_b: Genome, ctx: MutationContext) -> void:
		_node_owner.clear()
		# Union of node ids.
		var ids: Dictionary = {}
		for n: NodeGene in parent_a.nodes.values():
			ids[n.id] = true
		for n: NodeGene in parent_b.nodes.values():
			ids[n.id] = true
		for nid: int in ids:
			_node_owner[nid] = 0 if ctx.rng.randf() < 0.5 else 1

	func merge_weight(_innov: int, w_a: float, w_b: float, _fa: float, _fb: float, ctx: MutationContext) -> float:
		# Default: random pick (used when conn has no endpoints or endpoints disagree).
		return w_a if ctx.rng.randf() < 0.5 else w_b

	# Specialized entry point used by OverallCrossover: takes from/to ids.
	func merge_weight_for_pair(from_id: int, to_id: int, w_a: float, w_b: float, ctx: MutationContext) -> float:
		var owner_a: int = int(_node_owner.get(from_id, -1))
		var owner_b: int = int(_node_owner.get(to_id, -1))
		if owner_a == 0 and owner_b == 0:
			return w_a
		if owner_a == 1 and owner_b == 1:
			return w_b
		# Disagreement or unknown: random.
		return w_a if ctx.rng.randf() < 0.5 else w_b


class Average:
	extends NeuronCrossover

	func merge_weight(_innov: int, w_a: float, w_b: float, _fa: float, _fb: float, _ctx: MutationContext) -> float:
		return (w_a + w_b) * 0.5


class BiasedAverage:
	extends NeuronCrossover
	# Weight the average toward the fitter parent.
	# bias = clamp(0.5 + 0.5 * (fit_a - fit_b) / (|fit_a| + |fit_b| + eps), 0, 1)
	# Then child = lerp(w_b, w_a, bias).

	var bias_strength: float = 0.5  # 0 = pure average, 1 = full bias toward fitter

	func _init(p_bias_strength: float = 0.5) -> void:
		bias_strength = p_bias_strength

	func merge_weight(_innov: int, w_a: float, w_b: float, fa: float, fb: float, _ctx: MutationContext) -> float:
		var delta := fa - fb
		var norm := absf(fa) + absf(fb) + 1e-6
		var raw_bias := 0.5 + 0.5 * (delta / norm)
		# Apply bias_strength: 0 -> 0.5 (pure average), 1 -> raw_bias (full bias).
		var bias: float = lerp(0.5, clampf(raw_bias, 0.0, 1.0), bias_strength)
		return lerp(w_b, w_a, bias)
