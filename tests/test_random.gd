extends Node
## Test the four randomization methods for distribution sanity.
## Run with: godot --headless --path . res://tests/test_random.tscn

const N: int = 10000

func _ready() -> void:
	print("=== test_random: distribution sanity ===")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var items := [0, 1, 2, 3, 4]
	var values := [1.0, 2.0, 3.0, 4.0, 5.0]

	# Roulette: expected probs proportional to values; sum=15
	# -> 0.0667, 0.1333, 0.2000, 0.2667, 0.3333
	var counts := {0:0, 1:0, 2:0, 3:0, 4:0}
	for _i in range(N):
		var picked = RandomSelectors.roulette(items, values, rng)
		counts[picked] += 1
	print("Roulette counts over %d trials: %s" % [N, counts])
	print("Expected ratios: 0.067,0.133,0.200,0.267,0.333")
	_ensure_within(counts, [0.067, 0.133, 0.200, 0.267, 0.333], 0.05)

	# Inverse roulette: probs proportional to (5 - value); sum=10
	# -> 0.4, 0.3, 0.2, 0.1, 0.0
	counts = {0:0, 1:0, 2:0, 3:0, 4:0}
	for _i in range(N):
		var picked = RandomSelectors.inverse_roulette(items, values, rng)
		counts[picked] += 1
	print("Inverse roulette counts: %s" % [counts])
	print("Expected ratios: 0.4,0.3,0.2,0.1,0.0")
	_ensure_within(counts, [0.4, 0.3, 0.2, 0.1, 0.0], 0.05)

	# Gaussian: should not crash; produces a sensible center-biased pick.
	var g_counts := {0:0, 1:0, 2:0, 3:0, 4:0}
	for _i in range(N):
		var picked = RandomSelectors.gaussian(items, values, rng)
		g_counts[picked] += 1
	print("Gaussian counts: %s" % [g_counts])
	# Sanity: every bin got at least one pick (with this many trials).
	for k in g_counts.keys():
		assert(g_counts[k] > 0, "Gaussian should not starve any bin over %d trials" % N)

	# Triangular: also should not crash and should hit every bin.
	var t_counts := {0:0, 1:0, 2:0, 3:0, 4:0}
	for _i in range(N):
		var picked = RandomSelectors.triangular(items, values, rng)
		t_counts[picked] += 1
	print("Triangular counts: %s" % [t_counts])
	for k in t_counts.keys():
		assert(t_counts[k] > 0, "Triangular should not starve any bin over %d trials" % N)

	# Uniform: roughly equal.
	var u_counts := {0:0, 1:0, 2:0, 3:0, 4:0}
	for _i in range(N):
		var picked = RandomSelectors.uniform(items, rng)
		u_counts[picked] += 1
	print("Uniform counts: %s" % [u_counts])
	_ensure_within(u_counts, [0.2, 0.2, 0.2, 0.2, 0.2], 0.05)

	# Edge cases.
	assert(RandomSelectors.roulette([], [], rng) == null, "Empty roulette -> null")
	assert(RandomSelectors.roulette([42], [1.0], rng) == 42, "Single-item roulette -> that item")
	assert(RandomSelectors.gaussian(["x"], [0.0], rng) == "x", "Single-item gaussian -> that item")
	assert(RandomSelectors.triangular(["x"], [0.0], rng) == "x", "Single-item triangular -> that item")
	assert(RandomSelectors.inverse_roulette(["x"], [0.0], rng) == "x", "Single-item inv-roulette -> that item")

	print("\n=== test_random: ALL PASSED ===")
	get_tree().quit()

func _ensure_within(counts: Dictionary, expected: Array, tol: float) -> void:
	var total: int = 0
	for k in counts.keys():
		total += counts[k]
	for i in range(expected.size()):
		var actual := float(counts[i]) / float(total)
		assert(absf(actual - expected[i]) < tol,
			"Bin %d: expected ~%.3f, got %.3f" % [i, expected[i], actual])
