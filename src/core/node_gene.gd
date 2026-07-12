## A single neuron gene inside a [Genome].
## Lightweight RefCounted; stored in a Dictionary keyed by [member id] inside the genome.
class_name NodeGene
extends RefCounted

# Node type. INPUT/BIAS nodes have no incoming connections in standard NEAT,
# OUTPUT/HIDDEN can receive incoming connections.
enum Kind { INPUT, BIAS, HIDDEN, OUTPUT }

var id: int = 0
var kind: int = Kind.HIDDEN
var activation: int = ActivationFunctions.Func.TANH
# Cached topological depth (0 = inputs/bias, increases along connections).
# -1 means "not computed".
var depth: int = -1
# Bias term applied to the neuron's pre-activation sum. Inputs/bias ignore this.
var bias: float = 0.0
# Counters used by "Least Common" selectors within a species.
var times_selected: int = 0

func _init(p_id: int = 0, p_kind: int = Kind.HIDDEN, p_activation: int = ActivationFunctions.Func.TANH) -> void:
	id = p_id
	kind = p_kind
	activation = p_activation

func is_input_like() -> bool:
	return kind == Kind.INPUT or kind == Kind.BIAS

func duplicate() -> NodeGene:
	var n := NodeGene.new(id, kind, activation)
	n.depth = depth
	n.bias = bias
	n.times_selected = times_selected
	return n

func _to_string() -> String:
	return "Node#%d(%s,act=%s,bias=%.3f)" % [id, _kind_name(), ActivationFunctions.name_of(activation), bias]

func _kind_name() -> String:
	match kind:
		Kind.INPUT: return "IN"
		Kind.BIAS:  return "B"
		Kind.HIDDEN: return "H"
		Kind.OUTPUT: return "OUT"
		_: return "?"
