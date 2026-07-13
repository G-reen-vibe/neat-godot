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

## Set to true by reset(), cleared on the next step_env(). When true, step_env
## skips the RL env's physics_step + reward accumulation for that one frame.
## This is needed because the teleport queued by reset() applies during the
## physics server's step (which runs AFTER _physics_process in Godot 4's
## physics frame). Without this skip, the first step_env after reset reads
## stale body positions (pre-teleport), which can trigger false scoring in
## envs like Pong (ball still past the boundary -> another score detected).
var _reset_pending: bool = false

## Set by step_env() to indicate whether this step was skipped (due to
## _reset_pending, _done, or null _rl_env). Subclasses that override step_env()
## should check this after calling super.step_env() and return early if true.
var _step_skipped: bool = false

## Local "done" flag, set after accumulating the final-step reward. Prevents
## re-accumulation on subsequent physics frames (the env stays in the
## SceneTree after is_done() returns true, so _physics_process keeps firing).
## Without this, the reward would be inflated: e.g. Pong's _reward stays at
## +1 after a score, so every frame after done would add +1 to fitness.
## Without the separate flag (just checking is_done() before accumulating),
## the final-step reward (e.g. LunarLander's +100 for safe landing) would
## NEVER be accumulated, because is_done() is already true when step_env
## reads it (the physics engine stepped before _physics_process).
var _done: bool = false

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
        # The RL env renders naturally via its own Camera2D + Polygon2D children
        # inside the SubViewport. No need to hide or disable anything — the
        # SubViewport isolates the rendering from the main viewport.
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
        _reset_pending = true
        _done = false
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
        _step_skipped = false
        if _rl_env == null:
                _step_skipped = true
                return
        # Skip the first step after reset. The teleport queued by reset() applies
        # during the physics server's step, which may not have run yet when this
        # _physics_process fires (Godot 4's physics frame order can vary). Without
        # this skip, _on_physics_step reads stale body positions and can trigger
        # false scoring (e.g. Pong ball still past the boundary).
        if _reset_pending:
                _reset_pending = false
                _step_skipped = true
                return
        # If we've already accumulated the final-step reward, skip all further
        # steps. This prevents re-accumulating the reward on subsequent physics
        # frames (the env stays in the SceneTree after is_done() returns true).
        if _done:
                _step_skipped = true
                return
        # Advance the RL env's per-step game logic (scoring, ball speed
        # normalization, etc.). Only if the env is not already done (the physics
        # engine may have stepped and made the env done before _physics_process).
        # Skip physics_step if done, but still accumulate the reward below to
        # capture the final-step reward (e.g. LunarLander's +100 for safe landing).
        var already_done: bool = _rl_env.is_done() or (_primary_agent != null and _primary_agent.is_done())
        if not already_done:
                _rl_env.physics_step(get_physics_process_delta_time())
        # Accumulate the primary agent's per-step reward. All godot_rl agents
        # return a per-step reward (not a running total), so we add the raw value.
        # This captures the final-step reward even if the env became done during
        # this physics frame.
        if _primary_agent != null:
                _cumulative_fitness += _primary_agent.get_reward()
        # If the env is now done (either from physics_step or from the physics
        # engine's pre-_physics_process step), mark as done so we don't accumulate
        # again on subsequent frames.
        if _rl_env.is_done() or (_primary_agent != null and _primary_agent.is_done()):
                _done = true


func is_done() -> bool:
        if _rl_env == null:
                return true
        if _rl_env.is_done():
                return true
        if _primary_agent != null and _primary_agent.is_done():
                return true
        return false


func current_fitness() -> float:
        # If we've already accumulated the final-step reward (via step_env setting
        # _done), return as-is.
        if _done:
                return _cumulative_fitness
        # If the env is done but step_env hasn't processed the final step yet
        # (because _physics_process fires BEFORE the physics server steps, so
        # step_env reads the PREVIOUS state), add the final reward now. This
        # ensures the SceneEvaluator gets the correct fitness when it calls
        # current_fitness() after detecting is_done().
        # Sets _done = true to prevent double-counting if step_env runs later.
        if _rl_env != null and _primary_agent != null:
                if _rl_env.is_done() or _primary_agent.is_done():
                        _cumulative_fitness += _primary_agent.get_reward()
                        _done = true
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
