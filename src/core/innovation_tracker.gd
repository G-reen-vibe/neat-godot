## Hands out globally-unique innovation numbers within a population.
##
## - Each new connection (a, b) gets the same innovation number as any previous
##   connection with the same (a, b) pair, ensuring two genomes that invent the
##   same connection in the same generation end up with matching innovation
##   numbers. This is what makes NEAT's crossover / similarity test efficient.
## - Each new neuron that splits an existing connection (innovation X) also gets
##   a stable neuron id derived from X, so the same split in two genomes ends up
##   with the same neuron id.
class_name InnovationTracker
extends RefCounted

# Next connection innovation number to allocate.
var _next_conn_innov: int = 0
# Next node id to allocate.
var _next_node_id: int = 0

# Maps "from_id,to_id" -> innovation number.
var _conn_innov: Dictionary = {}
# Maps split-connection-innovation -> new node id.
var _split_node: Dictionary = {}

## Allocate (or look up) the innovation number for a connection [param from_id] -> [param to_id].
func get_connection_innov(from_id: int, to_id: int) -> int:
		var key := _conn_key(from_id, to_id)
		if _conn_innov.has(key):
				return _conn_innov[key]
		var innov := _next_conn_innov
		_next_conn_innov += 1
		_conn_innov[key] = innov
		return innov

## Look up the innovation number for a connection without allocating a new one.
## Returns -1 if the connection has never been created. Used by selectors that
## must not mutate the tracker as a side effect.
func peek_connection_innov(from_id: int, to_id: int) -> int:
		var key := _conn_key(from_id, to_id)
		if _conn_innov.has(key):
				return _conn_innov[key]
		return -1

## Allocate (or look up) the node id produced by splitting connection
## [param conn_innov]. The same split in any genome yields the same node id.
func get_split_node_id(conn_innov: int) -> int:
		if _split_node.has(conn_innov):
				return _split_node[conn_innov]
		var nid := _next_node_id
		_next_node_id += 1
		_split_node[conn_innov] = nid
		return nid

## Look up the split node id for a connection without allocating a new one.
## Returns -1 if the connection has never been split. Used by selectors that
## must not mutate the tracker as a side effect.
func peek_split_node_id(conn_innov: int) -> int:
		if _split_node.has(conn_innov):
				return _split_node[conn_innov]
		return -1

## Allocate a brand-new node id (used for inputs/outputs at population init).
func new_node_id() -> int:
		var nid := _next_node_id
		_next_node_id += 1
		return nid

## Pre-reserve a node id (used when seeding initial inputs/outputs/bias).
func reserve_node_id(p_id: int) -> void:
		if p_id >= _next_node_id:
				_next_node_id = p_id + 1

## Pre-reserve a connection innovation number (used when seeding initial
## fully-connected input/output topologies so the whole population shares the
## same starting innovations).
func reserve_connection_innov(p_innov: int) -> void:
		if p_innov >= _next_conn_innov:
				_next_conn_innov = p_innov + 1

func _conn_key(a: int, b: int) -> String:
		# String key is faster than Vector2i hashing for our use pattern in GDScript.
		return "%d,%d" % [a, b]

## Reset everything (used when starting a new population from scratch).
func clear() -> void:
		_next_conn_innov = 0
		_next_node_id = 0
		_conn_innov.clear()
		_split_node.clear()
