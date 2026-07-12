## Computes a similarity/distance metric between two genomes. Used by speciation
## to decide whether a genome belongs to a given species.
##
## Implementations:
##   - [Standard]: classic NEAT compatibility distance from the original paper:
##       δ = (c1 * E + c2 * D) / N + c3 * W_avg
##     where E = #excess genes, D = #disjoint genes, N = max(|A|, |B|) (or 1 if small),
##     W_avg = average weight difference over shared genes.
##   - [Percentage]: treats missing connections as having weight 0, then
##       diff = Σ |w_a - w_b|  over all innovations present in either
##       total = Σ |w_a| + |w_b|  over all innovations present in either
##       pct  = diff / total
##     This naturally handles missing genes (treats them as weight 0) and
##     returns a value in [0, 1] that can be thresholded directly.
class_name SimilarityTest
extends RefCounted

func distance(a: Genome, b: Genome) -> float:
	return 0.0


class Standard:
	extends SimilarityTest
	# Coefficients from the NEAT paper.
	var c1: float = 1.0  # excess
	var c2: float = 1.0  # disjoint
	var c3: float = 0.4  # weight difference
	# Normalize by max size only if both genomes have more than this many genes.
	var n_threshold: int = 20

	func _init(p_c1: float = 1.0, p_c2: float = 1.0, p_c3: float = 0.4, p_n_threshold: int = 20) -> void:
		c1 = p_c1
		c2 = p_c2
		c3 = p_c3
		n_threshold = p_n_threshold

	func distance(a: Genome, b: Genome) -> float:
		var innovs_a: Dictionary = {}
		for innov: int in a.connections:
			innovs_a[innov] = true
		var innovs_b: Dictionary = {}
		for innov: int in b.connections:
			innovs_b[innov] = true
		# Find min/max innovation in each.
		var max_a: int = -1
		var max_b: int = -1
		for innov: int in innovs_a:
			if innov > max_a:
				max_a = innov
		for innov: int in innovs_b:
			if innov > max_b:
				max_b = innov
		# Count disjoint/excess.
		var disjoint: int = 0
		var excess: int = 0
		var matching: int = 0
		var weight_diff_sum: float = 0.0
		for innov: int in innovs_a:
			if innovs_b.has(innov):
				matching += 1
				var ca: ConnectionGene = a.connections[innov]
				var cb: ConnectionGene = b.connections[innov]
				weight_diff_sum += absf(ca.weight - cb.weight)
			else:
				if innov > max_b:
					excess += 1
				else:
					disjoint += 1
		for innov: int in innovs_b:
			if not innovs_a.has(innov):
				if innov > max_a:
					excess += 1
				else:
					disjoint += 1
		var n: int = maxi(a.connection_count(), b.connection_count())
		if n < n_threshold:
			n = 1
		var w_avg: float = weight_diff_sum / float(maxi(1, matching))
		return (c1 * float(excess) + c2 * float(disjoint)) / float(n) + c3 * w_avg


class Percentage:
	extends SimilarityTest
	# diff = Σ |w_a - w_b| over all innovations in either (missing -> 0)
	# total = Σ |w_a| + |w_b| over all innovations in either
	# pct = diff / total
	# Returns 0 if both genomes are empty.

	func distance(a: Genome, b: Genome) -> float:
		var innovs: Dictionary = {}
		for innov: int in a.connections:
			innovs[innov] = true
		for innov: int in b.connections:
			innovs[innov] = true
		if innovs.is_empty():
			return 0.0
		var diff: float = 0.0
		var total: float = 0.0
		for innov: int in innovs:
			var w_a: float = 0.0
			var w_b: float = 0.0
			if a.connections.has(innov):
				w_a = (a.connections[innov] as ConnectionGene).weight
			if b.connections.has(innov):
				w_b = (b.connections[innov] as ConnectionGene).weight
			diff += absf(w_a - w_b)
			total += absf(w_a) + absf(w_b)
		if total < 1e-9:
			return 0.0 if diff < 1e-9 else 1.0
		return diff / total
