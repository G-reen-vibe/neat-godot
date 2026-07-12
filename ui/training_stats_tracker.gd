## Tracks training stats across generations for display + graphing.
extends RefCounted
class_name TrainingStatsTracker

var best_fitness: float = -1e9
var avg_fitness: float = 0.0
var species_count: int = 0
var generation: int = 0
var history: Array = []
var best_history: Array[float] = []
var avg_history: Array[float] = []
var species_history: Array[int] = []

func record(pop: Population) -> void:
	generation = pop.generation
	species_count = pop.species_count()
	if pop.genomes.is_empty():
		avg_fitness = 0.0
	else:
		var total: float = 0.0
		for g: Genome in pop.genomes:
			total += g.fitness
		avg_fitness = total / float(pop.genomes.size())
	if pop.best_fitness > best_fitness:
		best_fitness = pop.best_fitness
	history.append("gen %d: best=%.3f avg=%.3f sp=%d" % [generation, best_fitness, avg_fitness, species_count])
	if history.size() > 200:
		history.pop_front()
	best_history.append(best_fitness)
	avg_history.append(avg_fitness)
	species_history.append(species_count)
	if best_history.size() > 200:
		best_history.pop_front()
		avg_history.pop_front()
		species_history.pop_front()
