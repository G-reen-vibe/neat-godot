## Static methods implementing the four "randomization methods" used by NEAT
## to pick an item from a list given each item's value (typically its fitness).
##
## Each method takes:
##   - [param items]: Array of anything
##   - [param values]: Array of floats (parallel to items; treated as fitness)
##   - [param rng]: a RandomNumberGenerator
## and returns the chosen item (or [code]null[/code] if the list is empty).
##
## Methods:
##   - [method gaussian]   treat list as a gaussian distribution; sample then
##                         pick the closest item.
##   - [method triangular] pick an index from a triangular distribution using
##                         the literal formula given in the project spec.
##   - [method roulette]   probability proportional to value / sum(values).
##   - [method inverse_roulette]
##                         probability proportional to (max - value) / sum(max - values).
class_name RandomSelectors

const _EPS: float = 1e-9

## Treat the items' values as samples from a gaussian; sample a new value from
## N(mean, std) of the values; return the item whose value is closest.
static func gaussian(items: Array, values: Array, rng: RandomNumberGenerator) -> Variant:
	var n := items.size()
	if n == 0:
		return null
	if n == 1:
		return items[0]
	var mean: float = 0.0
	for v in values:
		mean += float(v)
	mean /= float(n)
	var variance: float = 0.0
	for v in values:
		var d: float = float(v) - mean
		variance += d * d
	variance /= float(n)
	var std := sqrt(variance)
	if std < _EPS:
		# All values equal; uniform pick.
		return items[rng.randi_range(0, n - 1)]
	var sample := mean + rng.randfn() * std
	var best_idx := 0
	var best_diff := absf(float(values[0]) - sample)
	for i in range(1, n):
		var d := absf(float(values[i]) - sample)
		if d < best_diff:
			best_diff = d
			best_idx = i
	return items[best_idx]

## Triangular distribution over indices.
##
## The spec gave the formula:
## [code]
##   a = items.Count
##   b = 200 / a^2
##   seed = RFloat(0, 100)
##   index = (int)(b*a - sqrt((b*a)^2 - 2*b*seed) / b)
## [/code]
## Taken literally (with C# operator precedence), the sqrt-term is divided by
## [code]b[/code] *first* and then subtracted from [code]b*a[/code]; this
## produces indices well outside [0, a-1] for any list size other than ~14, so
## the formula is almost certainly a parenthesization typo. Mathematically the
## inverse CDF of a triangular distribution peaked at index 0 with base [0, a]
## is [code]x = a - (a/10) * sqrt(100 - seed)[/code], which is exactly what
## [code](b*a - sqrt((b*a)^2 - 2*b*seed)) / b[/code] simplifies to. We implement
## that version (numerator parenthesised) and clamp the result to be safe.
static func triangular(items: Array, values: Array, rng: RandomNumberGenerator) -> Variant:
	var n := items.size()
	if n == 0:
		return null
	if n == 1:
		return items[0]
	var a := float(n)
	var b := 200.0 / (a * a)
	var seed := rng.randf_range(0.0, 100.0)
	var b_a := b * a
	var disc := b_a * b_a - 2.0 * b * seed
	if disc < 0.0:
		disc = 0.0
	var index_raw := (b_a - sqrt(disc)) / b
	var index := int(index_raw)
	if index < 0:
		index = 0
	elif index >= n:
		index = n - 1
	return items[index]

## Standard roulette wheel: probability of item i = values[i] / sum(values).
## Negative values are clamped to 0 (they cannot be selected).
static func roulette(items: Array, values: Array, rng: RandomNumberGenerator) -> Variant:
	var n := items.size()
	if n == 0:
		return null
	if n == 1:
		return items[0]
	var sum: float = 0.0
	for v in values:
		var fv := float(v)
		if fv > 0.0:
			sum += fv
	if sum < _EPS:
		return items[rng.randi_range(0, n - 1)]
	var r := rng.randf() * sum
	var acc: float = 0.0
	for i in range(n):
		var fv := float(values[i])
		if fv > 0.0:
			acc += fv
			if r <= acc:
				return items[i]
	return items[n - 1]

## Inverse roulette: each value is replaced by (max - value) before computing
## probabilities. Items with smaller original values become more likely.
static func inverse_roulette(items: Array, values: Array, rng: RandomNumberGenerator) -> Variant:
	var n := items.size()
	if n == 0:
		return null
	if n == 1:
		return items[0]
	var max_v: float = float(values[0])
	for v in values:
		var fv := float(v)
		if fv > max_v:
			max_v = fv
	var sum: float = 0.0
	for v in values:
		sum += max_v - float(v)
	if sum < _EPS:
		# All values equal to max -> uniform.
		return items[rng.randi_range(0, n - 1)]
	var r := rng.randf() * sum
	var acc: float = 0.0
	for i in range(n):
		acc += max_v - float(values[i])
		if r <= acc:
			return items[i]
	return items[n - 1]

## Pick uniformly at random. Useful as a baseline / for selectors that don't
## care about values.
static func uniform(items: Array, rng: RandomNumberGenerator) -> Variant:
	var n := items.size()
	if n == 0:
		return null
	if n == 1:
		return items[0]
	return items[rng.randi_range(0, n - 1)]

## Dispatch by name. [param method] is one of
## [code]"gaussian"[/code], [code]"triangular"[/code], [code]"roulette"[/code],
## [code]"inverse_roulette"[/code], [code]"uniform"[/code].
static func select(method: String, items: Array, values: Array, rng: RandomNumberGenerator) -> Variant:
	match method:
		"gaussian": return gaussian(items, values, rng)
		"triangular": return triangular(items, values, rng)
		"roulette": return roulette(items, values, rng)
		"inverse_roulette": return inverse_roulette(items, values, rng)
		"uniform": return uniform(items, rng)
		_:
			push_error("RandomSelectors.select: unknown method '%s'" % method)
			return null
