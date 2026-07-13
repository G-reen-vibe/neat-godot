## Abstract base class for **physics-based** evaluation environments.
##
## These envs use real Godot physics bodies (RigidBody2D/3D, joints, etc.) and
## are stepped by the SceneTree's physics frame. The [SceneEvaluator] batches
## N env instances across N SubViewports (each with its own World2D/3D) so
## they all step in parallel.
##
## Lifecycle (driven by SceneEvaluator during training):
##   1. [method reset] - re-initialize all bodies, bind the genome.
##   2. state = [method get_state] - read body transforms into a state dict.
##   3. output = genome.forward(state)
##   4. action = [method interpret_output](output)
##   5. [method apply_action](action) - queue forces/impulses on bodies.
##   6. (yield one physics frame - Godot steps all bodies in all worlds)
##   7. goto 2 until [method is_done] or step cap reached.
##
## Live visualization mode (driven by the env's own _physics_process when
## [member live_mode] is true):
##   - The env runs [method step_env] + [method apply_action] using
##     [member live_genome] every physics tick.
##   - When [method is_done] returns true, the env auto-resets with
##     [member live_genome] and a fixed RNG seed.
##   - This is the SOLE driver of the live env — no external code calls
##     step_env/apply_action on it. This eliminates the double-driving and
##     stale-state bugs that plagued the previous RunScreen-driven approach.
##
## Subclasses must implement [method reset], [method apply_action],
## [method get_state], [method is_done], [method current_fitness],
## [method step_env], and [method set_bodies_frozen].
class_name NeatPhysicsEnvironment
extends Node2D

## The genome currently being evaluated (training mode). Set by [method reset].
var genome = null

## The genome shown in the live visualization. Set by [method set_live_genome].
## When [member live_mode] is true, the env's _physics_process drives the
## simulation using this genome.
var live_genome: Genome = null

## When true, the env's _physics_process drives the live visualization using
## [member live_genome]. When false, _physics_process only calls step_env()
## (for training envs, where apply_action is called externally by the
## SceneEvaluator).
var live_mode: bool = false

## Forward pass mode for the live genome ("topological" or "timestep").
var live_forward_mode: String = "topological"

## Episode counter for live mode. Incremented every time [method _live_step]
## auto-resets the env because [method is_done] returned true. RunScreen reads
## this to display the episode number in the visualization overlay.
var live_episode_count: int = 0

## Network IO configuration (set by the env factory before reset).
var input_node_ids: Array[int] = []
var bias_node_id: int = -1
var output_node_id: int = -1
var output_node_ids: Array[int] = []

## Reset the environment: move all bodies back to their initial pose, zero
## velocities, bind [param p_genome] as the network being evaluated.
func reset(p_genome = null, rng: RandomNumberGenerator = null) -> void:
        genome = p_genome

## Read the current physics state into a Dictionary of { input_id -> value }
## suitable for feeding back into [Genome.forward].
func get_state() -> Dictionary:
        return {}

## Apply an action (output of [method interpret_output]) to the bodies.
## Forces/impulses queued here take effect on the next physics frame.
func apply_action(action: Dictionary) -> void:
        pass

## True if the simulation has ended (e.g. pole fell, time limit reached).
func is_done() -> bool:
        return false

## Current accumulated fitness for this simulation.
func current_fitness() -> float:
        return 0.0

## Initial state for the first forward pass.
func initial_state() -> Dictionary:
        return get_state()

## Map the network's output (Dictionary of output_id -> activation) to an
## action Dictionary understood by [method apply_action]. Default: identity.
func interpret_output(output: Dictionary) -> Dictionary:
        return output

## Return a Dictionary of renderable state for visualization.
func get_visual_state() -> Dictionary:
        return {}

## Returns "2d" or "3d" to indicate which view type should render this env.
func view_type() -> String:
        return "2d"

## True for physics-based envs. Used by the evaluator to route evaluation.
func is_physics_based() -> bool:
        return true

## Step the env's game logic (increment steps, check done conditions, etc.).
## Subclasses MUST implement this. It is called from _physics_process for both
## training envs (where apply_action is called separately by the SceneEvaluator)
## and live envs (where _live_step handles both step_env and apply_action).
func step_env() -> void:
        pass

## Freeze/unfreeze the env's physics bodies. When frozen, bodies won't move
## even when the physics server steps the world. Used by RunScreen to prevent
## the live env from being affected by SceneEvaluator physics steps during
## training. Subclasses MUST implement this.
func set_bodies_frozen(frozen: bool) -> void:
        pass

## Set the live genome (the genome shown in the visualization). Does NOT
## reset the env — call [method reset] with the same genome to restart the
## simulation from the beginning.
func set_live_genome(g: Genome) -> void:
        live_genome = g

## Enable/disable live mode. When enabled, the env's _physics_process drives
## the simulation using [member live_genome]. When disabled, _physics_process
## only calls step_env() (training mode, where SceneEvaluator calls
## apply_action externally).
##
## NOTE: This does NOT control whether _physics_process runs. Use Godot's
## [method Node.set_physics_process] for that. Typically:
##   - Training envs: set_physics_process(true), live_mode=false
##   - Live env during training: set_physics_process(false), live_mode=false,
##     bodies frozen.
##   - Live env during pause: set_physics_process(true), live_mode=true,
##     bodies unfrozen.
func set_live_mode(enabled: bool) -> void:
        live_mode = enabled

## Drive one live step. Called from the env's _physics_process when
## [member live_mode] is true. Handles: reset-if-done, step_env, apply_action.
##
## Subclasses' _physics_process should call this when live_mode is true:
## [code]
## func _physics_process(delta):
##     if live_mode:
##         _live_step()
##     else:
##         step_env()
## [/code]
func _live_step() -> void:
        if live_genome == null:
                return
        # If done, reset and return (the new episode starts next tick).
        if is_done():
                live_episode_count += 1
                var rng := RandomNumberGenerator.new()
                rng.seed = 12345
                reset(live_genome, rng)
                return
        # Step game logic.
        step_env()
        # If step_env made us done, return (reset happens next tick).
        if is_done():
                return
        # Apply the live genome's action.
        var state: Dictionary = get_state()
        var output: Dictionary = live_genome.forward(state, live_forward_mode)
        var action: Dictionary = interpret_output(output)
        apply_action(action)
