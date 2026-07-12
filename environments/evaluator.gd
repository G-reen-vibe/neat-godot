## Evaluator for **non-physics** environments (subclasses of [NeatEnvironment]
## that are RefCounted, e.g. XOR).
##
## Each genome is evaluated synchronously by:
##   1. Resetting a fresh Environment instance.
##   2. Forward-passing the initial state through the genome.
##   3. Stepping the environment with the output, getting the next state.
##   4. Repeating until the environment is done.
##   5. Returning the environment's final fitness.
##
## Optionally multi-threaded via Godot's WorkerThreadPool — each thread gets
## its own env instance (the env_factory Callable must produce a fresh,
## thread-local env each call).
##
## For environments that require multiple independent "episodes" per genome
## (e.g. averaging over random seeds), use [member episodes_per_genome].
class_name Evaluator
extends RefCounted

# Factory that returns a fresh Environment instance. Use a Callable so each
# thread gets its own (no shared mutable state).
var env_factory: Callable
# Number of episodes to run per genome (averaged). Default 1.
var episodes_per_genome: int = 1
# Maximum simulation steps per episode (safety cap).
var max_steps: int = 1000
# Forward pass mode: "topological" or "timestep".
var forward_mode: String = "topological"
# Number of worker threads. 0 = single-threaded.
var num_threads: int = 0

func _init(p_env_factory: Callable = Callable(), p_max_steps: int = 1000, p_forward_mode: String = "topological") -> void:
        env_factory = p_env_factory
        max_steps = p_max_steps
        forward_mode = p_forward_mode

## Evaluate all genomes in [param genomes] and return an Array[float] of
## fitnesses (parallel to [param genomes]).
func evaluate_all(genomes: Array) -> Array[float]:
        if num_threads <= 1:
                return _evaluate_single_threaded(genomes)
        return _evaluate_multi_threaded(genomes)

func _evaluate_single_threaded(genomes: Array) -> Array[float]:
        var out: Array[float] = []
        out.resize(genomes.size())
        for i in range(genomes.size()):
                out[i] = _evaluate_one(genomes[i], i)
        return out

func _evaluate_multi_threaded(genomes: Array) -> Array[float]:
        var out: Array[float] = []
        out.resize(genomes.size())
        var tasks: Array[Dictionary] = []
        for i in range(genomes.size()):
                var task_id := WorkerThreadPool.add_task(_eval_task.bind(genomes[i], out, i))
                tasks.append({"id": i, "task": task_id})
        for t: Dictionary in tasks:
                WorkerThreadPool.wait_for_task_completion(t["task"])
        return out

# Worker function. Evaluates one genome and writes the result into out[index].
func _eval_task(genome: Genome, out: Array[float], index: int) -> void:
        out[index] = _evaluate_one(genome, index)

# Core evaluation logic for one genome. Uses [param index] to seed a per-genome
# RNG for reproducible per-episode randomization (thread-safe; no shared state).
func _evaluate_one(genome: Genome, index: int) -> float:
        var total_fitness: float = 0.0
        var local_rng := RandomNumberGenerator.new()
        # Seed from the genome index so each genome gets different but reproducible
        # initial states across episodes.
        local_rng.seed = index * 7919 + 1
        for _ep in range(maxi(1, episodes_per_genome)):
                var env: NeatEnvironment = env_factory.call()
                env.reset(local_rng)
                var state: Dictionary = env.initial_state()
                var steps: int = 0
                while not env.is_done() and steps < max_steps:
                        var output: Dictionary = genome.forward(state, forward_mode)
                        var action: Dictionary = env.interpret_output(output)
                        state = env.step(action)
                        steps += 1
                total_fitness += env.current_fitness()
        return total_fitness / float(maxi(1, episodes_per_genome))
