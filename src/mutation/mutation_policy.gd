## Combines selectors and mutators into a single mutation policy and applies
## them to a genome.
##
## Implementations:
##   - [General]: standard NEAT mutation policy. Applies each configured
##     selector/mutator pair in sequence (if [member stacked] is true) or
##     picks one pair at random (if [member stacked] is false). Multiplies
##     every selector's effective rate by [member rate_multiplier].
##   - [PhasedPruning]: alternates between a "growth" phase (apply weight,
##     connection, and neuron mutations) and a "pruning" phase (apply prune
##     and enable mutations aggressively). Phase length is configurable.
class_name MutationPolicy
extends RefCounted

# Selector/mutator pairs. Any may be null; null pairs are skipped.
var weight_selector: WeightSelector = null
var weight_mutator: WeightMutator = null
var connection_selector: ConnectionSelector = null
var connection_mutator: ConnectionMutator = null
var neuron_selector: NeuronSelector = null
var neuron_mutator: NeuronMutator = null
var prune_selector: PruneSelector = null
var prune_mutator: PruneMutator = null
var enable_selector: EnableSelector = null  # no mutator; enabling is the action

func _init() -> void:
	pass

## Apply the policy to [param genome] using [param ctx]. Subclasses override.
func apply(genome: Genome, ctx: MutationContext) -> void:
	pass

# --- Helpers shared by subclasses ---

func _apply_weight(genome: Genome, ctx: MutationContext) -> void:
	if weight_selector == null or weight_mutator == null:
		return
	var selected: Array = weight_selector.select(genome, ctx)
	for c_v: Variant in selected:
		weight_mutator.mutate(c_v, ctx)

func _apply_connection(genome: Genome, ctx: MutationContext) -> void:
	if connection_selector == null or connection_mutator == null:
		return
	var pairs: Array = connection_selector.select(genome, ctx)
	connection_mutator.mutate(genome, pairs, ctx)

func _apply_neuron(genome: Genome, ctx: MutationContext) -> void:
	if neuron_selector == null or neuron_mutator == null:
		return
	var selected: Array = neuron_selector.select(genome, ctx)
	neuron_mutator.mutate(genome, selected, ctx)

func _apply_prune(genome: Genome, ctx: MutationContext) -> void:
	if prune_selector == null or prune_mutator == null:
		return
	var selected: Array = prune_selector.select(genome, ctx)
	prune_mutator.mutate(genome, selected, ctx)

func _apply_enable(genome: Genome, ctx: MutationContext) -> void:
	if enable_selector == null:
		return
	var selected: Array = enable_selector.select(genome, ctx)
	for c_v: Variant in selected:
		var c: ConnectionGene = c_v
		# In topological mode, check that re-enabling won't create a loop.
		if ctx.forbid_loops and genome.would_create_loop(c.from_node, c.to_node):
			continue
		c.enabled = true
		genome.mark_dirty()


## Standard NEAT mutation policy.
class General:
	extends MutationPolicy

	# Multiplier applied to every selector's effective rate.
	var rate_multiplier: float = 1.0
	# If true, apply all configured mutation types in sequence.
	# If false, pick one configured mutation type uniformly at random.
	var stacked: bool = true

	func _init(p_stacked: bool = true, p_rate_multiplier: float = 1.0) -> void:
		super()
		stacked = p_stacked
		rate_multiplier = p_rate_multiplier

	func apply(genome: Genome, ctx: MutationContext) -> void:
		ctx.rate_multiplier = rate_multiplier
		if stacked:
			_apply_weight(genome, ctx)
			_apply_connection(genome, ctx)
			_apply_neuron(genome, ctx)
			_apply_prune(genome, ctx)
			_apply_enable(genome, ctx)
		else:
			# Build a list of available mutation ops.
			var ops: Array[Callable] = []
			if weight_selector != null and weight_mutator != null:
				ops.append(_apply_weight)
			if connection_selector != null and connection_mutator != null:
				ops.append(_apply_connection)
			if neuron_selector != null and neuron_mutator != null:
				ops.append(_apply_neuron)
			if prune_selector != null and prune_mutator != null:
				ops.append(_apply_prune)
			if enable_selector != null:
				ops.append(_apply_enable)
			if ops.is_empty():
				return
			var idx := ctx.rng.randi_range(0, ops.size() - 1)
			ops[idx].call(genome, ctx)


## Phased Pruning policy. Alternates between growth and pruning phases.
## During growth: weight, connection, neuron mutations are applied.
## During pruning: prune and enable mutations are applied with an aggressive
## rate multiplier.
class PhasedPruning:
	extends MutationPolicy

	# Number of generations per phase.
	var phase_length: int = 5
	# Multiplier applied to mutation rates during the pruning phase.
	var pruning_rate_multiplier: float = 3.0
	# Multiplier applied during the growth phase.
	var growth_rate_multiplier: float = 1.0
	# Current generation counter (advanced externally via [method advance_generation]).
	var _generation: int = 0

	func _init(p_phase_length: int = 5, p_pruning_rate_multiplier: float = 3.0) -> void:
		super()
		phase_length = p_phase_length
		pruning_rate_multiplier = p_pruning_rate_multiplier

	func advance_generation() -> void:
		_generation += 1

	func _in_pruning_phase() -> bool:
		# Cycle: phase_length growth, then phase_length pruning.
		return (_generation % (2 * phase_length)) >= phase_length

	func apply(genome: Genome, ctx: MutationContext) -> void:
		if _in_pruning_phase():
			ctx.rate_multiplier = pruning_rate_multiplier
			_apply_prune(genome, ctx)
			_apply_enable(genome, ctx)
		else:
			ctx.rate_multiplier = growth_rate_multiplier
			_apply_weight(genome, ctx)
			_apply_connection(genome, ctx)
			_apply_neuron(genome, ctx)
