## A NEAT genome: a directed neural network of [NodeGene]s linked by
## [ConnectionGene]s.
##
## The genome stores its nodes in a Dictionary keyed by id and its connections
## in a Dictionary keyed by innovation number, both for O(1) lookup. Adjacency
## lists and a cached topological order are rebuilt lazily for the forward pass.
##
## Mutation / crossover / speciation logic lives in dedicated strategy classes
## under [code]src/mutation/[/code], [code]src/crossover/[/code],
## [code]src/speciation/[/code]; the genome itself is mostly data + a handful of
## graph helpers.
class_name Genome
extends RefCounted

var nodes: Dictionary = {}            # id (int) -> NodeGene
var connections: Dictionary = {}      # innovation (int) -> ConnectionGene

var fitness: float = 0.0
var adjusted_fitness: float = 0.0
var species_id: int = -1
# Species the genome descended from (used by Standard speciation as a fast
# first-match candidate).
var parent_species_id: int = -1
# Free-form metadata for selectors / strategies (e.g. novelty descriptor).
var metadata: Dictionary = {}

# --- Cached graph state (rebuilt lazily) ---
var _adj_out: Dictionary = {}   # node_id -> Array[ConnectionGene]
var _adj_in: Dictionary = {}    # node_id -> Array[ConnectionGene]
var _topo_order: Array[int] = []
var _topo_dirty: bool = true
var _has_loop: bool = false
# Activation cache used by both forward passes.
var _activation_cache: Dictionary = {}  # node_id -> float

# --- Node accessors ---

func add_node(n: NodeGene) -> void:
        nodes[n.id] = n
        _topo_dirty = true

func remove_node(p_id: int) -> void:
        if not nodes.has(p_id):
                return
        # Remove every connection touching this node.
        var to_remove: Array[int] = []
        for innov: int in connections:
                var c: ConnectionGene = connections[innov]
                if c.from_node == p_id or c.to_node == p_id:
                        to_remove.append(innov)
        for innov: int in to_remove:
                connections.erase(innov)
        nodes.erase(p_id)
        _topo_dirty = true

func get_node(p_id: int) -> NodeGene:
        return nodes.get(p_id)

func has_node(p_id: int) -> bool:
        return nodes.has(p_id)

func input_nodes() -> Array[NodeGene]:
        var out: Array[NodeGene] = []
        for n: NodeGene in nodes.values():
                if n.kind == NodeGene.Kind.INPUT:
                        out.append(n)
        return out

func output_nodes() -> Array[NodeGene]:
        var out: Array[NodeGene] = []
        for n: NodeGene in nodes.values():
                if n.kind == NodeGene.Kind.OUTPUT:
                        out.append(n)
        return out

func bias_nodes() -> Array[NodeGene]:
        var out: Array[NodeGene] = []
        for n: NodeGene in nodes.values():
                if n.kind == NodeGene.Kind.BIAS:
                        out.append(n)
        return out

func hidden_nodes() -> Array[NodeGene]:
        var out: Array[NodeGene] = []
        for n: NodeGene in nodes.values():
                if n.kind == NodeGene.Kind.HIDDEN:
                        out.append(n)
        return out

# --- Connection accessors ---

func add_connection(c: ConnectionGene) -> void:
        connections[c.innovation] = c
        _topo_dirty = true

func remove_connection(p_innov: int) -> void:
        if connections.erase(p_innov):
                _topo_dirty = true

func get_connection(p_innov: int) -> ConnectionGene:
        return connections.get(p_innov)

## Returns the ConnectionGene for (from_id -> to_id) if present, else null.
func find_connection(p_from: int, p_to: int) -> ConnectionGene:
        for c: ConnectionGene in connections.values():
                if c.from_node == p_from and c.to_node == p_to:
                        return c
        return null

## True if a connection (from_id -> to_id) exists (enabled or not).
func has_connection_between(p_from: int, p_to: int) -> bool:
        return find_connection(p_from, p_to) != null

func enabled_connections() -> Array[ConnectionGene]:
        var out: Array[ConnectionGene] = []
        out.assign(connections.values().filter(func(c): return c.enabled))
        return out

func disabled_connections() -> Array[ConnectionGene]:
        var out: Array[ConnectionGene] = []
        out.assign(connections.values().filter(func(c): return not c.enabled))
        return out

func all_connections_sorted_by_innov() -> Array[ConnectionGene]:
        var out: Array[ConnectionGene] = []
        out.assign(connections.values())
        out.sort_custom(func(a, b): return a.innovation < b.innovation)
        return out

func node_count() -> int:
        return nodes.size()

func connection_count() -> int:
        return connections.size()

# --- Adjacency / topological helpers ---

## Rebuild outgoing/incoming adjacency lists from the current enabled
## connections. Disabled connections are ignored by the forward pass and by
## topological sort.
func rebuild_adjacency() -> void:
        _adj_out.clear()
        _adj_in.clear()
        for n_id: int in nodes:
                _adj_out[n_id] = []
                _adj_in[n_id] = []
        for c: ConnectionGene in connections.values():
                if not c.enabled:
                        continue
                if not _adj_out.has(c.from_node):
                        _adj_out[c.from_node] = []
                if not _adj_in.has(c.to_node):
                        _adj_in[c.to_node] = []
                (_adj_out[c.from_node] as Array).append(c)
                (_adj_in[c.to_node] as Array).append(c)

## Returns true if adding a connection from [param p_from] to [param p_to]
## would create a cycle in the *enabled* subgraph.
func would_create_loop(p_from: int, p_to: int) -> bool:
        if p_from == p_to:
                return true
        if not nodes.has(p_from) or not nodes.has(p_to):
                return false
        # If we can already walk from p_to back to p_from, adding p_from -> p_to
        # closes a cycle.
        # Use DFS over the current enabled adjacency.
        if _topo_dirty:
                rebuild_adjacency()
        var visited: Dictionary = {}
        var stack: Array[int] = [p_to]
        while not stack.is_empty():
                var cur: int = stack.pop_back()
                if cur == p_from:
                        return true
                if visited.has(cur):
                        continue
                visited[cur] = true
                var out_arr: Array = _adj_out.get(cur, [])
                for c: ConnectionGene in out_arr:
                        if not visited.has(c.to_node):
                                stack.append(c.to_node)
        return false

## Compute a topological order over the enabled subgraph using Kahn's algorithm.
## Returns true on success (no cycle), false if a cycle exists.
## On success, [member _topo_order] is populated and depths are assigned.
## If the topology hasn't changed since the last call, the cached order is reused.
func compute_topological_order() -> bool:
        if not _topo_dirty and not _topo_order.is_empty():
                return not _has_loop
        if _topo_dirty:
                rebuild_adjacency()
        # In-degree per node (only counting enabled connections).
        var in_deg: Dictionary = {}
        for n_id: int in nodes:
                in_deg[n_id] = 0
        for c: ConnectionGene in connections.values():
                if not c.enabled:
                        continue
                in_deg[c.to_node] = int(in_deg[c.to_node]) + 1
        # Seed with all in-degree-0 nodes.
        var queue: Array[int] = []
        for n_id: int in nodes:
                if in_deg[n_id] == 0:
                        queue.append(n_id)
        _topo_order.clear()
        var depth: Dictionary = {}
        for n_id: int in queue:
                depth[n_id] = 0
        while not queue.is_empty():
                var cur: int = queue.pop_front()
                _topo_order.append(cur)
                var out_arr: Array = _adj_out.get(cur, [])
                for c: ConnectionGene in out_arr:
                        in_deg[c.to_node] = int(in_deg[c.to_node]) - 1
                        var new_d: int = int(depth[cur]) + 1
                        if not depth.has(c.to_node) or new_d > int(depth[c.to_node]):
                                depth[c.to_node] = new_d
                        if in_deg[c.to_node] == 0:
                                queue.append(c.to_node)
        if _topo_order.size() != nodes.size():
                # Cycle detected: not all nodes were ordered.
                _has_loop = true
                return false
        _has_loop = false
        # Persist depth back onto node genes for use by visualizer / selectors.
        for n_id: int in nodes:
                (nodes[n_id] as NodeGene).depth = int(depth.get(n_id, 0))
        _topo_dirty = false
        return true

func has_loop() -> bool:
        if _topo_dirty:
                compute_topological_order()
        return _has_loop

# --- Forward passes ---

## Run the time-stepped forward pass: inputs/bias are clamped, all other nodes
## update synchronously for [param steps] iterations using the previous step's
## activations. Returns a Dictionary of { output_node_id -> activation }.
func forward_timestep(inputs: Dictionary, steps: int = 5) -> Dictionary:
        if _topo_dirty:
                rebuild_adjacency()
        _activation_cache.clear()
        # Seed inputs and bias.
        for n: NodeGene in nodes.values():
                match n.kind:
                        NodeGene.Kind.INPUT:
                                _activation_cache[n.id] = float(inputs.get(n.id, 0.0))
                        NodeGene.Kind.BIAS:
                                _activation_cache[n.id] = 1.0
                        _:
                                _activation_cache[n.id] = 0.0
        # Synchronous update for `steps` iterations.
        var new_values: Dictionary = {}
        for _step in range(steps):
                new_values.clear()
                for n: NodeGene in nodes.values():
                        if n.is_input_like():
                                new_values[n.id] = _activation_cache[n.id]
                                continue
                        var s: float = n.bias
                        for c: ConnectionGene in (_adj_in.get(n.id, []) as Array):
                                s += c.weight * float(_activation_cache[c.from_node])
                        new_values[n.id] = ActivationFunctions.activate(n.activation, s)
                # Swap caches.
                var tmp := _activation_cache
                _activation_cache = new_values
                new_values = tmp
        # Read outputs.
        var out: Dictionary = {}
        for n: NodeGene in nodes.values():
                if n.kind == NodeGene.Kind.OUTPUT:
                        out[n.id] = _activation_cache[n.id]
        return out

## Run the topological-sort forward pass. Requires no cycle in the enabled
## subgraph. Single sweep, deterministic, no iteration needed.
func forward_topological(inputs: Dictionary) -> Dictionary:
        if not compute_topological_order():
                # Fallback: cannot use topo pass on a cyclic graph.
                # Caller should have reverted the mutation that created the cycle.
                # We fall back to a single-step timestep pass to avoid crashing.
                return forward_timestep(inputs, 1)
        _activation_cache.clear()
        for n: NodeGene in nodes.values():
                if n.kind == NodeGene.Kind.INPUT:
                        _activation_cache[n.id] = float(inputs.get(n.id, 0.0))
                elif n.kind == NodeGene.Kind.BIAS:
                        _activation_cache[n.id] = 1.0
                else:
                        _activation_cache[n.id] = 0.0
        for n_id: int in _topo_order:
                var n: NodeGene = nodes[n_id]
                if n.is_input_like():
                        continue
                var s: float = n.bias
                for c: ConnectionGene in (_adj_in.get(n_id, []) as Array):
                        s += c.weight * float(_activation_cache[c.from_node])
                _activation_cache[n_id] = ActivationFunctions.activate(n.activation, s)
        var out: Dictionary = {}
        for n: NodeGene in nodes.values():
                if n.kind == NodeGene.Kind.OUTPUT:
                        out[n.id] = _activation_cache[n.id]
        return out

## Convenience: forward pass with explicit mode.
## [param mode] is one of [code]timestep[/code] / [code]topological[/code].
func forward(inputs: Dictionary, mode: String = "topological", steps: int = 5) -> Dictionary:
        if mode == "timestep":
                return forward_timestep(inputs, steps)
        return forward_topological(inputs)

# --- Cloning ---

func duplicate() -> Genome:
        var g := Genome.new()
        for n: NodeGene in nodes.values():
                g.nodes[n.id] = n.duplicate()
        for c: ConnectionGene in connections.values():
                g.connections[c.innovation] = c.duplicate()
        g.fitness = fitness
        g.adjusted_fitness = adjusted_fitness
        g.species_id = species_id
        g.parent_species_id = parent_species_id
        g.metadata = metadata.duplicate(true)
        g._topo_dirty = true
        return g

# --- Convenience queries for selectors ---

## Returns the list of node ids in the genome that are eligible as connection
## sources (i.e. not OUTPUT-only consumers; we allow any non-output node to be
## a source, and any non-input/bias node to be a target). Standard NEAT rule.
func candidate_sources() -> Array[int]:
        var out: Array[int] = []
        for n: NodeGene in nodes.values():
                if n.kind != NodeGene.Kind.OUTPUT:
                        out.append(n.id)
        return out

func candidate_targets() -> Array[int]:
        var out: Array[int] = []
        for n: NodeGene in nodes.values():
                if not n.is_input_like():
                        out.append(n.id)
        return out

## Connections that are *not currently present* in the genome. Used by
## connection-add selectors. Each entry is a Vector2i(from_id, to_id).
## Only returns pairs that wouldn't immediately create a self-loop or duplicate.
func candidate_new_connections(allow_loop_check: bool = false) -> Array[Vector2i]:
        var present: Dictionary = {}
        for c: ConnectionGene in connections.values():
                present[_pair_key(c.from_node, c.to_node)] = true
        var out: Array[Vector2i] = []
        for src: NodeGene in nodes.values():
                if src.kind == NodeGene.Kind.OUTPUT:
                        continue
                for dst: NodeGene in nodes.values():
                        if dst.is_input_like():
                                continue
                        if src.id == dst.id:
                                continue
                        if present.has(_pair_key(src.id, dst.id)):
                                continue
                        if allow_loop_check and would_create_loop(src.id, dst.id):
                                continue
                        out.append(Vector2i(src.id, dst.id))
        return out

func _pair_key(a: int, b: int) -> String:
        return "%d,%d" % [a, b]

## Mark the cache dirty; call after any structural change done externally
## (e.g. by mutation strategies that bypass [method add_connection] /
## [method add_node]).
func mark_dirty() -> void:
        _topo_dirty = true

func _to_string() -> String:
        return "Genome(nodes=%d,conns=%d,fit=%.3f,species=%d)" % [nodes.size(), connections.size(), fitness, species_id]
