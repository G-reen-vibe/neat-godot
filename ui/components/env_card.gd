## Reusable environment selection card. Displays env name + description.
## Click to select. Emits the `selected` signal with the env index.
extends Button
class_name EnvCard

signal selected(index: int)

@export var env_index: int = -1
@export var env_name: String = "":
	set(v):
		env_name = v
		$VBox/NameLabel.text = v
@export var env_desc: String = "":
	set(v):
		env_desc = v
		$VBox/DescLabel.text = v

func _ready() -> void:
	pressed.connect(func(): selected.emit(env_index))
