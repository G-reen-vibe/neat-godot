## Static helper: registers all built-in envs with RLEnvRegistry.
##
## Call `RLEnvRegistration.register_all()` from a test/preview scene's
## _ready() before instantiating the Academy. We can't use an autoload
## for this because the user explicitly said no autoloads.
extends RefCounted
class_name RLEnvRegistration


static func register_all() -> void:
	if not RLEnvRegistry.has("cartpole"):
		var cartpole_scene := load("res://rl/envs/cartpole/cartpole_env.tscn") as PackedScene
		RLEnvRegistry.register("cartpole", cartpole_scene)
	if not RLEnvRegistry.has("pong"):
		var pong_scene := load("res://rl/envs/pong/pong_env.tscn") as PackedScene
		RLEnvRegistry.register("pong", pong_scene)
	if not RLEnvRegistry.has("lunar_lander"):
		var ll_scene := load("res://rl/envs/lunar_lander/lunar_lander_env.tscn") as PackedScene
		RLEnvRegistry.register("lunar_lander", ll_scene)
	if not RLEnvRegistry.has("bipedal_walker"):
		var bw_scene := load("res://rl/envs/bipedal_walker/bipedal_walker_env.tscn") as PackedScene
		RLEnvRegistry.register("bipedal_walker", bw_scene)
