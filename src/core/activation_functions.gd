## Static library of activation functions used by neuron genes.
## Uses an int enum + a dispatch match for speed (no Dictionary lookup per call).
class_name ActivationFunctions

enum Func {
	LINEAR,
	ABSOLUTE,
	SQUARED,
	CUBED,
	BINARY_STEP,
	GAUSSIAN,
	SIGMOID,
	TANH,
	RELU,
	LEAKY_RELU,
	ELU,
	SELU,
	GELU,
	SWISH,
}

# SeLU constants (Klambauer et al. 2017).
const SELU_ALPHA := 1.6732632423543772
const SELU_SCALE := 1.0507009873554805
# GELU constants.
const GELU_C  := 0.7978845608028654   # sqrt(2 / PI)
const GELU_C2 := 0.044715
# Leaky ReLU negative slope.
const LEAKY_SLOPE := 0.01

## Apply the activation function identified by [param f] to a scalar [param x].
static func activate(f: int, x: float) -> float:
	match f:
		Func.LINEAR:
			return x
		Func.ABSOLUTE:
			return absf(x)
		Func.SQUARED:
			return x * x
		Func.CUBED:
			return x * x * x
		Func.BINARY_STEP:
			return 1.0 if x >= 0.0 else 0.0
		Func.GAUSSIAN:
			return exp(-x * x * 0.5)
		Func.SIGMOID:
			return 1.0 / (1.0 + exp(-x))
		Func.TANH:
			return tanh(x)
		Func.RELU:
			return x if x > 0.0 else 0.0
		Func.LEAKY_RELU:
			return x if x > 0.0 else LEAKY_SLOPE * x
		Func.ELU:
			return x if x > 0.0 else exp(x) - 1.0
		Func.SELU:
			return SELU_SCALE * (x if x > 0.0 else SELU_ALPHA * (exp(x) - 1.0))
		Func.GELU:
			return 0.5 * x * (1.0 + tanh(GELU_C * (x + GELU_C2 * x * x * x)))
		Func.SWISH:
			return x / (1.0 + exp(-x))
		_:
			return x

## Human-readable name of an activation function id.
static func name_of(f: int) -> String:
	match f:
		Func.LINEAR: return "linear"
		Func.ABSOLUTE: return "abs"
		Func.SQUARED: return "squared"
		Func.CUBED: return "cubed"
		Func.BINARY_STEP: return "step"
		Func.GAUSSIAN: return "gaussian"
		Func.SIGMOID: return "sigmoid"
		Func.TANH: return "tanh"
		Func.RELU: return "relu"
		Func.LEAKY_RELU: return "leaky_relu"
		Func.ELU: return "elu"
		Func.SELU: return "selu"
		Func.GELU: return "gelu"
		Func.SWISH: return "swish"
		_: return "linear"

## Parse a name back into a Func id. Returns [constant Func.LINEAR] if unknown.
static func from_name(p_name: String) -> int:
	match p_name.to_lower():
		"linear": return Func.LINEAR
		"abs", "absolute": return Func.ABSOLUTE
		"squared": return Func.SQUARED
		"cubed": return Func.CUBED
		"step", "binary_step": return Func.BINARY_STEP
		"gaussian": return Func.GAUSSIAN
		"sigmoid": return Func.SIGMOID
		"tanh": return Func.TANH
		"relu": return Func.RELU
		"leaky_relu": return Func.LEAKY_RELU
		"elu": return Func.ELU
		"selu": return Func.SELU
		"gelu": return Func.GELU
		"swish": return Func.SWISH
		_: return Func.LINEAR

## Array of all function ids (handy for random selection / UI listing).
static func all_ids() -> Array[int]:
	return [
		Func.LINEAR, Func.ABSOLUTE, Func.SQUARED, Func.CUBED, Func.BINARY_STEP,
		Func.GAUSSIAN, Func.SIGMOID, Func.TANH, Func.RELU, Func.LEAKY_RELU,
		Func.ELU, Func.SELU, Func.GELU, Func.SWISH,
	]
