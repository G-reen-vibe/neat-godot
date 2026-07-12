## Abstract base class for evaluation environments. An environment represents
## one simulation that a single genome is run against. To evaluate a population,
## the evaluator creates a fresh environment per genome (or resets and reuses)
## and accumulates fitness.
##
## Subclasses must implement [method reset], [method step], [method is_done],
## and [method current_fitness].
class_name NeatEnvironment
extends RefCounted

## Reset the environment to its initial state.
func reset(rng: RandomNumberGenerator = null) -> void:
        pass

## Run one simulation step given the genome's action. Returns the new state
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
## Subclasses should populate this with whatever data their view needs.
## Default: empty (no visualization).
func get_visual_state() -> Dictionary:
        return {}

## Returns "2d" or "3d" to indicate which view type should render this env.
func view_type() -> String:
        return "2d"
