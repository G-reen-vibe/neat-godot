## Prunes (removes) connections from a genome.
##
## Implementations:
##   - [PruneDisabled]: removes the given connections only if they are
##     currently disabled.
##   - [PruneNonEssential]: removes the given connections only if their removal
##     would not isolate any output node (i.e., the output still has at least
##     one incoming path from an input).
##   - [MergePair]: instead of pruning, finds pairs of connections
##     (a -> n) and (n -> b) where n is a hidden neuron with exactly one
##     incoming and one outgoing connection, and replaces them with a single
##     direct connection (a -> b) with weight = w_in * w_out, removing n.
class_name PruneMutator
extends RefCounted

func _init() -> void:
	pass

## Apply the prune. Returns the Array of innovation numbers actually removed
## (or merged-away node ids for [MergePair]).
func mutate(genome: Genome, conns: Array, ctx: MutationContext) -> Array[int]:
	var removed: Array[int] = []
	for c_v: Variant in conns:
		var c: ConnectionGene = c_v
		if genome.connections.has(c.innovation):
			genome.remove_connection(c.innovation)
			removed.append(c.innovation)
	return removed


class PruneDisabled:
	extends PruneMutator

	func mutate(genome: Genome, conns: Array, ctx: MutationContext) -> Array[int]:
		var removed: Array[int] = []
		for c_v: Variant in conns:
			var c: ConnectionGene = c_v
			if genome.connections.has(c.innovation) and not c.enabled:
				genome.remove_connection(c.innovation)
				removed.append(c.innovation)
		return removed


class PruneNonEssential:
	extends PruneMutator
	# Don't prune if it would isolate an output (output has no incoming path).

	func mutate(genome: Genome, conns: Array, ctx: MutationContext) -> Array[int]:
		var removed: Array[int] = []
		for c_v: Variant in conns:
			var c: ConnectionGene = c_v
			if not genome.connections.has(c.innovation):
				continue
			# Tentatively remove.
			genome.remove_connection(c.innovation)
			# Check that every output still has an incoming path from some input.
			if _all_outputs_reachable(genome):
				removed.append(c.innovation)
			else:
				# Re-add.
				genome.add_connection(c.duplicate())
		return removed

	func _all_outputs_reachable(genome: Genome) -> bool:
		genome.rebuild_adjacency()
		var inputs: Array[int] = []
		for n: NodeGene in genome.nodes.values():
			if n.kind == NodeGene.Kind.INPUT or n.kind == NodeGene.Kind.BIAS:
				inputs.append(n.id)
		if inputs.is_empty():
			return true
		# BFS forward from each input; collect reachable set.
		var reachable: Dictionary = {}
		var stack: Array[int] = inputs.duplicate()
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			reachable[cur] = true
			for c: ConnectionGene in (genome._adj_out.get(cur, []) as Array):
				if not reachable.has(c.to_node):
					stack.append(c.to_node)
		# Every output must be reachable.
		for n: NodeGene in genome.nodes.values():
			if n.kind == NodeGene.Kind.OUTPUT and not reachable.has(n.id):
				return false
		return true


class MergePair:
	extends PruneMutator
	# For each candidate connection, check if its source/target neuron is a
	# "linear chain" (1 in, 1 out). If so, merge the pair through that neuron.

	func mutate(genome: Genome, conns: Array, ctx: MutationContext) -> Array[int]:
		var removed_nodes: Array[int] = []
		# Build in-degree/out-degree tables for hidden neurons.
		genome.rebuild_adjacency()
		# We iterate over conns; for each, try to merge via its target if that
		# target is a hidden neuron with in=1, out=1.
		for c_v: Variant in conns:
			var c: ConnectionGene = c_v
			if not genome.connections.has(c.innovation):
				continue
			var mid_node: NodeGene = genome.get_node(c.to_node)
			if mid_node == null or mid_node.kind != NodeGene.Kind.HIDDEN:
				continue
			var in_conns: Array = genome._adj_in.get(mid_node.id, [])
			var out_conns: Array = genome._adj_out.get(mid_node.id, [])
			if in_conns.size() != 1 or out_conns.size() != 1:
				continue
			var in_c: ConnectionGene = in_conns[0]
			var out_c: ConnectionGene = out_conns[0]
			# Skip if in_c == c (we want the *incoming* edge, not c itself).
			# If c is the incoming edge, mid_node is the target -> we want to
			# remove mid_node and connect c.from_node -> out_c.to_node.
			# If c is the outgoing edge, we'd merge via mid_node but using
			# in_c.from_node as the new source. Either way works; just pick
			# based on which edge c is.
			var new_from: int
			var new_to: int
			if c.innovation == in_c.innovation:
				new_from = in_c.from_node
				new_to = out_c.to_node
			elif c.innovation == out_c.innovation:
				new_from = in_c.from_node
				new_to = out_c.to_node
			else:
				continue
			# Avoid creating a self-loop or duplicate.
			if new_from == new_to:
				continue
			if genome.has_connection_between(new_from, new_to):
				continue
			if ctx.forbid_loops and genome.would_create_loop(new_from, new_to):
				continue
			# Perform the merge.
			var merged_weight := in_c.weight * out_c.weight
			var new_innov := ctx.tracker.get_connection_innov(new_from, new_to)
			# Remove the two old connections and the neuron.
			genome.remove_connection(in_c.innovation)
			genome.remove_connection(out_c.innovation)
			genome.remove_node(mid_node.id)
			# Add the merged connection.
			genome.add_connection(ConnectionGene.new(new_innov, new_from, new_to, merged_weight))
			removed_nodes.append(mid_node.id)
			# Rebuild adjacency so subsequent iterations see the new graph.
			genome.rebuild_adjacency()
		return removed_nodes
