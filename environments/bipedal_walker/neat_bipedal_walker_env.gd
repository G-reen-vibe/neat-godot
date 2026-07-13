## NEAT adapter for the BipedalWalker RL env.
##
## Wraps res://rl/envs/bipedal_walker/bipedal_walker_env.tscn.
##
## Network IO:
##   Inputs (8): left hip angle, left knee angle, right hip angle, right knee
##     angle, torso angle, torso vx, torso vy, ground contact
##     (all pre-normalized to [-1, 1] by the RL agent)
##   Outputs (4): [left_hip_torque, left_knee_torque, right_hip_torque,
##     right_knee_torque] in [-1, 1], scaled by TORQUE_SCALE
##
## Fitness: accumulated per-step reward from the RL agent:
##   +0.1 per step alive + 0.1 * forward_dx, -5 for falling.
##
## Done: torso falls below FALL_Y, or |torso rotation| > 60 deg.
##
## Note: the RL agent's reward is computed in its _physics_process (AFTER
## physics integration). The adapter's step_env reads it via get_reward(),
## which has a 1-frame lag (parent _physics_process fires before child).
## This is acceptable: missing 1 reward out of ~500 steps is noise.
class_name NeatBipedalWalkerEnv
extends NeatRLAdapter

const BIPEDAL_WALKER_SCENE: PackedScene = preload("res://rl/envs/bipedal_walker/bipedal_walker_env.tscn")

# Drawing constants (in RL env pixel units).
const GROUND_Y := 111.0
const FALL_Y := 100.0


func _get_rl_env_scene() -> PackedScene:
	return BIPEDAL_WALKER_SCENE


func get_visual_state() -> Dictionary:
	var torso: RigidBody2D = _rl_env.get_node_or_null("Torso") if _rl_env != null else null
	var left_thigh: RigidBody2D = _rl_env.get_node_or_null("LeftThigh") if _rl_env != null else null
	var left_shin: RigidBody2D = _rl_env.get_node_or_null("LeftShin") if _rl_env != null else null
	var left_foot: RigidBody2D = _rl_env.get_node_or_null("LeftFoot") if _rl_env != null else null
	var right_thigh: RigidBody2D = _rl_env.get_node_or_null("RightThigh") if _rl_env != null else null
	var right_shin: RigidBody2D = _rl_env.get_node_or_null("RightShin") if _rl_env != null else null
	var right_foot: RigidBody2D = _rl_env.get_node_or_null("RightFoot") if _rl_env != null else null
	var steps: int = _rl_env.get_step_count() if _rl_env != null else 0
	var d: Dictionary = {
		"steps": steps,
		"max_steps": _rl_env.max_steps if _rl_env != null else 0,
		"done": is_done(),
		"ground_y": GROUND_Y,
		"fall_y": FALL_Y,
	}
	if torso != null:
		d["torso_x"] = torso.position.x
		d["torso_y"] = torso.position.y
		d["torso_angle"] = torso.rotation
	if left_thigh != null:
		d["left_thigh_pos"] = left_thigh.position
		d["left_thigh_angle"] = left_thigh.rotation
	if left_shin != null:
		d["left_shin_pos"] = left_shin.position
		d["left_shin_angle"] = left_shin.rotation
	if left_foot != null:
		d["left_foot_pos"] = left_foot.position
	if right_thigh != null:
		d["right_thigh_pos"] = right_thigh.position
		d["right_thigh_angle"] = right_thigh.rotation
	if right_shin != null:
		d["right_shin_pos"] = right_shin.position
		d["right_shin_angle"] = right_shin.rotation
	if right_foot != null:
		d["right_foot_pos"] = right_foot.position
	return d


func is_solved() -> bool:
	# Walker is "solved" if it can walk forward significantly.
	# Reward ~0.1/step + 0.1*dx. For 500 steps with dx=0.5/step, reward ~50.
	return _cumulative_fitness > 30.0
