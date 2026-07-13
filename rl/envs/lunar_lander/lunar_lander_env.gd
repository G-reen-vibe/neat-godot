## Lunar Lander environment.
##
## Scene graph (see lunar_lander_env.tscn):
##   LunarLanderEnv (Node2D, RLEnvironment)
##     ├── Ground (StaticBody2D)
##     ├── Pad (StaticBody2D) — landing pad at center
##     ├── Lander (RLResettableBody2D) — the lander
##     ├── LunarLanderAgent (RLAgent)
##     └── Camera2D
##
## Coordinate convention:
##   Origin at center. +x right, +y down.
##   Ground at y=140. Pad at y=130, x=0.
##   Lander starts at y=-100 with random x.
class_name LunarLanderEnv
extends RLEnvironment

const OBS_DIM := 6
const ACTION_DIM := 3


func _ready() -> void:
	env_name = "lunar_lander"
	super._ready()


func _setup() -> void:
	var agent := get_node("LunarLanderAgent") as LunarLanderAgent
	agent._setup()


func get_action_dim() -> int:
	return ACTION_DIM


func get_obs_dim() -> int:
	return OBS_DIM
