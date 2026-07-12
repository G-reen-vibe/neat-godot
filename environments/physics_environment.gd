## Abstract base class for **physics-based** evaluation environments.
##
## These envs use real Godot physics bodies (RigidBody2D/3D, joints, etc.) and
## are stepped by the SceneTree's physics frame. The [SceneEvaluator] batches
## N env instances across N SubViewports (each with its own World2D/3D) so
## they all step in parallel.
##
## Lifecycle (driven by SceneEvaluator):
##   1. [method reset] - re-initialize all bodies, bind the genome.
##   2. state = [method get_state] - read body transforms into a state dict.
##   3. output = genome.forward(state)
##   4. action = [method interpret_output](output)
##   5. [method apply_action](action) - queue forces/impulses on bodies.
##   6. (yield one physics frame - Godot steps all bodies in all worlds)
##   7. goto 2 until [method is_done] or step cap reached.
##
## Subclasses must implement [method reset], [method apply_action],
## [method get_state], [method is_done], [method current_fitness].
class_name NeatPhysicsEnvironment
extends Node2D

## The genome currently being evaluated. Set by [method reset].
var genome = null

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
