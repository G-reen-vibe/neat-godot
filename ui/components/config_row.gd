## Reusable config row: a label + a control (SpinBox / OptionButton / CheckButton).
## The control is created dynamically based on the `kind` property.
extends HBoxContainer
class_name ConfigRow

@export var key: String = ""
@export var label_text: String = "":
	set(v):
		label_text = v
		$Label.text = v

var _control: Control = null

func set_kind(kind: String, opts: Dictionary = {}) -> void:
	if _control != null:
		_control.queue_free()
		_control = null
	match kind:
		"int":
			var spin := SpinBox.new()
			spin.min_value = opts.get("min", 0)
			spin.max_value = opts.get("max", 9999)
			spin.step = opts.get("step", 1)
			spin.value = opts.get("value", 0)
			spin.custom_minimum_size = Vector2(120, 28)
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_control = spin
		"float":
			var spin := SpinBox.new()
			spin.min_value = opts.get("min", 0.0)
			spin.max_value = opts.get("max", 999.0)
			spin.step = opts.get("step", 0.1)
			spin.value = opts.get("value", 0.0)
			spin.custom_minimum_size = Vector2(120, 28)
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_control = spin
		"enum":
			var opt := OptionButton.new()
			var options: Array = opts.get("options", [])
			var current_val = opts.get("value", "")
			for i in range(options.size()):
				var entry: Array = options[i]
				opt.add_item(entry[0])
				opt.set_item_metadata(i, entry[1])
				if str(entry[1]) == str(current_val):
					opt.selected = i
			opt.custom_minimum_size = Vector2(200, 28)
			opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_control = opt
		"bool":
			var chk := CheckButton.new()
			chk.button_pressed = bool(opts.get("value", false))
			chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_control = chk
	if _control != null:
		$ControlSlot.add_child(_control)

func get_value() -> Variant:
	if _control == null:
		return null
	if _control is SpinBox:
		return (_control as SpinBox).value
	if _control is OptionButton:
		var opt := _control as OptionButton
		if opt.selected >= 0 and opt.selected < opt.item_count:
			return opt.get_item_metadata(opt.selected)
		return ""
	if _control is CheckButton:
		return (_control as CheckButton).button_pressed
	return null

func set_value(v: Variant) -> void:
	if _control == null:
		return
	if _control is SpinBox:
		(_control as SpinBox).value = float(v)
	elif _control is OptionButton:
		var opt := _control as OptionButton
		for i in range(opt.item_count):
			if str(opt.get_item_metadata(i)) == str(v):
				opt.selected = i
				return
	elif _control is CheckButton:
		(_control as CheckButton).button_pressed = bool(v)
