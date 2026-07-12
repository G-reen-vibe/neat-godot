## Tracks per-generation training statistics for graphing.
## Attached to a Population and updated each generation via [method record].
class_name TrainingStatsTracker
extends RefCounted

# Per-generation history arrays.
var generations: Array[int] = []
var best_fitness: Array[float] = []
var avg_fitness: Array[float] = []
var median_fitness: Array[float] = []
var species_count: Array[int] = []
var avg_nodes: Array[float] = []
var avg_conns: Array[float] = []
var max_nodes: Array[int] = []
var max_conns: Array[int] = []
var population_size: Array[int] = []

func record(pop: Population) -> void:
	var gen: int = pop.generation
	var best_f: float = -1e9
	var sum_f: float = 0.0
	var sum_nodes: float = 0.0
	var sum_conns: float = 0.0
	var max_n: int = 0
	var max_c: int = 0
	var fits: Array[float] = []
	for g: Genome in pop.genomes:
		if g.fitness > best_f:
			best_f = g.fitness
		sum_f += g.fitness
		var nc: int = g.node_count()
		var cc: int = g.connection_count()
		sum_nodes += float(nc)
		sum_conns += float(cc)
		if nc > max_n:
			max_n = nc
		if cc > max_c:
			max_c = cc
		fits.append(g.fitness)
	var n: int = maxi(1, pop.genomes.size())
	var avg_f: float = sum_f / float(n)
	fits.sort()
	var median_f: float = fits[fits.size() / 2] if not fits.is_empty() else 0.0
	generations.append(gen)
	best_fitness.append(best_f)
	avg_fitness.append(avg_f)
	median_fitness.append(median_f)
	species_count.append(pop.species_count())
	avg_nodes.append(sum_nodes / float(n))
	avg_conns.append(sum_conns / float(n))
	max_nodes.append(max_n)
	max_conns.append(max_c)
	population_size.append(pop.genomes.size())

func clear() -> void:
	generations.clear()
	best_fitness.clear()
	avg_fitness.clear()
	median_fitness.clear()
	species_count.clear()
	avg_nodes.clear()
	avg_conns.clear()
	max_nodes.clear()
	max_conns.clear()
	population_size.clear()

func size() -> int:
	return generations.size()
