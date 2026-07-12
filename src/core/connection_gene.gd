## A single directed, weighted connection gene inside a [Genome].
## Identified by its innovation number, which is unique across the population
## for a given (from, to) pair at the time of creation.
class_name ConnectionGene
extends RefCounted

var innovation: int = 0
var from_node: int = 0
var to_node: int = 0
var weight: float = 0.0
var enabled: bool = true
# Times this connection's innovation has been chosen by a "least common"
# selector across the species; used as a rarity bias.
var times_selected: int = 0

func _init(p_innov: int = 0, p_from: int = 0, p_to: int = 0, p_weight: float = 0.0, p_enabled: bool = true) -> void:
        innovation = p_innov
        from_node = p_from
        to_node = p_to
        weight = p_weight
        enabled = p_enabled

func duplicate() -> ConnectionGene:
        var c := ConnectionGene.new(innovation, from_node, to_node, weight, enabled)
        c.times_selected = times_selected
        return c

func _to_string() -> String:
        return "Conn#%d(%d->%d,w=%.3f,%s)" % [innovation, from_node, to_node, weight, "on" if enabled else "off"]
