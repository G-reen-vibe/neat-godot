## Bipedal Walker environment.
##
## Scene graph (see bipedal_walker_env.tscn):
##   BipedalWalkerEnv (Node2D, RLEnvironment)
##     ├── Ground (StaticBody2D)
##     ├── Torso (RLResettableBody2D)
##     ├── LeftThigh (RLResettableBody2D) + PinJoint2D to Torso
##     ├── LeftShin (RLResettableBody2D) + PinJoint2D to LeftThigh
##     ├── LeftFoot (RLResettableBody2D) + PinJoint2D to LeftShin
##     ├── RightThigh, RightShin, RightFoot (same pattern)
##     ├── BipedalWalkerAgent (RLAgent)
##     └── Camera2D
##
## Coordinate convention:
##   Origin at center. +x right, +y down.
##   Ground top at y=111. Torso starts at y=30.
##   Feet start at y=108 (bottom at y=111 = ground top).
class_name BipedalWalkerEnv
extends RLEnvironment

const OBS_DIM := 8
const ACTION_DIM := 4


func _ready() -> void:
        env_name = "bipedal_walker"
        super._ready()


func _setup() -> void:
        var agent := get_node("BipedalWalkerAgent") as BipedalWalkerAgent
        agent._setup()


func get_action_dim() -> int:
        return ACTION_DIM


func get_obs_dim() -> int:
        return OBS_DIM
