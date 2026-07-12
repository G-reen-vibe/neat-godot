## Topology-level crossover: decides which connections from the two parents
## end up in the child, and uses a [NeuronCrossover] strategy to pick weights
## for shared connections.
##
## Implementations:
##   - [Fitter]:   child inherits the fitter parent's topology. Shared
##                 connections get the neuron-level crossover weight.
##   - [Bigger]:   child inherits the bigger parent's topology.
##   - [Combine]:  child inherits shared connections + as many disjoints as
##                 possible from both parents. If a loop forms, disjoints from
##                 the less-fit parent are removed one-by-one until the graph
##                 is acyclic.
##   - [Excluded]: child inherits shared connections + as few disjoints as
##                 possible. Disjoints from the more-fit parent are added
##                 back one-by-one if the resulting graph would be
##                 disconnected (i.e., some output has no incoming path).
class_name OverallCrossover
extends RefCounted

var neuron_crossover: NeuronCrossover = null

func _init(p_neuron_crossover: NeuronCrossover = null) -> void:
	neuron_crossover = p_neuron_crossover

## Produce a child genome from parents [param parent_a] (assumed fitter) and
## [param parent_b]. [param ctx] provides the RNG.
func crossover(parent_a: Genome, parent_b: Genome, ctx: MutationContext) -> Genome:
	# Default: standard NEAT crossover -- shared connections get neuron-crossover
	# weight; disjoints/excess inherited from parent_a (the fitter).
	if neuron_crossover != null:
		neuron_crossover.begin_crossover(parent_a, parent_b, ctx)
	var child := Genome.new()
	# Inherit all nodes from both parents (union). Activation/kind from fitter.
	for n: NodeGene in parent_a.nodes.values():
		child.add_node(n.duplicate())
	for n: NodeGene in parent_b.nodes.values():
		if not child.has_node(n.id):
			child.add_node(n.duplicate())
	# Iterate connections sorted by innovation.
	var innovs: Array[int] = []
	for innov: int in parent_a.connections:
		innovs.append(innov)
	for innov: int in parent_b.connections:
		if not innovs.has(innov):
			innovs.append(innov)
	innovs.sort()
	for innov: int in innovs:
		var ca: ConnectionGene = parent_a.connections.get(innov)
		var cb: ConnectionGene = parent_b.connections.get(innov)
		if ca != null and cb != null:
			# Shared: use neuron crossover for weight; enable if either is enabled.
			var w_a: float = ca.weight
			var w_b: float = cb.weight
			var w: float
			if neuron_crossover is NeuronCrossover.StandardAll:
				w = (neuron_crossover as NeuronCrossover.StandardAll).merge_weight_for_pair(ca.from_node, ca.to_node, w_a, w_b, ctx)
			elif neuron_crossover != null:
				w = neuron_crossover.merge_weight(innov, w_a, w_b, parent_a.fitness, parent_b.fitness, ctx)
			else:
				w = w_a
			var enabled := ca.enabled or cb.enabled
			# Inherit structure from A (from/to should match for shared conns).
			child.add_connection(ConnectionGene.new(innov, ca.from_node, ca.to_node, w, enabled))
		elif ca != null:
			# Excess/disjoint in A (fitter): inherit.
			child.add_connection(ca.duplicate())
		# cb-only connections are dropped in default strategy.
	return child


class Fitter:
	extends OverallCrossover

	func _init(p_neuron_crossover: NeuronCrossover = null) -> void:
		super(p_neuron_crossover)


class Bigger:
	extends OverallCrossover
	# Use the bigger parent's topology (treat the bigger parent as "fitter"
	# for the purpose of disjoint inheritance).

	func crossover(parent_a: Genome, parent_b: Genome, ctx: MutationContext) -> Genome:
		# Determine which is bigger.
		var a_bigger := parent_a.connection_count() >= parent_b.connection_count()
		var bigger: Genome = parent_a if a_bigger else parent_b
		var smaller: Genome = parent_b if a_bigger else parent_a
		if neuron_crossover != null:
			neuron_crossover.begin_crossover(bigger, smaller, ctx)
		var child := Genome.new()
		for n: NodeGene in bigger.nodes.values():
			child.add_node(n.duplicate())
		for n: NodeGene in smaller.nodes.values():
			if not child.has_node(n.id):
				child.add_node(n.duplicate())
		# Iterate connections: shared -> neuron crossover; disjoint -> from bigger.
		var innovs: Array[int] = []
		for innov: int in bigger.connections:
			innovs.append(innov)
		for innov: int in smaller.connections:
			if not innovs.has(innov):
				innovs.append(innov)
		innovs.sort()
		for innov: int in innovs:
			var cb: ConnectionGene = bigger.connections.get(innov)
			var cs: ConnectionGene = smaller.connections.get(innov)
			if cb != null and cs != null:
				var w: float
				if neuron_crossover is NeuronCrossover.StandardAll:
					w = (neuron_crossover as NeuronCrossover.StandardAll).merge_weight_for_pair(cb.from_node, cb.to_node, cb.weight, cs.weight, ctx)
				elif neuron_crossover != null:
					w = neuron_crossover.merge_weight(innov, cb.weight, cs.weight, bigger.fitness, smaller.fitness, ctx)
				else:
					w = cb.weight
				var enabled := cb.enabled or cs.enabled
				child.add_connection(ConnectionGene.new(innov, cb.from_node, cb.to_node, w, enabled))
			elif cb != null:
				child.add_connection(cb.duplicate())
		return child


class Combine:
	extends OverallCrossover
	# Inherit shared + as many disjoints as possible from BOTH parents.
	# If a loop forms, drop disjoints from the less-fit parent one-by-one
	# (in innovation order) until acyclic.

	func crossover(parent_a: Genome, parent_b: Genome, ctx: MutationContext) -> Genome:
		if neuron_crossover != null:
			neuron_crossover.begin_crossover(parent_a, parent_b, ctx)
		var child := Genome.new()
		for n: NodeGene in parent_a.nodes.values():
			child.add_node(n.duplicate())
		for n: NodeGene in parent_b.nodes.values():
			if not child.has_node(n.id):
				child.add_node(n.duplicate())
		# Determine less-fit parent (for fallback removal).
		var less_fit: Genome = parent_b if parent_a.fitness >= parent_b.fitness else parent_a
		# Shared connections first.
		var shared: Array[int] = []
		var disjoints_a: Array[int] = []  # only in A
		var disjoints_b: Array[int] = []  # only in B
		var all_innovs: Dictionary = {}
		for innov: int in parent_a.connections:
			all_innovs[innov] = true
		for innov: int in parent_b.connections:
			all_innovs[innov] = true
		var sorted_innovs: Array[int] = []
		for innov: int in all_innovs:
			sorted_innovs.append(innov)
		sorted_innovs.sort()
		for innov: int in sorted_innovs:
			var has_a: bool = parent_a.connections.has(innov)
			var has_b: bool = parent_b.connections.has(innov)
			if has_a and has_b:
				shared.append(innov)
			elif has_a:
				disjoints_a.append(innov)
			else:
				disjoints_b.append(innov)
		# Add shared connections.
		for innov: int in shared:
			var ca: ConnectionGene = parent_a.connections[innov]
			var cb: ConnectionGene = parent_b.connections[innov]
			var w: float
			if neuron_crossover is NeuronCrossover.StandardAll:
				w = (neuron_crossover as NeuronCrossover.StandardAll).merge_weight_for_pair(ca.from_node, ca.to_node, ca.weight, cb.weight, ctx)
			elif neuron_crossover != null:
				w = neuron_crossover.merge_weight(innov, ca.weight, cb.weight, parent_a.fitness, parent_b.fitness, ctx)
			else:
				w = ca.weight
			var enabled := ca.enabled or cb.enabled
			child.add_connection(ConnectionGene.new(innov, ca.from_node, ca.to_node, w, enabled))
		# Try to add all disjoints from both parents. If loops form, drop from less-fit parent.
		var less_fit_disjoints: Array[int] = disjoints_b if less_fit == parent_b else disjoints_a
		var more_fit_disjoints: Array[int] = disjoints_a if less_fit == parent_b else disjoints_b
		var less_fit_parent: Genome = less_fit
		var more_fit_parent: Genome = parent_a if less_fit == parent_b else parent_b
		# Add more-fit disjoints first (always kept).
		for innov: int in more_fit_disjoints:
			var c: ConnectionGene = more_fit_parent.connections[innov]
			if ctx.forbid_loops and child.would_create_loop(c.from_node, c.to_node):
				continue
			child.add_connection(c.duplicate())
		# Add less-fit disjoints, dropping any that cause loops.
		for innov: int in less_fit_disjoints:
			var c: ConnectionGene = less_fit_parent.connections[innov]
			if ctx.forbid_loops and child.would_create_loop(c.from_node, c.to_node):
				continue
			child.add_connection(c.duplicate())
		return child


class Excluded:
	extends OverallCrossover
	# Inherit only shared connections + minimal disjoints.
	# Start with no disjoints; if graph is disconnected (some output has no
	# incoming path), add disjoints from the more-fit parent one-by-one
	# (innovation order) until connected.

	func crossover(parent_a: Genome, parent_b: Genome, ctx: MutationContext) -> Genome:
		if neuron_crossover != null:
			neuron_crossover.begin_crossover(parent_a, parent_b, ctx)
		var child := Genome.new()
		for n: NodeGene in parent_a.nodes.values():
			child.add_node(n.duplicate())
		for n: NodeGene in parent_b.nodes.values():
			if not child.has_node(n.id):
				child.add_node(n.duplicate())
		# Determine more-fit parent.
		var more_fit: Genome = parent_a if parent_a.fitness >= parent_b.fitness else parent_b
		var less_fit: Genome = parent_b if more_fit == parent_a else parent_a
		# Find shared connections.
		var shared: Array[int] = []
		var disjoints_more: Array[int] = []
		var disjoints_less: Array[int] = []
		var all_innovs: Dictionary = {}
		for innov: int in parent_a.connections:
			all_innovs[innov] = true
		for innov: int in parent_b.connections:
			all_innovs[innov] = true
		var sorted_innovs: Array[int] = []
		for innov: int in all_innovs:
			sorted_innovs.append(innov)
		sorted_innovs.sort()
		for innov: int in sorted_innovs:
			var has_a: bool = parent_a.connections.has(innov)
			var has_b: bool = parent_b.connections.has(innov)
			if has_a and has_b:
				shared.append(innov)
			elif has_a:
				if more_fit == parent_a:
					disjoints_more.append(innov)
				else:
					disjoints_less.append(innov)
			else:
				if more_fit == parent_b:
					disjoints_more.append(innov)
				else:
					disjoints_less.append(innov)
		# Add shared.
		for innov: int in shared:
			var ca: ConnectionGene = parent_a.connections[innov]
			var cb: ConnectionGene = parent_b.connections[innov]
			var w: float
			if neuron_crossover is NeuronCrossover.StandardAll:
				w = (neuron_crossover as NeuronCrossover.StandardAll).merge_weight_for_pair(ca.from_node, ca.to_node, ca.weight, cb.weight, ctx)
			elif neuron_crossover != null:
				w = neuron_crossover.merge_weight(innov, ca.weight, cb.weight, parent_a.fitness, parent_b.fitness, ctx)
			else:
				w = ca.weight
			var enabled := ca.enabled or cb.enabled
			child.add_connection(ConnectionGene.new(innov, ca.from_node, ca.to_node, w, enabled))
		# If the graph is already connected (every output reachable from some input),
		# we don't need to add any disjoints.
		# Otherwise, add disjoints from more_fit one-by-one until connected.
		var idx := 0
		while not _is_connected(child) and idx < disjoints_more.size():
			var innov: int = disjoints_more[idx]
			var c: ConnectionGene = more_fit.connections[innov]
			if not (ctx.forbid_loops and child.would_create_loop(c.from_node, c.to_node)):
				child.add_connection(c.duplicate())
			idx += 1
		return child

	func _is_connected(genome: Genome) -> bool:
		# True if every output has at least one incoming path from an input/bias.
		genome.rebuild_adjacency()
		var inputs: Array[int] = []
		for n: NodeGene in genome.nodes.values():
			if n.kind == NodeGene.Kind.INPUT or n.kind == NodeGene.Kind.BIAS:
				inputs.append(n.id)
		if inputs.is_empty():
			return true
		var reachable: Dictionary = {}
		var stack: Array[int] = inputs.duplicate()
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			if reachable.has(cur):
				continue
			reachable[cur] = true
			for c: ConnectionGene in (genome._adj_out.get(cur, []) as Array):
				if not reachable.has(c.to_node):
					stack.append(c.to_node)
		for n: NodeGene in genome.nodes.values():
			if n.kind == NodeGene.Kind.OUTPUT and not reachable.has(n.id):
				return false
		return true
