## A [RigidBody2D] that supports reliable teleporting via [method _integrate_forces].
##
## In Godot 4, setting [member RigidBody2D.position] / [member RigidBody2D.linear_velocity]
## from outside [method _integrate_forces] is unreliable: the physics server maintains
## its own internal transform/velocity and may overwrite the Node properties on the
## next physics step. This class provides a [method request_teleport] method that
## queues a teleport; the actual state change happens inside [method _integrate_forces],
## where the physics server accepts the new state reliably.
##
## Usage:
## [code]
## body.request_teleport(Transform2D(rot, pos), linear_vel, angular_vel)
## # ... on the next physics step, the body snaps to the new state.
## [/code]
class_name TeleportBody2D
extends RigidBody2D

var _teleport_requested: bool = false
var _teleport_transform: Transform2D = Transform2D.IDENTITY
var _teleport_linear_vel: Vector2 = Vector2.ZERO
var _teleport_angular_vel: float = 0.0

## Queue a teleport. Takes effect on the next [method _integrate_forces] call
## (i.e., the next physics step). Pass [param clear_velocity] = true to zero out
## linear/angular velocity (the common case for reset).
func request_teleport(p_transform: Transform2D, p_linear_vel: Vector2 = Vector2.ZERO, p_angular_vel: float = 0.0) -> void:
	_teleport_requested = true
	_teleport_transform = p_transform
	_teleport_linear_vel = p_linear_vel
	_teleport_angular_vel = p_angular_vel

## Convenience: teleport to a position with zero rotation and given velocities.
func request_teleport_pos(p_pos: Vector2, p_linear_vel: Vector2 = Vector2.ZERO, p_angular_vel: float = 0.0) -> void:
	request_teleport(Transform2D(0.0, p_pos), p_linear_vel, p_angular_vel)

## Cancel any pending teleport (rarely needed).
func cancel_teleport() -> void:
	_teleport_requested = false

## True if a teleport is pending (useful for debugging / tests).
func is_teleport_pending() -> bool:
	return _teleport_requested

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _teleport_requested:
		state.transform = _teleport_transform
		state.linear_velocity = _teleport_linear_vel
		state.angular_velocity = _teleport_angular_vel
		_teleport_requested = false
		# Don't apply other forces this step — the teleport is authoritative.
		return
	# Default integration: do nothing here. RigidBody2D's default _integrate_forces
	# applies gravity and damping; we let that happen by not overriding super.
	# (Godot calls the built-in integration if we don't set custom forces.)
