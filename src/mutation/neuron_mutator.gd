## Splits existing connections to insert new hidden neurons.
##
## Standard NEAT behavior: when connection (a -> b) with weight w is split,
## the new neuron n is created with two connections (a -> n) with weight 1.0
## and (n -> b) with weight w. The original connection is disabled (kept for
## historical bookkeeping). The new neuron's id and the two new connections'
## innovation numbers are obtained from [InnovationTracker], so the same split
## performed in any other genome of the same generation yields matching ids.
class_name NeuronMutator
extends RefCounted

# Activation function for newly inserted neurons.
var activation: int = ActivationFunctions.Func.TANH

func _init(p_activation: int = ActivationFunctions.Func.TANH) -> void:
	activation = p_activation

## Splits each connection in [param conns]. Returns the Array of new node ids.
func mutate(genome: Genome, conns: Array, ctx: MutationContext) -> Array[int]:
	var new_ids: Array[int] = []
	for c_v: Variant in conns:
		var c: ConnectionGene = c_v
		if not genome.connections.has(c.innovation):
			continue
		if not c.enabled:
			continue
		var split_node_id := ctx.tracker.get_split_node_id(c.innovation)
		# If this exact split was already done in this genome, skip.
		if genome.has_node(split_node_id):
			continue
		# Create the new hidden neuron.
		var new_node := NodeGene.new(split_node_id, NodeGene.Kind.HIDDEN, activation)
		genome.add_node(new_node)
		# Disable the original connection.
		c.enabled = false
		genome.mark_dirty()
		# Add (a -> n) with weight 1.0.
		var innov_in := ctx.tracker.get_connection_innov(c.from_node, split_node_id)
		genome.add_connection(ConnectionGene.new(innov_in, c.from_node, split_node_id, 1.0))
		# Add (n -> b) with weight = original weight.
		var innov_out := ctx.tracker.get_connection_innov(split_node_id, c.to_node)
		genome.add_connection(ConnectionGene.new(innov_out, split_node_id, c.to_node, c.weight))
		# Update species selection count for Least Common neuron selector.
		if ctx.species != null:
			ctx.species.increment_node_selection(split_node_id)
		new_ids.append(split_node_id)
	return new_ids


class Standard:
	extends NeuronMutator

	func _init(p_activation: int = ActivationFunctions.Func.TANH) -> void:
		super(p_activation)
