extends VBoxContainer
class_name SaveLoadView

var population: Population = null
var config: NeatConfig = null
var env_idx: int = -1
var _pending_load: Dictionary = {}

@onready var _path_edit: LineEdit = $PathRow/PathEdit
@onready var _save_btn: Button = $BtnRow/SaveBtn
@onready var _load_btn: Button = $BtnRow/LoadBtn
@onready var _refresh_btn: Button = $BtnRow/RefreshBtn
@onready var _list: ItemList = $List
@onready var _status: Label = $StatusLabel

const SAVES_DIR: String = "user://saves"

func _ready() -> void:
	_save_btn.pressed.connect(_on_save)
	_load_btn.pressed.connect(_on_load)
	_refresh_btn.pressed.connect(_refresh_list)
	_list.item_activated.connect(_on_item_activated)
	_refresh_list()

func has_pending_load() -> bool:
	return not _pending_load.is_empty()

func take_pending_load() -> Dictionary:
	var d := _pending_load.duplicate(true)
	_pending_load.clear()
	return d

func _on_save() -> void:
	if population == null or config == null:
		_status.text = "Nothing to save."
		return
	var name: String = _path_edit.text.strip_edges()
	if name.is_empty():
		_status.text = "Enter a name."
		return
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	var path: String = "%s/%s.json" % [SAVES_DIR, name]
	var data: Dictionary = {
		"env_idx": env_idx,
		"generation": population.generation,
		"best_fitness": population.best_fitness,
		"config": _config_to_dict(config),
		"population": _population_to_dict(population),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "Cannot write file."
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	_status.text = "Saved to %s." % path
	_refresh_list()

func _on_load() -> void:
	var name: String = _path_edit.text.strip_edges()
	if name.is_empty():
		_status.text = "Enter a name."
		return
	var path: String = "%s/%s.json" % [SAVES_DIR, name]
	if not FileAccess.file_exists(path):
		_status.text = "File not found."
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_status.text = "Cannot read file."
		return
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		_status.text = "Parse error."
		return
	_pending_load = json.data
	_status.text = "Load queued. Will apply next generation."

func _on_item_activated(idx: int) -> void:
	_path_edit.text = _list.get_item_text(idx)

func _refresh_list() -> void:
	_list.clear()
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		return
	var files := DirAccess.get_files_at(SAVES_DIR)
	for f in files:
		if f.ends_with(".json"):
			_list.add_item(f.get_basename())

func _config_to_dict(c: NeatConfig) -> Dictionary:
	var d: Dictionary = {}
	for prop in c.get_property_list():
		var name: String = prop.name
		if name.begins_with("_") or name in ["script", "resource_local_to_scene"]:
			continue
		d[name] = c.get(name)
	return d

func _population_to_dict(p: Population) -> Dictionary:
	var d: Dictionary = {
		"generation": p.generation,
		"best_fitness": p.best_fitness,
		"genomes": [],
	}
	for g: Genome in p.genomes:
		d.genomes.append(_genome_to_dict(g))
	return d

func _genome_to_dict(g: Genome) -> Dictionary:
	var d: Dictionary = {
		"fitness": g.fitness,
		"species_id": g.species_id,
		"nodes": [],
		"connections": [],
	}
	for n: NodeGene in g.nodes.values():
		d.nodes.append({
			"id": n.id,
			"kind": n.kind,
			"activation": n.activation,
			"bias": n.bias,
			"depth": n.depth,
		})
	for c: ConnectionGene in g.connections.values():
		d.connections.append({
			"innovation": c.innovation,
			"from": c.from_node,
			"to": c.to_node,
			"weight": c.weight,
			"enabled": c.enabled,
		})
	return d
