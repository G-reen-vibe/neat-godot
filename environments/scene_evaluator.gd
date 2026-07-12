## Evaluator for **physics-based** environments (subclasses of
## [NeatPhysicsEnvironment] or [NeatPhysicsEnvironment3D]).
##
## Batches N genome evaluations across N SubViewports, each with its own
## World2D/3D so the envs do not collide with each other. All N worlds step
## in parallel every physics frame (Godot's PhysicsServer steps every world
## in the SceneTree each tick).
##
## Because physics can only advance via the SceneTree's physics frame, this
## evaluator is a coroutine: [method evaluate_all] returns a coroutine that
## the caller must [code]await[/code].
##
## Speedup is achieved by temporarily raising [member Engine.time_scale] and
## [member Engine.physics_ticks_per_second] for the duration of evaluation.
## These are restored to their original values when evaluation completes.
class_name SceneEvaluator
extends RefCounted

## PackedScene to instantiate per genome slot. Must be a Node2D (or Node3D)
## whose root script extends NeatPhysicsEnvironment (or NeatPhysicsEnvironment3D).
var env_scene: PackedScene

## Number of parallel slots (one SubViewport + env per slot). Should match
## the population size (extra slots are wasted; fewer slots means the
## evaluator runs in batches).
var num_slots: int = 100

## Maximum simulation steps per episode (safety cap).
var max_steps: int = 500

## Forward pass mode: "topological" or "timestep".
var forward_mode: String = "topological"

## Speedup factor for evaluation. [member Engine.time_scale] and
## [member Engine.physics_ticks_per_second] are multiplied by this during
## evaluation. Higher values run faster but may cause physics instability
## in joint-heavy envs. Recommended range: 1.0–4.0.
var speedup: float = 2.0

## Base physics tick rate (per second). The effective rate during evaluation
## is [member base_physics_ticks] × [member speedup].
var base_physics_ticks: int = 60

## Number of episodes to run per genome (averaged). Each episode uses a
## different RNG seed derived from the genome index.
var episodes_per_genome: int = 1

## Whether envs should render their SubViewport during training. Disable for
## maximum speed; enable if you want to peek at training via the inspector.
var render_during_training: bool = false

## Optional: called once per env instance after instantiation to configure
## env-specific constants (input/output node IDs, max_steps, etc.).
## Signature: (env: Node) -> void.
var env_setup_fn: Callable = Callable()

# Internal: pool of (SubViewport, env) pairs.
var _slots: Array = []  # Array[Dictionary] { viewport: SubViewport, env: Node, busy: bool }
var _host: Node = null
var _original_time_scale: float = 1.0
var _original_physics_ticks: int = 60

func _init(p_host: Node, p_env_scene: PackedScene, p_num_slots: int = 100, p_max_steps: int = 500, p_forward_mode: String = "topological") -> void:
        _host = p_host
        env_scene = p_env_scene
        num_slots = p_num_slots
        max_steps = p_max_steps
        forward_mode = p_forward_mode
        _setup_slots()

## Allocate the SubViewport pool. Called once at construction.
func _setup_slots() -> void:
        _slots.clear()
        for i in range(num_slots):
                var env: Node = env_scene.instantiate()
                var is_3d: bool = env is Node3D
                var sv: SubViewport
                if is_3d:
                        sv = SubViewport.new()
                        sv.world_3d = World3D.new()
                        sv.transparent_bg = true
                else:
                        sv = SubViewport.new()
                        sv.world_2d = World2D.new()
                        sv.transparent_bg = true
                sv.size = Vector2i(64, 64)  # minimal size; rendering disabled
                sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
                sv.add_child(env)
                _host.add_child(sv)
                _slots.append({ "viewport": sv, "env": env, "busy": false, "configured": false })

## Evaluate all genomes. Returns an Array[float] of fitnesses parallel to
## [param genomes]. MUST be awaited (this is a coroutine).
func evaluate_all(genomes: Array) -> Array[float]:
        var out: Array[float] = []
        out.resize(genomes.size())
        out.fill(0.0)
        # Run in batches of num_slots.
        var idx: int = 0
        while idx < genomes.size():
                var batch_size: int = mini(num_slots, genomes.size() - idx)
                var batch_fitnesses: Array[float] = await _evaluate_batch(genomes, idx, batch_size)
                for i in range(batch_size):
                        out[idx + i] = batch_fitnesses[i]
                idx += batch_size
        return out

## Evaluate [param batch_size] genomes starting at [param start_idx] in parallel.
func _evaluate_batch(genomes: Array, start_idx: int, batch_size: int) -> Array[float]:
        var out: Array[float] = []
        out.resize(batch_size)
        out.fill(0.0)
        # Begin speedup.
        _begin_speedup()
        # Run episodes.
        var num_episodes: int = maxi(1, episodes_per_genome)
        for ep in range(num_episodes):
                # Reset each env with its genome and a per-genome-per-episode RNG.
                for i in range(batch_size):
                        var env = _slots[i].env
                        # Lazy-configure env (idempotent) the first time it's used.
                        if not _slots[i].configured:
                                if env_setup_fn.is_valid():
                                        env_setup_fn.call(env)
                                _slots[i].configured = true
                        var rng := RandomNumberGenerator.new()
                        rng.seed = (start_idx + i) * 7919 + ep * 31 + 1
                        env.reset(genomes[start_idx + i], rng)
                # Step loop: apply action, yield physics frame, check done.
                var done: Array[bool] = []
                done.resize(batch_size)
                done.fill(false)
                var steps: int = 0
                while steps < max_steps:
                        var all_done: bool = true
                        # Apply actions for non-done envs.
                        for i in range(batch_size):
                                if done[i]:
                                        continue
                                all_done = false
                                var env = _slots[i].env
                                var state: Dictionary = env.get_state()
                                var output: Dictionary = genomes[start_idx + i].forward(state, forward_mode)
                                var action: Dictionary = env.interpret_output(output)
                                env.apply_action(action)
                        if all_done:
                                break
                        # Yield one physics frame so Godot steps all worlds.
                        await _host.get_tree().physics_frame
                        # Check done states.
                        for i in range(batch_size):
                                if not done[i]:
                                        if _slots[i].env.is_done():
                                                done[i] = true
                        steps += 1
                # Collect fitnesses; average over episodes.
                for i in range(batch_size):
                        out[i] += _slots[i].env.current_fitness()
        # Average over episodes.
        for i in range(batch_size):
                out[i] /= float(num_episodes)
        # End speedup.
        _end_speedup()
        return out

func _begin_speedup() -> void:
        _original_time_scale = Engine.time_scale
        _original_physics_ticks = Engine.physics_ticks_per_second
        Engine.time_scale = speedup
        Engine.physics_ticks_per_second = int(float(base_physics_ticks) * speedup)

func _end_speedup() -> void:
        Engine.time_scale = _original_time_scale
        Engine.physics_ticks_per_second = _original_physics_ticks

## Free all pooled slots. Call when the evaluator is no longer needed.
func dispose() -> void:
        for slot in _slots:
                var sv: SubViewport = slot.viewport
                if is_instance_valid(sv):
                        sv.queue_free()
        _slots.clear()
