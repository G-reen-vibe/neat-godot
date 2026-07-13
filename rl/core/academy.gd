## Orchestrates N parallel envs in one Godot process.
##
## Architecture
## ------------
## - Each env lives in its own SubViewport (own World2D / physics space).
## - All envs step in lock-step via the main physics loop.
## - Every `decision_period` physics steps the Academy:
##     1. Asks the ActionSource for a batch of actions
##     2. Applies actions to every env
##     3. Reads back obs / reward / done
##     4. Resets any env that reported done
##     5. Updates per-env stats for the preview UI
##
## No networking, no threads, no Python. The Academy is the only
## entry point the trainer will ever need.
extends Node

class_name RLAcademy


## Emitted after every decision step. Carries a snapshot of all env
## stats. Preview UI listens to this.
signal step_completed(stats: Array)

## Emitted once when all envs have been spawned and the Academy is
## ready to step. Preview UI waits for this before building the grid.
signal spawned


## Name of the env to spawn. Must be in RLEnvRegistry.
@export var env_name: String = "cartpole"

## Number of parallel envs to run.
@export var num_envs: int = 16

## Physics frames between action decisions. The env's physics_step
## (and thus _on_physics_step) still runs every frame; only action
## application + obs/reward reading is throttled.
@export var decision_period: int = 1

## If non-empty, env indices in this set are rendered live. The rest
## run with rendering disabled for throughput.
@export var preview_env_indices: PackedInt32Array = []

## SubViewport size for each env (smaller = more envs fit on screen).
@export var env_viewport_size: Vector2i = Vector2i(192, 192)

## Whether to render the envs at all (false = pure headless mode,
## all SubViewport updates disabled).
@export var render_envs: bool = true

## Time scale for the simulation. 1.0 = real-time, 4.0 = 4x speed.
@export var time_scale: float = 1.0


var _envs: Array[RLEnvironment] = []
var _viewports: Array[SubViewport] = []
var _stats: Array[RLEnvStats] = []
var _action_source: RLActionSource = null
var _agents_per_env: int = 1
var _action_dim: int = 1
var _physics_step_count: int = 0
var _spawned: bool = false


func _ready() -> void:
        Engine.time_scale = time_scale
        _spawn_envs()


func _spawn_envs() -> void:
        # Pre-spawn: figure out agent count + action dim from one env.
        # We must add the probe to the tree so its _ready() fires and
        # _collect_agents() runs. Without this, get_agent_count() returns 0.
        var probe := RLEnvRegistry.create(env_name)
        if probe == null:
                push_error("RLAcademy: cannot spawn env '%s'" % env_name)
                return
        add_child(probe)
        _agents_per_env = probe.get_agent_count()
        _action_dim = _infer_action_dim(probe)
        probe.queue_free()
        await get_tree().process_frame

        # Now spawn the real envs
        for i in range(num_envs):
                var env := RLEnvRegistry.create(env_name)
                env.decision_period = decision_period
                env.env_name = env_name

                var vp := SubViewport.new()
                vp.name = "EnvViewport_%d" % i
                vp.size = env_viewport_size
                vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
                vp.disable_3d = true
                vp.transparent_bg = false
                # Each SubViewport gets its own World2D so physics spaces are isolated
                vp.add_child(env)

                add_child(vp)
                _envs.append(env)
                _viewports.append(vp)

                # Ensure the env's Camera2D becomes the active camera for this SubViewport.
                # Must be called AFTER the SubViewport is added to the tree.
                _activate_env_camera(env)

                var stats := RLEnvStats.new()
                stats.env_idx = i
                _stats.append(stats)

                env.reset()

        # Now that _agents_per_env / _action_dim are known, (re-)setup action source
        if _action_source:
                _action_source.setup(num_envs, _agents_per_env, _action_dim)

        _apply_render_visibility()
        _spawned = true
        spawned.emit()


func _apply_render_visibility() -> void:
        # B2 fix: respect render_envs flag
        if not render_envs:
                for vp in _viewports:
                        vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
                return

        if preview_env_indices.is_empty():
                for vp in _viewports:
                        vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
                return
        for i in range(_viewports.size()):
                var vp := _viewports[i]
                if preview_env_indices.has(i):
                        vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
                else:
                        vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Set the action source. Safe to call before or after the Academy spawns.
## If called before, setup() will be re-invoked after spawn with correct dims.
func set_action_source(source: RLActionSource) -> void:
        _action_source = source
        if _action_source and _spawned:
                _action_source.setup(num_envs, _agents_per_env, _action_dim)


func get_stats() -> Array:
        var out: Array = []
        for s in _stats:
                out.append(s.to_dict())
        return out


func _physics_process(delta: float) -> void:
        if not _spawned:
                return
        _physics_step_count += 1

        # B9 fix: env's physics_step (which runs _on_physics_step for scoring,
        # timers, etc.) runs EVERY frame. Only action application + reward
        # reading is throttled by decision_period.
        var is_decision_step: bool = (_physics_step_count % decision_period == 0)

        if is_decision_step:
                # 1. Get actions from the source
                var actions: Array[Array] = []
                if _action_source:
                        actions = _action_source.get_actions(num_envs, _agents_per_env, _action_dim)
                else:
                        for i in range(num_envs):
                                var env_actions: Array[PackedFloat32Array] = []
                                for j in range(_agents_per_env):
                                        env_actions.append(PackedFloat32Array())
                                        env_actions[j].resize(_action_dim)
                                        for k in range(_action_dim):
                                                env_actions[j][k] = 0.0
                                actions.append(env_actions)

                # 2. Apply actions + step + read
                for i in range(num_envs):
                        var env := _envs[i]
                        var env_actions: Array[PackedFloat32Array] = []
                        if i < actions.size():
                                env_actions = actions[i]
                        env.apply_actions(env_actions)
                        env.physics_step(delta)

                        var reward := env.get_reward()
                        _stats[i].steps = env.get_step_count()
                        _stats[i].accumulate(reward)
                        # B1 fix: clear done from PREVIOUS step, will re-set below if done now
                        _stats[i].done = false

                        # 3. Reset if done
                        if env.is_done():
                                env.reset()
                                _stats[i].reset_for_new_episode()
                                # B1 fix: set done AFTER reset_for_new_episode (which clears it)
                                _stats[i].done = true
        else:
                # Non-decision frame: still step env physics so scoring/timers work
                for i in range(num_envs):
                        _envs[i].physics_step(delta)

        # Emit stats every decision step
        if is_decision_step:
                var stat_dicts: Array = []
                for s in _stats:
                        stat_dicts.append(s.to_dict())
                step_completed.emit(stat_dicts)


## Find and activate the first Camera2D in the env so it becomes the
## active camera for its SubViewport. Without this, dynamically created
## SubViewports may not render anything.
func _activate_env_camera(env: RLEnvironment) -> void:
        for child in env.find_children("*", "Camera2D", true, false):
                var cam := child as Camera2D
                cam.make_current()
                return


## Pull action_dim from an env instance.
func _infer_action_dim(env: RLEnvironment) -> int:
        if env.has_method("get_action_dim"):
                return env.get_action_dim()
        if "ACTION_DIM" in env:
                return env.get("ACTION_DIM")
        push_warning("RLAcademy: env has no ACTION_DIM, defaulting to 1")
        return 1


## Pull obs_dim from an env instance.
func _infer_obs_dim(env: RLEnvironment) -> int:
        if env.has_method("get_obs_dim"):
                return env.get_obs_dim()
        if "OBS_DIM" in env:
                return env.get("OBS_DIM")
        push_warning("RLAcademy: env has no OBS_DIM, defaulting to 1")
        return 1


func get_env(idx: int) -> RLEnvironment:
        if idx < 0 or idx >= _envs.size():
                return null
        return _envs[idx]


func get_viewport_for_env(idx: int) -> SubViewport:
        if idx < 0 or idx >= _viewports.size():
                return null
        return _viewports[idx]


func get_num_envs() -> int:
        return _envs.size()


func is_spawned() -> bool:
        return _spawned


# B10 fix: restore time_scale when Academy is freed
func _exit_tree() -> void:
        Engine.time_scale = 1.0
