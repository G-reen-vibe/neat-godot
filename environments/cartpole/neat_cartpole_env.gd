## NEAT adapter for the CartPole RL env.
##
## Wraps res://rl/envs/cartpole/cartpole_env.tscn.
##
## Network IO:
##   Inputs (4): cart x, cart vx, pole angle, pole angular velocity
##     (all pre-normalized to [-1, 1] by the RL agent)
##   Outputs (1): cart force in [-1, 1] (tanh), scaled by FORCE_SCALE
##
## Fitness: +1 per step the pole is upright (accumulated from the RL agent's
## per-step reward). Max fitness = max_steps (e.g. 500).
class_name NeatCartPoleEnv
extends NeatRLAdapter

const CARTPOLE_SCENE: PackedScene = preload("res://rl/envs/cartpole/cartpole_env.tscn")

# Drawing constants (in RL env pixel units).
const X_LIMIT_PX := 2.4 * 80.0  # 192.0
const POLE_HALF_LEN_PX := 60.0
const TRACK_Y_PX := 160.0  # ground position


func _get_rl_env_scene() -> PackedScene:
	return CARTPOLE_SCENE


func get_visual_state() -> Dictionary:
	var cart: RigidBody2D = _rl_env.get_node_or_null("Cart") if _rl_env != null else null
	var pole: RigidBody2D = _rl_env.get_node_or_null("Pole") if _rl_env != null else null
	var steps: int = _rl_env.get_step_count() if _rl_env != null else 0
	var d: Dictionary = {
		"steps": steps,
		"max_steps": _rl_env.max_steps if _rl_env != null else 0,
		"done": is_done(),
		"x_threshold": X_LIMIT_PX,
		"pole_half_length": POLE_HALF_LEN_PX,
		"track_y": TRACK_Y_PX,
	}
	if cart != null:
		d["cart_pos"] = cart.position
		d["cart_x"] = cart.position.x
	if pole != null:
		d["pole_pos"] = pole.position
		d["theta"] = pole.rotation
	return d


func is_solved() -> bool:
	return _cumulative_fitness >= float(_neat_max_steps) * 0.95
