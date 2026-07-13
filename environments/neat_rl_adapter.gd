## Base adapter that bridges an [RLEnvironment] (from the godot_rl module) to
## the [NeatPhysicsEnvironment] interface expected by the NEAT [SceneEvaluator].
##
## The adapter is a [Node2D] (so it can be added to a SubViewport and stepped
## by the SceneTree's physics frame). It owns a child [RLEnvironment] instance
## (the actual physics world + agents) and translates between the two interfaces:
##
##   NEAT Dictionary<int, float> state  <->  RL PackedFloat32Array observation
##   NEAT Dictionary<int, float> output <->  RL PackedFloat32Array action
##
## Subclasses must override [method _get_rl_env_scene] to specify which RL env
## scene to instantiate. They may also override [method _get_primary_agent_index]
## (for multi-agent envs) and [method get_visual_state] (for visualization).
##
## Reward model: the RL env's per-step reward is accumulated into a cumulative
## fitness via [method current_fitness]. For multi-agent envs (e.g. Pong), only
## the primary agent's reward is accumulated; secondary agents receive a zero
## action (stationary).
##
## Lifecycle (driven by SceneEvaluator during training):
##   1. [method _ready] - instantiate the RL env child, find the primary agent.
##   2. [method reset] - bind the genome, reset the RL env (bodies snap to
##      initial pose via RLResettableBody2D.request_reset).
##   3. state = [method get_state] - read the primary agent's observation.
##   4. output = genome.forward(state)
##   5. action = [method interpret_output](output)
##   6. [method apply_action](action) - call primary_agent.set_action().
##   7. (yield one physics frame - Godot steps all bodies in all worlds)
##      - adapter._physics_process fires -> step_env -> _rl_env.physics_step
##        (game logic: scoring, timers, etc.) + accumulate reward.
##   8. goto 3 until [method is_done] or step cap reached.
##
## Live visualization mode (driven by _physics_process when [member live_mode]
## is true): the inherited [method _live_step] handles reset-if-done, step_env,
## and apply_action using [member live_genome].
class_name NeatRLAdapter
extends NeatPhysicsEnvironment

## The wrapped RLEnvironment (added as a child in _ready).
var _rl_env: RLEnvironment = null

## The primary agent (the one the genome controls).
var _primary_agent: RLAgent = null

## Secondary agents (opponents). Their action is set to zero (stationary).
var _secondary_agents: Array[RLAgent] = []

## Accumulated fitness (cumulative reward from the primary agent).
var _cumulative_fitness: float = 0.0

## Max steps per episode. Set by env_setup_fn via [method set_max_steps].
## Defaults to 0 meaning "use the RL env's own max_steps".
var _neat_max_steps: int = 0


## Override in subclasses to return the RL env PackedScene to instantiate.
func _get_rl_env_scene() -> PackedScene:
        return null


## Override in subclasses to specify which agent index is the "primary"
## (genome-controlled). Default 0 (first agent). For Pong, override to 0
## (left agent); the right agent becomes a stationary secondary.
func _get_primary_agent_index() -> int:
        return 0


func _ready() -> void:
        var scene: PackedScene = _get_rl_env_scene()
        if scene != null:
                _rl_env = scene.instantiate() as RLEnvironment
                add_child(_rl_env)
        if _rl_env == null:
                push_error("NeatRLAdapter[%s]: no RLEnvironment child found" % name)
                return
        # Apply the NEAT max_steps to the RL env (if set). This keeps the RL env's
        # own is_done() (which checks _step_count >= max_steps) consistent with the
        # SceneEvaluator's step cap.
        if _neat_max_steps > 0:
                _rl_env.max_steps = _neat_max_steps
        var agents: Array[RLAgent] = _rl_env.get_agents()
        if agents.is_empty():
                push_error("NeatRLAdapter[%s]: RLEnvironment has no agents" % name)
                return
        var primary_idx: int = clampi(_get_primary_agent_index(), 0, agents.size() - 1)
        _primary_agent = agents[primary_idx]
        for i in range(agents.size()):
                if i != primary_idx:
                        _secondary_agents.append(agents[i])


## Set the max steps per episode. Called by the RunScreen's env_setup_fn.
func set_max_steps(p_max_steps: int) -> void:
        _neat_max_steps = p_max_steps
        if _rl_env != null:
                _rl_env.max_steps = p_max_steps


func reset(p_genome = null, rng: RandomNumberGenerator = null) -> void:
        super.reset(p_genome, rng)
        _cumulative_fitness = 0.0
        # Seed the global RNG from our per-genome-per-episode RNG so the RL env's
        # randf_range calls (in agent.reset() and env._on_reset()) are deterministic
        # per genome + episode. This is the minimal way to make the godot_rl envs
        # reproducible without modifying their code.
        if rng != null:
                seed(rng.randi())
        if _rl_env != null:
                _rl_env.reset()


func get_state() -> Dictionary:
        if _primary_agent == null:
                return {}
        var obs: PackedFloat32Array = _primary_agent.get_observation()
        var d: Dictionary = {}
        for i in range(obs.size()):
                if i < input_node_ids.size():
                        d[input_node_ids[i]] = float(obs[i])
        return d


func interpret_output(output: Dictionary) -> Dictionary:
        var arr := PackedFloat32Array()
        if output_node_ids.size() > 0:
                for oid in output_node_ids:
                        arr.append(float(output.get(oid, 0.0)))
        elif output_node_id >= 0:
                arr.append(float(output.get(output_node_id, 0.0)))
        return {"action_arr": arr}


func apply_action(action: Dictionary) -> void:
        if _primary_agent == null:
                return
        var arr: PackedFloat32Array = action.get("action_arr", PackedFloat32Array())
        _primary_agent.set_action(arr)
        # Secondary agents get a zero action (stationary paddle / opponent).
        if not _secondary_agents.is_empty():
                var zero_arr := PackedFloat32Array()
                zero_arr.resize(maxi(1, arr.size()))
                zero_arr.fill(0.0)
                for agent in _secondary_agents:
                        agent.set_action(zero_arr)


func step_env() -> void:
        if _rl_env == null:
                return
        # Advance the RL env's per-step game logic (scoring, ball speed
        # normalization, etc.). physics_step increments _step_count and calls
        # _on_physics_step. This runs AFTER the physics engine integrated forces
        # for this frame (Godot calls _physics_process after integration).
        _rl_env.physics_step(get_physics_process_delta_time())
        # Accumulate the primary agent's per-step reward. All godot_rl agents
        # return a per-step reward (not a running total), so we add the raw value.
        # For agents whose get_reward() computes live from physics state
        # (cartpole, pong, lunar_lander), this reads the current step's reward.
        # For agents whose get_reward() returns a _cached_reward updated by their
        # own _physics_process (bipedal_walker), this reads the PREVIOUS step's
        # reward (1-frame lag, because parent _physics_process fires before child).
        # The 1-frame lag is acceptable: missing 1 reward out of ~500 is noise.
        if _primary_agent != null:
                _cumulative_fitness += _primary_agent.get_reward()


func is_done() -> bool:
        if _rl_env == null:
                return true
        if _rl_env.is_done():
                return true
        if _primary_agent != null and _primary_agent.is_done():
                return true
        return false


func current_fitness() -> float:
        return _cumulative_fitness


## Freeze/unfreeze all RigidBody2D descendants. RLResettableBody2D extends
## RigidBody2D, so freeze works on it. _integrate_forces still runs on frozen
## bodies (in both FREEZE_MODE_STATIC and FREEZE_MODE_KINEMATIC), so
## request_reset still works for live-mode resets on a frozen env.
func set_bodies_frozen(frozen: bool) -> void:
        for body in find_children("*", "RigidBody2D", true, false):
                body.freeze = frozen


func _physics_process(_delta: float) -> void:
        if live_mode:
                _live_step()
        else:
                step_env()


## Override to provide env-specific visual state for the EnvViewport renderer.
## Default returns an empty dict; subclasses should override.
func get_visual_state() -> Dictionary:
        return {}


## Returns the wrapped RLEnvironment (for subclass use).
func get_rl_env() -> RLEnvironment:
        return _rl_env


## Returns the primary RLAgent (for subclass use).
func get_primary_agent() -> RLAgent:
        return _primary_agent
