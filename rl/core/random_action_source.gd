## Yields uniform random actions in [-1, 1] for every env / agent.
##
## Used as a placeholder while the env framework is being built. A
## real GAActionSource will replace this once the training side lands.
class_name RLRandomActionSource
extends RLActionSource

var _rng := RandomNumberGenerator.new()


func _init(seed: int = -1) -> void:
	if seed >= 0:
		_rng.seed = seed
	else:
		_rng.randomize()


func get_actions(num_envs: int, agents_per_env: int, action_dim: int) -> Array[Array]:
	var out: Array[Array] = []
	out.resize(num_envs)
	for i in range(num_envs):
		var env_actions: Array[PackedFloat32Array] = []
		env_actions.resize(agents_per_env)
		for j in range(agents_per_env):
			var a := PackedFloat32Array()
			a.resize(action_dim)
			for k in range(action_dim):
				a[k] = _rng.randf_range(-1.0, 1.0)
			env_actions[j] = a
		out[i] = env_actions
	return out
