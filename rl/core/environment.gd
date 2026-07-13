## Base class for all RL environments.
##
## An Environment is a Node2D that owns the physics world for one
## episode. It contains one or more RLAgents as children and is
## responsible for:
##   - spawning / resetting scene state
##   - any per-step environment logic (moving targets, timers, etc.)
##   - reporting the cumulative reward / done state across agents
##
## Each Environment instance lives inside its own SubViewport with
## its own World2D, so physics never bleeds between parallel envs.
class_name RLEnvironment
extends Node2D

## Display name used by preview/debug UI. Set in subclass _ready().
var env_name: String = "env"

## Decision period in physics frames. The Academy will only poll
## observations / push actions every N physics steps.
@export var decision_period: int = 1

## Max steps before forced reset (safety net for random policies).
@export var max_steps: int = 10000

var _agents: Array[RLAgent] = []
var _step_count: int = 0


func _ready() -> void:
	_collect_agents()
	_setup()


## Find all RLAgent children (recursive).
func _collect_agents() -> void:
	_agents.clear()
	for child in find_children("*", "RLAgent", true, false):
		_agents.append(child as RLAgent)


## Hook for subclasses to do one-time setup.
func _setup() -> void:
	pass


func get_agents() -> Array[RLAgent]:
	return _agents


## Total agents in this env. Usually 1, but pong is 2.
func get_agent_count() -> int:
	return _agents.size()


## Called every physics step by the Academy.
func physics_step(delta: float) -> void:
	_step_count += 1
	_on_physics_step(delta)


## Subclass hook for per-step env logic.
func _on_physics_step(delta: float) -> void:
	pass


## True if any agent is done or we hit max_steps.
func is_done() -> bool:
	if _step_count >= max_steps:
		return true
	for agent in _agents:
		if agent.is_done():
			return true
	return false


## Sum reward across all agents. Most envs have 1 agent so this is
## just that agent's reward; pong with self-play returns the avg.
func get_reward() -> float:
	var total: float = 0.0
	for agent in _agents:
		total += agent.get_reward()
	return total


## Returns obs flattened as [agent_idx][obs_dim]. Most envs have one
## agent so this is a single-element array.
func get_observations() -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	out.resize(_agents.size())
	for i in range(_agents.size()):
		out[i] = _agents[i].get_observation()
	return out


## Apply actions from the Academy. Same shape as get_observations().
func apply_actions(actions: Array[PackedFloat32Array]) -> void:
	for i in range(_agents.size()):
		if i < actions.size():
			_agents[i].set_action(actions[i])


## Full reset: re-randomize scene, reset every agent, clear step count.
func reset() -> void:
	_step_count = 0
	_on_reset()
	for agent in _agents:
		agent.reset()


## Subclass hook for env-specific reset logic (re-position bodies,
## respawn targets, clear timers, etc.).
func _on_reset() -> void:
	pass


## Per-env configuration. Override to read from a Dictionary that
## the Academy passes down (e.g. difficulty, observation mode).
func configure(config: Dictionary) -> void:
	pass


func get_step_count() -> int:
	return _step_count
