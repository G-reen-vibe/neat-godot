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
@export var env_color: Color = Color(0.3, 0.8, 0.4):
	set(v):
		env_color = v
		_apply_color()

func _ready() -> void:
	pressed.connect(func(): selected.emit(env_index))
	_apply_color()

func _apply_color() -> void:
	var sb_normal := get_theme_stylebox("normal") as StyleBoxFlat
	if sb_normal != null:
		sb_normal = (sb_normal.duplicate() as StyleBoxFlat)
		sb_normal.bg_color = env_color.darkened(0.78)
		sb_normal.border_color = env_color.darkened(0.3)
		add_theme_stylebox_override("normal", sb_normal)
	var sb_hover := get_theme_stylebox("hover") as StyleBoxFlat
	if sb_hover != null:
		sb_hover = (sb_hover.duplicate() as StyleBoxFlat)
		sb_hover.bg_color = env_color.darkened(0.65)
		sb_hover.border_color = env_color
		add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed := get_theme_stylebox("pressed") as StyleBoxFlat
	if sb_pressed != null:
		sb_pressed = (sb_pressed.duplicate() as StyleBoxFlat)
		sb_pressed.bg_color = env_color.darkened(0.55)
		add_theme_stylebox_override("pressed", sb_pressed)
	# Update name label color.
	var name_label = get_node_or_null("VBox/NameLabel")
	if name_label != null:
		name_label.add_theme_color_override("font_color", env_color)
