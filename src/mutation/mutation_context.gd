## Shared context passed into every selector / mutator call. Avoids threading
## long parameter lists through every mutation strategy.
##
## Fields:
##   - [member rng]: shared RNG (may be a thread-local copy for parallel sims).
##   - [member tracker]: global innovation tracker.
##   - [member species]: the species the genome belongs to (for "Least Common"
##     selectors and species-level mutation-rate multipliers). May be null.
##   - [member forward_mode]: forward pass mode in use; "topological" or
##     "timestep". Used by Safe-Mutation-Through-Gradients to choose how to
##     evaluate candidate mutations.
##   - [member forbid_loops]: if true (default), connection-add mutators must
##     avoid creating cycles in the enabled subgraph. Used by the
##     topological-sort forward pass mode.
class_name MutationContext
extends RefCounted

var rng: RandomNumberGenerator
var tracker: InnovationTracker
var species: Species = null
var forward_mode: String = "topological"
var forbid_loops: bool = true
# Multiplier applied to every selector's `rate` during this mutation pass.
# Set by the mutation policy (e.g. species-level mutation-rate adjustment).
var rate_multiplier: float = 1.0

func _init(p_rng: RandomNumberGenerator = null, p_tracker: InnovationTracker = null, p_species: Species = null) -> void:
        rng = p_rng if p_rng != null else RandomNumberGenerator.new()
        tracker = p_tracker if p_tracker != null else InnovationTracker.new()
        species = p_species
