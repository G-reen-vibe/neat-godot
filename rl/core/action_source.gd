## Source of actions for an RL training session.
##
## Abstract base. Subclasses might be:
##   - RandomActionSource   (used now, for sanity-checking envs)
##   - GAActionSource       (genetic algorithm - future)
##   - ReplayActionSource   (load actions from disk for debugging)
##
## The Academy owns one ActionSource and queries it every decision
## period for a batch of actions across all envs / agents.
class_name RLActionSource
extends RefCounted

## Called once before the first step. Pass any config the source needs.
func setup(num_envs: int, agents_per_env: int, action_dim: int) -> void:
	pass


## Return actions shaped as [env_idx][agent_idx][action_values].
## The Academy will pass this verbatim to env.apply_actions().
func get_actions(num_envs: int, agents_per_env: int, action_dim: int) -> Array[Array]:
	push_error("RLActionSource.get_actions() not overridden")
	return []
