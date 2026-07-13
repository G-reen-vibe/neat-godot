## RigidBody2D that supports reliable teleport-style reset AND optionally
## kinematic drive (velocity set directly each step).
##
## - When kinematic = true: the body is moved by setting its linear_velocity
##   directly each step. A very high mass + lock_rotation prevents
##   collisions from disturbing it. Use for paddles, platforms, etc.
## - When kinematic = false (default): normal dynamic RigidBody2D.
##   Gravity, forces, and collisions all work normally. Use for balls,
##   carts, poles, etc.
##
## Either mode supports request_reset() for reliable teleport-style reset
## via _integrate_forces.
class_name RLResettableBody2D
extends RigidBody2D

## If true, this body is moved by setting linear_velocity directly
## (high mass prevents collisions from disturbing it). If false,
## it's a normal dynamic body.
@export var kinematic: bool = false

var _pending_transform: Transform2D = Transform2D.IDENTITY
var _pending_linear_velocity: Vector2 = Vector2.ZERO
var _pending_angular_velocity: float = 0.0
var _has_pending_reset: bool = false


func _ready() -> void:
	if kinematic:
		# High mass so ball collisions don't push us.
		mass = 10000.0
		lock_rotation = true
		gravity_scale = 0.0


func request_reset(new_transform: Transform2D,
		new_linear_velocity: Vector2 = Vector2.ZERO,
		new_angular_velocity: float = 0.0) -> void:
	_pending_transform = new_transform
	_pending_linear_velocity = new_linear_velocity
	_pending_angular_velocity = new_angular_velocity
	_has_pending_reset = true


## Set the velocity for kinematic movement. Only meaningful when
## kinematic = true. For kinematic bodies we set linear_velocity
## directly; the physics engine moves the body.
func set_kinematic_velocity(v: Vector2) -> void:
	linear_velocity = v


func get_kinematic_velocity() -> Vector2:
	return linear_velocity


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _has_pending_reset:
		state.transform = _pending_transform
		state.linear_velocity = _pending_linear_velocity
		state.angular_velocity = _pending_angular_velocity
		_has_pending_reset = false
