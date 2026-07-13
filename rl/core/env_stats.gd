## Lightweight per-env stats, surfaced to the preview UI.
class_name RLEnvStats
extends RefCounted

var env_idx: int = 0
var episode: int = 0
var steps: int = 0
var episode_reward: float = 0.0
var best_reward: float = -INF
var done: bool = false
var last_episode_reward: float = 0.0


func reset_for_new_episode() -> void:
	last_episode_reward = episode_reward
	episode += 1
	steps = 0
	episode_reward = 0.0
	done = false


func accumulate(reward: float) -> void:
	episode_reward += reward
	if episode_reward > best_reward:
		best_reward = episode_reward


func to_dict() -> Dictionary:
	return {
		"env_idx": env_idx,
		"episode": episode,
		"steps": steps,
		"episode_reward": episode_reward,
		"best_reward": best_reward,
		"done": done,
		"last_episode_reward": last_episode_reward,
	}
