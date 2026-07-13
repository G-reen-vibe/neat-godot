## NEAT adapter for the LunarLander RL env.
##
## Wraps res://rl/envs/lunar_lander/lunar_lander_env.tscn.
##
## Network IO:
##   Inputs (6): lander x, y, vx, vy, angle, angular velocity
##     (all pre-normalized to [-1, 1] by the RL agent)
##   Outputs (3): [main_thrust, left_thrust, right_thrust] in [-1, 1]
##     main_thrust > 0: fires main engine (upward force)
##     left_thrust > 0: fires right-side thruster (pushes left, CCW torque)
##     right_thrust > 0: fires left-side thruster (pushes right, CW torque)
##
## Fitness: accumulated per-step reward from the RL agent:
##   +100 for landing safely, -100 for crashing, -0.3 per step (fuel cost),
##   + proximity bonus when near pad.
##
## Done: landed safely, crashed, or out of bounds.
class_name NeatLunarLanderEnv
extends NeatRLAdapter

const LUNAR_LANDER_SCENE: PackedScene = preload("res://rl/envs/lunar_lander/lunar_lander_env.tscn")

# Drawing constants (in RL env pixel units).
const ARENA_WIDTH := 400.0
const ARENA_HEIGHT := 300.0
const PAD_X := 0.0
const PAD_Y := 130.0
const PAD_HALF_WIDTH := 40.0
const LANDER_HALF_SIZE := 12.0


func _get_rl_env_scene() -> PackedScene:
	return LUNAR_LANDER_SCENE


func get_visual_state() -> Dictionary:
	var lander: RigidBody2D = _rl_env.get_node_or_null("Lander") if _rl_env != null else null
	var steps: int = _rl_env.get_step_count() if _rl_env != null else 0
	var d: Dictionary = {
		"steps": steps,
		"max_steps": _rl_env.max_steps if _rl_env != null else 0,
		"done": is_done(),
		"arena_width": ARENA_WIDTH,
		"arena_height": ARENA_HEIGHT,
		"pad_x": PAD_X,
		"pad_y": PAD_Y,
		"pad_half_width": PAD_HALF_WIDTH,
		"lander_half_size": LANDER_HALF_SIZE,
	}
	if lander != null:
		d["lander_x"] = lander.position.x
		d["lander_y"] = lander.position.y
		d["lander_angle"] = lander.rotation
		d["lander_vx"] = lander.linear_velocity.x
		d["lander_vy"] = lander.linear_velocity.y
	return d


func is_solved() -> bool:
	# Solved = landed safely (reward +100 at episode end).
	return _cumulative_fitness > 50.0
