## Tracks comprehensive training stats across generations for display + graphing.
##
## Records per-generation snapshots of:
##   - Fitness: best (all-time + per-gen), average, median, worst, std dev
##   - Topology: avg/min/max nodes & connections, enabled/disabled ratio
##   - Speciation: species count, compatibility threshold
##   - Per-species details: members, best/avg fitness, staleness, allocated children
##
## Also stores the algorithm configuration (read once from the population's config)
## so the stats view can display what strategies are active.
extends RefCounted
class_name TrainingStatsTracker

# --- Latest snapshot (current generation) ---
var generation: int = 0
var best_fitness: float = -1e9        # all-time best
var gen_best_fitness: float = -1e9    # this generation's best
var avg_fitness: float = 0.0
var median_fitness: float = 0.0
var worst_fitness: float = -1e9
var fitness_std: float = 0.0
var species_count: int = 0
var compatibility_threshold: float = 0.0

# Topology stats (current generation)
var avg_nodes: float = 0.0
var avg_conns: float = 0.0
var min_nodes: int = 0
var max_nodes: int = 0
var min_conns: int = 0
var max_conns: int = 0
var total_enabled_conns: int = 0
var total_disabled_conns: int = 0

# --- History arrays (one entry per generation) ---
var best_history: Array[float] = []          # all-time best per gen
var gen_best_history: Array[float] = []       # per-gen best
var avg_history: Array[float] = []            # per-gen average
var median_history: Array[float] = []         # per-gen median
var worst_history: Array[float] = []          # per-gen worst
var std_history: Array[float] = []            # per-gen std dev
var species_count_history: Array[int] = []    # species count per gen
var threshold_history: Array[float] = []      # compatibility threshold per gen
var avg_nodes_history: Array[float] = []      # avg nodes per gen
var avg_conns_history: Array[float] = []      # avg conns per gen

# --- Per-species snapshot (current generation) ---
## Array of Dictionaries, each with: id, members, best_fitness, avg_fitness,
## staleness, allocated_children, mutation_rate_multiplier, avg_nodes, avg_conns
var species_snapshot: Array = []

# --- Algorithm config (set once via set_config_snapshot) ---
var config_snapshot: Dictionary = {}

# --- History log (text entries for the log view) ---
var history: Array = []
const MAX_HISTORY: int = 500

func record(pop: Population) -> void:
        generation = pop.generation
        species_count = pop.species_count()
        # Fitness stats.
        var fitnesses: Array[float] = []
        fitnesses.resize(pop.genomes.size())
        for i in range(pop.genomes.size()):
                fitnesses[i] = pop.genomes[i].fitness
        if fitnesses.is_empty():
                avg_fitness = 0.0
                median_fitness = 0.0
                worst_fitness = -1e9
                gen_best_fitness = -1e9
                fitness_std = 0.0
        else:
                var total: float = 0.0
                var best_f: float = -1e9
                var worst_f: float = 1e9
                for f in fitnesses:
                        total += f
                        if f > best_f:
                                best_f = f
                        if f < worst_f:
                                worst_f = f
                avg_fitness = total / float(fitnesses.size())
                gen_best_fitness = best_f
                worst_fitness = worst_f
                # Median.
                var sorted_f := fitnesses.duplicate()
                sorted_f.sort()
                var mid: int = sorted_f.size() / 2
                if sorted_f.size() % 2 == 0:
                        median_fitness = (sorted_f[mid - 1] + sorted_f[mid]) / 2.0
                else:
                        median_fitness = sorted_f[mid]
                # Std dev.
                var variance: float = 0.0
                for f in fitnesses:
                        variance += (f - avg_fitness) * (f - avg_fitness)
                variance /= float(fitnesses.size())
                fitness_std = sqrt(variance)
        # All-time best.
        if pop.best_fitness > best_fitness:
                best_fitness = pop.best_fitness
        # Topology stats.
        var nodes_sum: int = 0
        var conns_sum: int = 0
        var nodes_min: int = 1 << 30
        var nodes_max: int = 0
        var conns_min: int = 1 << 30
        var conns_max: int = 0
        total_enabled_conns = 0
        total_disabled_conns = 0
        for g: Genome in pop.genomes:
                var nc: int = g.node_count()
                var cc: int = g.connection_count()
                nodes_sum += nc
                conns_sum += cc
                if nc < nodes_min: nodes_min = nc
                if nc > nodes_max: nodes_max = nc
                if cc < conns_min: conns_min = cc
                if cc > conns_max: conns_max = cc
                total_enabled_conns += g.enabled_connections().size()
                total_disabled_conns += g.disabled_connections().size()
        var pop_size: int = maxi(1, pop.genomes.size())
        avg_nodes = float(nodes_sum) / float(pop_size)
        avg_conns = float(conns_sum) / float(pop_size)
        min_nodes = nodes_min if pop.genomes.size() > 0 else 0
        max_nodes = nodes_max if pop.genomes.size() > 0 else 0
        min_conns = conns_min if pop.genomes.size() > 0 else 0
        max_conns = conns_max if pop.genomes.size() > 0 else 0
        # Compatibility threshold (read defensively from the speciation strategy).
        compatibility_threshold = _read_threshold(pop)
        # Per-species snapshot.
        species_snapshot.clear()
        for sp: Species in pop.species_list:
                var sp_nodes_sum: int = 0
                var sp_conns_sum: int = 0
                var sp_fit_sum: float = 0.0
                var sp_best: float = -1e9
                for m: Genome in sp.members:
                        sp_nodes_sum += m.node_count()
                        sp_conns_sum += m.connection_count()
                        sp_fit_sum += m.fitness
                        if m.fitness > sp_best:
                                sp_best = m.fitness
                var sp_size: int = maxi(1, sp.members.size())
                species_snapshot.append({
                        "id": sp.id,
                        "members": sp.members.size(),
                        "best_fitness": sp_best,
                        "avg_fitness": sp_fit_sum / float(sp_size),
                        "staleness": sp.staleness,
                        "allocated_children": sp.allocated_children,
                        "mutation_rate_multiplier": sp.mutation_rate_multiplier,
                        "avg_nodes": float(sp_nodes_sum) / float(sp_size),
                        "avg_conns": float(sp_conns_sum) / float(sp_size),
                })
        # History arrays.
        best_history.append(best_fitness)
        gen_best_history.append(gen_best_fitness)
        avg_history.append(avg_fitness)
        median_history.append(median_fitness)
        worst_history.append(worst_fitness)
        std_history.append(fitness_std)
        species_count_history.append(species_count)
        threshold_history.append(compatibility_threshold)
        avg_nodes_history.append(avg_nodes)
        avg_conns_history.append(avg_conns)
        # Cap history.
        if best_history.size() > MAX_HISTORY:
                best_history.pop_front()
                gen_best_history.pop_front()
                avg_history.pop_front()
                median_history.pop_front()
                worst_history.pop_front()
                std_history.pop_front()
                species_count_history.pop_front()
                threshold_history.pop_front()
                avg_nodes_history.pop_front()
                avg_conns_history.pop_front()
        # Text log.
        history.append("Gen %d: best=%.3f gen_best=%.3f avg=%.3f med=%.3f worst=%.3f std=%.3f sp=%d thr=%.2f n=%.1f c=%.1f" % [
                generation, best_fitness, gen_best_fitness, avg_fitness, median_fitness,
                worst_fitness, fitness_std, species_count, compatibility_threshold,
                avg_nodes, avg_conns
        ])
        if history.size() > MAX_HISTORY:
                history.pop_front()

## Try to read the current compatibility threshold from the speciation strategy.
## Different strategies store it differently; return 0.0 if not found.
func _read_threshold(pop: Population) -> float:
        if pop == null or pop.speciation == null:
                return 0.0
        # Purge delegates to an internal Standard; read from there.
        if pop.speciation is SpeciationStrategy.Purge:
                var purge := pop.speciation as SpeciationStrategy.Purge
                if purge.standard != null:
                        return purge.standard.compatibility_threshold
                return purge.ideal_threshold
        # Standard and other strategies expose compatibility_threshold directly.
        if "compatibility_threshold" in pop.speciation:
                return float(pop.speciation.get("compatibility_threshold"))
        return 0.0

## Store a snapshot of the algorithm config for display.
func set_config_snapshot(config: NeatConfig) -> void:
        config_snapshot = {
                "population_size": config.population_size,
                "num_inputs": config.num_inputs,
                "num_outputs": config.num_outputs,
                "use_bias": config.use_bias,
                "forward_mode": config.forward_mode,
                "timestep_steps": config.timestep_steps,
                "selection_method": config.selection_method,
                "similarity_method": config.similarity_method,
                "speciation_method": config.speciation_method,
                "evaluation_method": config.evaluation_method,
                "generation_method": config.generation_method,
                "compatibility_threshold": config.compatibility_threshold,
                "target_species_count": config.target_species_count,
                "elite_count": config.elite_count,
                "interspecies_rate": config.interspecies_rate,
                "crossover_rate": config.crossover_rate,
                "weight_mutation_rate": config.weight_mutation_rate,
                "weight_mutation_mode": config.weight_mutation_mode,
                "connection_mutation_rate": config.connection_mutation_rate,
                "neuron_mutation_rate": config.neuron_mutation_rate,
                "prune_mutation_rate": config.prune_mutation_rate,
                "enable_mutation_rate": config.enable_mutation_rate,
                "mutation_policy_method": config.mutation_policy_method,
                "mutation_stacked": config.mutation_stacked,
                "forbid_loops": config.forbid_loops,
                "similarity_c1": config.similarity_c1,
                "similarity_c2": config.similarity_c2,
                "similarity_c3": config.similarity_c3,
                "input_activation": ActivationFunctions.name_of(config.input_activation),
                "output_activation": ActivationFunctions.name_of(config.output_activation),
                "hidden_activation": ActivationFunctions.name_of(config.hidden_activation),
                "init_min_hidden_nodes": config.init_min_hidden_nodes,
                "init_max_hidden_nodes": config.init_max_hidden_nodes,
                "init_min_connections": config.init_min_connections,
                "init_max_connections": config.init_max_connections,
                "neuron_crossover_method": config.neuron_crossover_method,
                "overall_crossover_method": config.overall_crossover_method,
        }

## Format a float for compact display.
func fmt(v: float, decimals: int = 3) -> String:
        var fmt_str: String = "%%.%df" % decimals
        return fmt_str % v
