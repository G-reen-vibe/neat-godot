## 3D variant of [NeatPhysicsEnvironment]. Use this for any env that needs
## 3D physics (RigidBody3D, joints in 3D space, etc.).
class_name NeatPhysicsEnvironment3D
extends Node3D

## The genome currently being evaluated. Set by [method reset].
var genome = null

## Network IO configuration (set by the env factory before reset).
var input_node_ids: Array[int] = []
var bias_node_id: int = -1
var output_node_id: int = -1
var output_node_ids: Array[int] = []

## Reset the environment: move all bodies back to their initial pose, zero
## velocities, bind [param p_genome] as the network being evaluated.
func reset(p_genome = null, rng: RandomNumberGenerator = null) -> void:
	genome = p_genome

## Read the current physics state into a Dictionary of { input_id -> value }
## suitable for feeding back into [Genome.forward].
func get_state() -> Dictionary:
	return {}

## Apply an action (output of [method interpret_output]) to the bodies.
func apply_action(action: Dictionary) -> void:
	pass

func is_done() -> bool:
	return false

func current_fitness() -> float:
	return 0.0

func initial_state() -> Dictionary:
	return get_state()

func interpret_output(output: Dictionary) -> Dictionary:
	return output

func get_visual_state() -> Dictionary:
	return {}

func view_type() -> String:
	return "3d"

func is_physics_based() -> bool:
	return true
