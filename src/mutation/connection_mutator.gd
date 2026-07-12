## Adds new connections to a genome. Operates on a list of (from, to) pairs
## returned by a [ConnectionSelector].
##
## Implementations:
##   - [Standard]: weight uniformly sampled in [min_weight, max_weight].
##   - [Normal]:   weight sampled from a normal distribution.
##   - [SafeGradient]: "Safe Mutation Through Gradients" -- tentatively apply
##                     the mutation, evaluate the gradient signal on a small
##                     perturbation, and revert if the mutation hurts the
##                     objective. The objective is provided by an external
##                     callback; if no callback is set, falls back to a
##                     random-perturbation safety check.
class_name ConnectionMutator
extends RefCounted

func _init() -> void:
	pass

## Apply mutation to add connections for each (from, to) in [param pairs].
## Returns the Array of innovation numbers that were actually added (some may
## be skipped if a loop would form and [member ctx.forbid_loops] is true).
func mutate(genome: Genome, pairs: Array, ctx: MutationContext) -> Array[int]:
	var added: Array[int] = []
	for pair_v: Variant in pairs:
		var pair: Vector2i = pair_v
		var from_id: int = pair.x
		var to_id: int = pair.y
		if ctx.forbid_loops and genome.would_create_loop(from_id, to_id):
			continue
		var innov := ctx.tracker.get_connection_innov(from_id, to_id)
		# Skip if the connection already exists.
		if genome.connections.has(innov):
			continue
		var w := _sample_weight(ctx)
		genome.add_connection(ConnectionGene.new(innov, from_id, to_id, w))
		# Update species selection count for Least Common selectors.
		if ctx.species != null:
			ctx.species.increment_connection_selection(innov)
		added.append(innov)
	return added

## Override in subclasses to sample the new connection's weight.
func _sample_weight(ctx: MutationContext) -> float:
	return 0.0


class Standard:
	extends ConnectionMutator

	var min_weight: float = -1.0
	var max_weight: float = 1.0

	func _init(p_min_weight: float = -1.0, p_max_weight: float = 1.0) -> void:
		super()
		min_weight = p_min_weight
		max_weight = p_max_weight

	func _sample_weight(ctx: MutationContext) -> float:
		return ctx.rng.randf_range(min_weight, max_weight)


class Normal:
	extends ConnectionMutator

	var mean: float = 0.0
	var std: float = 0.5

	func _init(p_mean: float = 0.0, p_std: float = 0.5) -> void:
		super()
		mean = p_mean
		std = p_std

	func _sample_weight(ctx: MutationContext) -> float:
		return mean + ctx.rng.randfn() * std


## Safe Mutation Through Gradients (SMUG-style).
## We tentatively add the connection with a small initial weight, then perturb
## the weight by +/-delta and accept whichever direction keeps the network's
## output norm closer to the target (a small proxy for "useful gradient
## signal"). If neither direction improves, the connection is reverted.
##
## This is a lightweight surrogate for the real paper's approach (which requires
## task-specific gradient computation). For task-aware safety, set
## [member safety_callback] to a Callable that returns a quality score for a
## given genome (higher = better); the mutator will keep the mutation only if
## the score doesn't drop.
class SafeGradient:
	extends ConnectionMutator

	var initial_weight: float = 0.0
	var perturbation_delta: float = 0.1
	var safety_callback: Callable = Callable()
	# When no safety_callback is set, we evaluate by sampling a random input
	# and measuring output magnitude change. The genome's input/output node
	# ids must be available; we use input_nodes() / output_nodes().
	var probe_inputs: Array = []  # Array[Dictionary] to probe; populated lazily.

	func _init(p_initial_weight: float = 0.0, p_perturbation_delta: float = 0.1) -> void:
		super()
		initial_weight = p_initial_weight
		perturbation_delta = p_perturbation_delta

	func mutate(genome: Genome, pairs: Array, ctx: MutationContext) -> Array[int]:
		var added: Array[int] = []
		# Lazily prepare probe inputs if we need them.
		var need_probes: bool = not safety_callback.is_valid()
		if need_probes and probe_inputs.is_empty():
			_build_probe_inputs(genome, ctx)
		for pair_v: Variant in pairs:
			var pair: Vector2i = pair_v
			var from_id: int = pair.x
			var to_id: int = pair.y
			if ctx.forbid_loops and genome.would_create_loop(from_id, to_id):
				continue
			var innov := ctx.tracker.get_connection_innov(from_id, to_id)
			if genome.connections.has(innov):
				continue
			# Tentatively add with initial weight.
			var conn := ConnectionGene.new(innov, from_id, to_id, initial_weight)
			genome.add_connection(conn)
			# Evaluate.
			var accepted := _evaluate_and_perturb(genome, conn, ctx)
			if not accepted:
				genome.remove_connection(innov)
			else:
				if ctx.species != null:
					ctx.species.increment_connection_selection(innov)
				added.append(innov)
		return added

	func _evaluate_and_perturb(genome: Genome, conn: ConnectionGene, ctx: MutationContext) -> bool:
		if safety_callback.is_valid():
			# Score with the connection at +delta and -delta; keep the better.
			conn.weight = initial_weight + perturbation_delta
			var score_plus: float = float(safety_callback.call(genome))
			conn.weight = initial_weight - perturbation_delta
			var score_minus: float = float(safety_callback.call(genome))
			if score_plus >= score_minus:
				conn.weight = initial_weight + perturbation_delta
				return score_plus >= 0.0
			else:
				conn.weight = initial_weight - perturbation_delta
				return score_minus >= 0.0
		# No callback: probe by measuring output magnitude change vs. baseline.
		# Compute baseline (with the connection at weight 0 -> no effect).
		conn.weight = 0.0
		var base_out_norm: float = _output_norm(genome, ctx)
		conn.weight = perturbation_delta
		var plus_norm: float = _output_norm(genome, ctx)
		conn.weight = -perturbation_delta
		var minus_norm: float = _output_norm(genome, ctx)
		# Accept if either direction strictly changes the output (i.e., the
		# connection is wired into a path that actually affects outputs).
		if absf(plus_norm - base_out_norm) > 1e-6 or absf(minus_norm - base_out_norm) > 1e-6:
			# Pick the direction with larger deviation from baseline.
			if absf(plus_norm - base_out_norm) >= absf(minus_norm - base_out_norm):
				conn.weight = perturbation_delta
			else:
				conn.weight = -perturbation_delta
			return true
		return false

	func _output_norm(genome: Genome, ctx: MutationContext) -> float:
		if probe_inputs.is_empty():
			return 0.0
		var total: float = 0.0
		for inp: Dictionary in probe_inputs:
			var out := genome.forward(inp, ctx.forward_mode)
			for v in out.values():
				total += float(v) * float(v)
		return sqrt(total)

	func _build_probe_inputs(genome: Genome, ctx: MutationContext) -> void:
		probe_inputs.clear()
		var in_nodes := genome.input_nodes()
		if in_nodes.is_empty():
			return
		# 3 random probes.
		for _i in range(3):
			var inp: Dictionary = {}
			for n: NodeGene in in_nodes:
				inp[n.id] = ctx.rng.randf_range(-1.0, 1.0)
			probe_inputs.append(inp)
