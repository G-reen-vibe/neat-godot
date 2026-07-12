## A NEAT species: a cluster of genomes that are topologically similar.
##
## Species are created/managed by speciation strategies (see
## [code]src/speciation/[/code]); this class is just the data container plus a
## few helpers used by selectors (notably [member selection_counts] for the
## "Least Common" bias) and by evaluation strategies (notably
## [member best_fitness_history] for improvement-rate scoring).
class_name Species
extends RefCounted

var id: int = -1
var members: Array = []  # Array[Genome]
var representative: Genome = null  # used for similarity comparisons
var best_fitness: float = -1e9
var best_fitness_history: Array[float] = []  # per-generation best fitness
var average_fitness: float = 0.0
var average_fitness_history: Array[float] = []  # per-generation average fitness
var staleness: int = 0  # generations since improvement
# Per-innovation selection count for "Least Common" selectors.
# Maps innovation number -> times it has been picked by any Least Common
# selector operating on this species.
var selection_counts: Dictionary = {}
# Per-node-id selection count for "Least Common" neuron selectors.
var node_selection_counts: Dictionary = {}
# Children allocated for next generation (set by evaluation strategy).
var allocated_children: int = 0
# Mutation-rate multiplier applied to all genomes in this species next gen
# (set by evaluation strategies that adjust mutation rate).
var mutation_rate_multiplier: float = 1.0

func _init(p_id: int = -1) -> void:
        id = p_id

func add_member(g: Genome) -> void:
        g.species_id = id
        members.append(g)

func clear_members() -> void:
        members.clear()

func size() -> int:
        return members.size()

func record_generation_stats() -> void:
        var cur_best: float = -1e9
        var sum: float = 0.0
        for g: Genome in members:
                if g.fitness > cur_best:
                        cur_best = g.fitness
                sum += g.fitness
        best_fitness = maxf(best_fitness, cur_best)
        if best_fitness_history.size() == 0 or cur_best > best_fitness_history[-1] + 1e-9:
                staleness = 0
        else:
                staleness += 1
        best_fitness_history.append(cur_best)
        average_fitness = sum / float(maxi(1, members.size()))
        average_fitness_history.append(average_fitness)

func increment_connection_selection(innov: int) -> void:
        selection_counts[innov] = int(selection_counts.get(innov, 0)) + 1

func increment_node_selection(node_id: int) -> void:
        node_selection_counts[node_id] = int(node_selection_counts.get(node_id, 0)) + 1

func connection_selection_count(innov: int) -> int:
        return int(selection_counts.get(innov, 0))

func node_selection_count(node_id: int) -> int:
        return int(node_selection_counts.get(node_id, 0))
