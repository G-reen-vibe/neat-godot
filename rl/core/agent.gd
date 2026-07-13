## Base class for all RL agents.
##
## An Agent owns the observation/action/reward contract for a single
## entity inside an environment. The Academy never touches the env's
## physics bodies directly - it always goes through this interface.
##
## Subclasses MUST override: get_observation, set_action, reset.
## Subclasses MAY override: get_reward, is_done, get_info.
class_name RLAgent
extends Node2D

## Called by the Academy to read the current observation vector.
## Must return a PackedFloat32Array of length obs_dim.
func get_observation() -> PackedFloat32Array:
	push_error("RLAgent.get_observation() not overridden: " + str(get_path()))
	return PackedFloat32Array()


## Called by the Academy to apply a single action vector.
## The agent is responsible for translating continuous/discrete
## action values into physics forces, joint targets, etc.
func set_action(action: PackedFloat32Array) -> void:
	push_error("RLAgent.set_action() not overridden: " + str(get_path()))


## Reward for the most recent step. Should be reset to 0 by reset().
func get_reward() -> float:
	return 0.0


## True if the episode has terminated (failure / timeout / success).
func is_done() -> bool:
	return false


## Optional env-specific info dict, passed through to the trainer.
func get_info() -> Dictionary:
	return {}


## Called on episode start. Must fully reset internal state and
## any physics bodies the agent controls.
func reset() -> void:
	push_error("RLAgent.reset() not overridden: " + str(get_path()))


## Called once after _ready() so the agent can cache node refs.
func _setup() -> void:
	pass
