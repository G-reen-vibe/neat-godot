## Abstract base class for **non-physics** evaluation environments.
##
## These envs have no real-time simulation needs and run synchronously inside
## a threaded evaluator (see [RefCountedEvaluator]). They are RefCounted so
## they can be created/destroyed cheaply in worker threads.
##
## Physics envs (CartPole, Acrobot, Pong, Spiders) subclass
## [NeatPhysicsEnvironment] instead, which is Node-based and stepped by the
## [SceneEvaluator] via the SceneTree's physics frame.
##
## Subclasses must implement [method reset], [method step], [method is_done],
## and [method current_fitness].
class_name NeatEnvironment
extends RefCounted

## Reset the environment to its initial state.
func reset(rng: RandomNumberGenerator = null) -> void:
	pass

## Run one simulation step given the interpreted action. Returns the new state
## (Dictionary of input_id -> value) for the next forward pass.
func step(action: Dictionary) -> Dictionary:
	return {}

## True if the simulation has ended (e.g. pole fell, time limit reached).
func is_done() -> bool:
	return false

## Current accumulated fitness for this simulation.
func current_fitness() -> float:
	return 0.0

## Initial state for the first forward pass (after [method reset]).
func initial_state() -> Dictionary:
	return {}

## Map the network's output (Dictionary of output_id -> activation) to an
## action Dictionary understood by [method step]. Default: identity.
func interpret_output(output: Dictionary) -> Dictionary:
	return output

## Return a Dictionary of renderable state for visualization.
func get_visual_state() -> Dictionary:
	return {}

## Returns "2d" or "3d" to indicate which view type should render this env.
func view_type() -> String:
	return "2d"
