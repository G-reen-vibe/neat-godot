## Central configuration container for a NEAT run. Holds:
##   - Population / topology params (size, #inputs, #outputs, bias, forward mode).
##   - Hyperparameters for every strategy (selection, mutation, crossover, etc.).
##   - Factory methods to instantiate the configured strategies.
##
## Default values are sensible NEAT-paper defaults; tweak fields before calling
## [method build_strategies].
class_name NeatConfig
extends RefCounted

# --- Topology ---
var num_inputs: int = 2
var num_outputs: int = 1
var use_bias: bool = true
var input_activation: int = ActivationFunctions.Func.LINEAR
var output_activation: int = ActivationFunctions.Func.TANH
var hidden_activation: int = ActivationFunctions.Func.TANH
var initial_weight_range: float = 1.0

# --- Initialization (first generation) ---
# The initial population is built by starting from a bare input/output/bias
# topology and applying a random sequence of connection-add and neuron-add
# mutations to each genome independently. This produces diverse starting
# topologies (different hidden nodes and connection patterns) so speciation
# has meaningful structure to work with from generation 0.
#
# init_min_hidden_nodes / init_max_hidden_nodes: range of extra hidden nodes
#   to add per genome (in addition to the bare inputs/outputs/bias).
# init_min_connections / init_max_connections: range of total connections
#   (including the initial input→output links) to aim for per genome.
#   The actual count is clamped to the maximum feasible (all possible
#   source→target pairs given the genome's nodes).
# init_weight_min / init_weight_max: range for initial connection weights.
var init_min_hidden_nodes: int = 0
var init_max_hidden_nodes: int = 3
var init_min_connections: int = 5
var init_max_connections: int = 20
var init_weight_min: float = -1.0
var init_weight_max: float = 1.0

# --- Population ---
var population_size: int = 150

# --- Forward pass ---
# "topological" or "timestep".
var forward_mode: String = "topological"
var timestep_steps: int = 5

# --- Randomization method ---
# One of "gaussian", "triangular", "roulette", "inverse_roulette", "uniform".
var selection_method: String = "roulette"

# --- Similarity test ---
# "standard" or "percentage".
var similarity_method: String = "standard"
var similarity_c1: float = 1.0
var similarity_c2: float = 1.0
var similarity_c3: float = 0.4
var similarity_n_threshold: int = 20

# --- Speciation ---
# "single", "kmedian", "standard", "purge".
var speciation_method: String = "standard"
var compatibility_threshold: float = 3.0
var target_species_count: int = 10
var max_species_count: int = 20
# How much to adjust the threshold per generation when species count is off
# target. NEAT paper default: 0.3. Separate up/down speeds for fine control:
# threshold_up_speed applies when count > target (threshold increases);
# threshold_down_speed applies when count < target (threshold decreases).
var threshold_up_speed: float = 0.3
var threshold_down_speed: float = 0.3
# Backwards-compat: sets both up and down.
var threshold_adjustment_speed: float:
        get:
                return threshold_up_speed
        set(v):
                threshold_up_speed = v
                threshold_down_speed = v
# Merge ratio: species closer than threshold × merge_ratio are merged.
var merge_ratio: float = 0.5
# Min/max bounds for the threshold.
var min_threshold: float = 0.5
var max_threshold: float = 15.0

# --- Evaluation ---
# "equal", "improvement_rate", "novelty".
var evaluation_method: String = "equal"
var novelty_weight: float = 1.0

# --- Generation ---
# "asexual", "crossover", "mixed".
var generation_method: String = "asexual"
var elite_count: int = 1
var interspecies_rate: float = 0.001
var crossover_rate: float = 0.5

# --- Mutation: which types are enabled and their parameters ---
var enable_weight_mutation: bool = true
# "single" = pick 1 (or min_count) connection(s), apply full delta.
# "all" = apply a small perturbation to ALL enabled connections.
var weight_mutation_mode: String = "single"
var weight_mutation_rate: float = 0.8
var weight_mutation_min: int = 1
var weight_mutation_delta_min: float = -1.0
var weight_mutation_delta_max: float = 1.0
var weight_mutation_normal_std: float = 0.5
# When mode = "all", the delta range is scaled by this factor so each weight
# gets a smaller perturbation than in "single" mode.
var weight_mutation_all_scale: float = 0.1
var weight_mutator_method: String = "standard"  # "standard" or "normal"
var weight_selector_method: String = "standard"  # "standard" or "capped"
var weight_capped_min: float = -3.0
var weight_capped_max: float = 3.0

var enable_connection_mutation: bool = true
var connection_mutation_rate: float = 0.05
var connection_mutation_min: int = 1
var connection_weight_min: float = -1.0
var connection_weight_max: float = 1.0
var connection_weight_normal_std: float = 0.5
var connection_mutator_method: String = "standard"  # "standard", "normal", "safe_gradient"
var connection_selector_method: String = "standard"  # "standard", "least_used", "least_common"

var enable_neuron_mutation: bool = true
var neuron_mutation_rate: float = 0.03
var neuron_mutation_min: int = 1
var neuron_selector_method: String = "standard"  # "standard", "least_common"

var enable_prune_mutation: bool = false
var prune_mutation_rate: float = 0.01
var prune_mutation_min: int = 1
var prune_selector_method: String = "standard"  # "standard", "least_weight"
var prune_mutator_method: String = "disabled"  # "disabled", "non_essential", "merge"

var enable_enable_mutation: bool = false
var enable_mutation_rate: float = 0.01
var enable_mutation_min: int = 1

# --- Mutation policy ---
# "general" or "phased_pruning".
var mutation_policy_method: String = "general"
var mutation_stacked: bool = true
var mutation_rate_multiplier: float = 1.0
var phased_phase_length: int = 5
var phased_pruning_rate_multiplier: float = 3.0

# --- Crossover ---
# "standard", "standard_all", "average", "biased_average".
var neuron_crossover_method: String = "standard"
# "fitter", "bigger", "combine", "excluded".
var overall_crossover_method: String = "fitter"
var biased_average_strength: float = 0.5

# --- Loop prevention ---
var forbid_loops: bool = true  # Required for topological mode.

## Build all strategy instances from this config.
## Returns a Dictionary with keys: similarity, speciation, evaluation, generation,
## mutation_policy, overall_crossover, neuron_crossover.
func build_strategies() -> Dictionary:
        var out: Dictionary = {}
        # Similarity
        match similarity_method:
                "percentage":
                        out["similarity"] = SimilarityTest.Percentage.new()
                _:
                        out["similarity"] = SimilarityTest.Standard.new(similarity_c1, similarity_c2, similarity_c3, similarity_n_threshold)
        # Mutation policy
        out["mutation_policy"] = _build_mutation_policy()
        # Crossover
        var nc := _build_neuron_crossover()
        out["neuron_crossover"] = nc
        out["overall_crossover"] = _build_overall_crossover(nc)
        # Speciation
        match speciation_method:
                "single":
                        out["speciation"] = SpeciationStrategy.Single.new()
                "kmedian":
                        out["speciation"] = SpeciationStrategy.KMedian.new(target_species_count, 5)
                "purge":
                        # Build a Standard delegate with the config's parameters so that
                        # subsequent generations (after the first) use the configured
                        # threshold dynamics, not defaults.
                        var purge_std := SpeciationStrategy.Standard.new(compatibility_threshold, target_species_count)
                        purge_std.threshold_up_speed = threshold_up_speed
                        purge_std.threshold_down_speed = threshold_down_speed
                        purge_std.max_species_count = max_species_count
                        purge_std.merge_ratio = merge_ratio
                        purge_std.min_threshold = min_threshold
                        purge_std.max_threshold = max_threshold
                        out["speciation"] = SpeciationStrategy.Purge.new(out["mutation_policy"], purge_std, target_species_count)
                _:
                        var std_sp := SpeciationStrategy.Standard.new(compatibility_threshold, target_species_count)
                        std_sp.threshold_up_speed = threshold_up_speed
                        std_sp.threshold_down_speed = threshold_down_speed
                        std_sp.max_species_count = max_species_count
                        std_sp.merge_ratio = merge_ratio
                        std_sp.min_threshold = min_threshold
                        std_sp.max_threshold = max_threshold
                        out["speciation"] = std_sp
        # Evaluation
        match evaluation_method:
                "improvement_rate":
                        out["evaluation"] = EvaluationStrategy.ImprovementRate.new()
                "novelty":
                        out["evaluation"] = EvaluationStrategy.Novelty.new(out["similarity"], novelty_weight)
                _:
                        out["evaluation"] = EvaluationStrategy.Equal.new()
        # Generation
        var gs: GenerationStrategy
        match generation_method:
                "crossover":
                        gs = GenerationStrategy.Crossover.new(out["mutation_policy"], out["overall_crossover"])
                "mixed":
                        gs = GenerationStrategy.Mixed.new(out["mutation_policy"], out["overall_crossover"], crossover_rate)
                _:
                        gs = GenerationStrategy.Asexual.new(out["mutation_policy"])
        gs.elite_count = elite_count
        gs.interspecies_rate = interspecies_rate
        gs.selection_method = selection_method
        out["generation"] = gs
        return out

func _build_mutation_policy() -> MutationPolicy:
        var pol: MutationPolicy
        match mutation_policy_method:
                "phased_pruning":
                        var pp := MutationPolicy.PhasedPruning.new(phased_phase_length, phased_pruning_rate_multiplier)
                        pol = pp
                _:
                        pol = MutationPolicy.General.new(mutation_stacked, mutation_rate_multiplier)
        # Weight selector/mutator
        if enable_weight_mutation:
                var ws: WeightSelector
                match weight_selector_method:
                        "capped":
                                ws = WeightSelector.Capped.new(weight_mutation_min, weight_mutation_rate, weight_capped_min, weight_capped_max)
                        _:
                                ws = WeightSelector.Standard.new(weight_mutation_min, weight_mutation_rate)
                var wm: WeightMutator
                match weight_mutator_method:
                        "normal":
                                if weight_mutation_mode == "all":
                                        wm = WeightMutator.Normal.new(0.0, weight_mutation_normal_std * weight_mutation_all_scale)
                                else:
                                        wm = WeightMutator.Normal.new(0.0, weight_mutation_normal_std)
                        _:
                                if weight_mutation_mode == "all":
                                        wm = WeightMutator.Standard.new(weight_mutation_delta_min * weight_mutation_all_scale, weight_mutation_delta_max * weight_mutation_all_scale)
                                else:
                                        wm = WeightMutator.Standard.new(weight_mutation_delta_min, weight_mutation_delta_max)
                # In "all" mode, override the selector to return ALL enabled connections.
                if weight_mutation_mode == "all":
                        ws = WeightSelector.All.new()
                pol.weight_selector = ws
                pol.weight_mutator = wm
        # Connection selector/mutator
        if enable_connection_mutation:
                var cs: ConnectionSelector
                match connection_selector_method:
                        "least_used":
                                cs = ConnectionSelector.LeastUsed.new(connection_mutation_min, connection_mutation_rate, forbid_loops)
                        "least_common":
                                cs = ConnectionSelector.LeastCommon.new(connection_mutation_min, connection_mutation_rate, forbid_loops)
                        _:
                                cs = ConnectionSelector.Standard.new(connection_mutation_min, connection_mutation_rate, forbid_loops)
                var cm: ConnectionMutator
                match connection_mutator_method:
                        "normal":
                                cm = ConnectionMutator.Normal.new(0.0, connection_weight_normal_std)
                        "safe_gradient":
                                cm = ConnectionMutator.SafeGradient.new()
                        _:
                                cm = ConnectionMutator.Standard.new(connection_weight_min, connection_weight_max)
                pol.connection_selector = cs
                pol.connection_mutator = cm
        # Neuron selector/mutator
        if enable_neuron_mutation:
                var ns: NeuronSelector
                match neuron_selector_method:
                        "least_common":
                                ns = NeuronSelector.LeastCommon.new(neuron_mutation_min, neuron_mutation_rate)
                        _:
                                ns = NeuronSelector.Standard.new(neuron_mutation_min, neuron_mutation_rate)
                var nm := NeuronMutator.Standard.new(hidden_activation)
                pol.neuron_selector = ns
                pol.neuron_mutator = nm
        # Prune selector/mutator
        if enable_prune_mutation:
                var ps: PruneSelector
                match prune_selector_method:
                        "least_weight":
                                ps = PruneSelector.LeastWeight.new(prune_mutation_min, prune_mutation_rate)
                        _:
                                ps = PruneSelector.Standard.new(prune_mutation_min, prune_mutation_rate)
                var pm: PruneMutator
                match prune_mutator_method:
                        "non_essential":
                                pm = PruneMutator.PruneNonEssential.new()
                        "merge":
                                pm = PruneMutator.MergePair.new()
                        _:
                                pm = PruneMutator.PruneDisabled.new()
                pol.prune_selector = ps
                pol.prune_mutator = pm
        # Enable selector
        if enable_enable_mutation:
                pol.enable_selector = EnableSelector.Standard.new(enable_mutation_min, enable_mutation_rate)
        return pol

func _build_neuron_crossover() -> NeuronCrossover:
        match neuron_crossover_method:
                "standard_all":
                        return NeuronCrossover.StandardAll.new()
                "average":
                        return NeuronCrossover.Average.new()
                "biased_average":
                        return NeuronCrossover.BiasedAverage.new(biased_average_strength)
                _:
                        return NeuronCrossover.Standard.new()

func _build_overall_crossover(nc: NeuronCrossover) -> OverallCrossover:
        match overall_crossover_method:
                "bigger":
                        return OverallCrossover.Bigger.new(nc)
                "combine":
                        return OverallCrossover.Combine.new(nc)
                "excluded":
                        return OverallCrossover.Excluded.new(nc)
                _:
                        return OverallCrossover.Fitter.new(nc)
