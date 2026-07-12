## Stub - being rewritten. See Phase 5 of the architecture rewrite.
extends Control
class_name SaveLoadView

var population: Population = null
var config: NeatConfig = null
var env_idx: int = -1

func has_pending_load() -> bool:
	return false

func take_pending_load() -> Dictionary:
	return {}
