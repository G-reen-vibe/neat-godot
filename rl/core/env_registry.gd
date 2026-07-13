## Maps env type name -> PackedScene.
##
## Centralizes env registration so the Academy can spawn envs by
## string identifier without hardcoding paths. Envs register
## themselves on _ready via RLAcademy.register_env().
class_name RLEnvRegistry
extends RefCounted

static var _registry: Dictionary = {}


static func register(name: String, scene: PackedScene) -> void:
	if _registry.has(name):
		push_warning("RLEnvRegistry: overwriting existing env '%s'" % name)
	_registry[name] = scene


static func has(name: String) -> bool:
	return _registry.has(name)


static func get_env_names() -> PackedStringArray:
	return PackedStringArray(_registry.keys())


static func create(name: String) -> RLEnvironment:
	if not _registry.has(name):
		push_error("RLEnvRegistry: unknown env '%s'" % name)
		return null
	var packed := _registry[name] as PackedScene
	var inst := packed.instantiate()
	if not inst is RLEnvironment:
		push_error("RLEnvRegistry: scene for '%s' is not an RLEnvironment" % name)
		inst.queue_free()
		return null
	return inst as RLEnvironment
