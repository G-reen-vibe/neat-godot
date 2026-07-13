## CartPole environment.
##
## Scene graph (see cartpole_env.tscn):
##   CartPoleEnv (Node2D, RLEnvironment)
##     ├── Ground (StaticBody2D)
##     │     └── CollisionShape2D
##     ├── Cart (RigidBody2D)
##     │     └── CartShape (CollisionShape2D)
##     ├── Pole (RigidBody2D)
##     │     └── PoleShape (CollisionShape2D)
##     ├── PoleJoint (PinJoint2D)   — connects Cart and Pole
##     ├── CartPoleAgent (RLAgent)
##     └── Camera2D
class_name CartPoleEnv
extends RLEnvironment

const OBS_DIM := 4
const ACTION_DIM := 1

var _agent: CartPoleAgent


func _ready() -> void:
	env_name = "cartpole"
	super._ready()


func _setup() -> void:
	_agent = get_node("CartPoleAgent") as CartPoleAgent
	_agent._setup()


func get_action_dim() -> int:
	return ACTION_DIM


func get_obs_dim() -> int:
	return OBS_DIM
