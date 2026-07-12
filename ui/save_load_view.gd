class_name SaveLoadView
extends Control
## Save/Load panel for population state.
## Uses JSON serialization via Population's to_dict/from_dict.

var population: Population = null
var config: NeatConfig = null
var env_idx: int = -1

var _status_label: Label
var _path_edit: LineEdit
var _save_btn: Button
var _load_btn: Button
var _list: ItemList
var _saves_dir: String = "user://saves"

func _ready() -> void:
        custom_minimum_size = Vector2(340, 460)
        # Build UI.
        var vbox := VBoxContainer.new()
        vbox.set_anchors_preset(PRESET_FULL_RECT)
        vbox.offset_left = 8
        vbox.offset_top = 8
        vbox.offset_right = -8
        vbox.offset_bottom = -8
        vbox.add_theme_constant_override("separation", 8)
        add_child(vbox)
        # Title.
        var title := Label.new()
        title.text = "Save / Load Training State"
        title.add_theme_font_size_override("font_size", 15)
        title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
        vbox.add_child(title)
        # Path entry.
        var path_row := HBoxContainer.new()
        path_row.add_theme_constant_override("separation", 6)
        var path_lbl := Label.new()
        path_lbl.text = "Name:"
        path_lbl.custom_minimum_size = Vector2(50, 24)
        path_row.add_child(path_lbl)
        _path_edit = LineEdit.new()
        _path_edit.placeholder_text = "my_training"
        _path_edit.text = "neat_save"
        _path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        path_row.add_child(_path_edit)
        vbox.add_child(path_row)
        # Save / Load buttons.
        var btn_row := HBoxContainer.new()
        btn_row.add_theme_constant_override("separation", 8)
        _save_btn = Button.new()
        _save_btn.text = "Save"
        _save_btn.custom_minimum_size = Vector2(80, 32)
        _save_btn.pressed.connect(_on_save)
        btn_row.add_child(_save_btn)
        _load_btn = Button.new()
        _load_btn.text = "Load"
        _load_btn.custom_minimum_size = Vector2(80, 32)
        _load_btn.pressed.connect(_on_load)
        btn_row.add_child(_load_btn)
        var refresh_btn := Button.new()
        refresh_btn.text = "Refresh List"
        refresh_btn.custom_minimum_size = Vector2(100, 32)
        refresh_btn.pressed.connect(_refresh_list)
        btn_row.add_child(refresh_btn)
        vbox.add_child(btn_row)
        # Saved files list.
        var list_lbl := Label.new()
        list_lbl.text = "Saved files:"
        list_lbl.add_theme_font_size_override("font_size", 12)
        list_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
        vbox.add_child(list_lbl)
        _list = ItemList.new()
        _list.size_flags_vertical = Control.SIZE_EXPAND_FILL
        _list.custom_minimum_size = Vector2(0, 150)
        _list.item_activated.connect(_on_item_activated)
        vbox.add_child(_list)
        # Status.
        _status_label = Label.new()
        _status_label.text = "Ready."
        _status_label.add_theme_font_size_override("font_size", 11)
        _status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
        _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _status_label.custom_minimum_size = Vector2(0, 60)
        vbox.add_child(_status_label)
        # Create saves dir if needed.
        DirAccess.make_dir_recursive_absolute(_saves_dir)
        _refresh_list()

func _set_status(text: String, is_error: bool = false) -> void:
        _status_label.text = text
        if is_error:
                _status_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
        else:
                _status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))

func _on_save() -> void:
        if population == null:
                _set_status("No population to save.", true)
                return
        var name: String = _path_edit.text.strip_edges()
        if name.is_empty():
                _set_status("Enter a save name.", true)
                return
        var path: String = "%s/%s.json" % [_saves_dir, name]
        var data: Dictionary = {
                "env_idx": env_idx,
                "generation": population.generation,
                "best_fitness": population.best_fitness,
                "config": _config_to_dict(config),
                "population": _population_to_dict(population),
        }
        var file := FileAccess.open(path, FileAccess.WRITE)
        if file == null:
                _set_status("Failed to open %s for writing." % path, true)
                return
        file.store_string(JSON.stringify(data, "\t"))
        file.close()
        _set_status("Saved to %s" % path)
        _refresh_list()

func _on_load() -> void:
        var name: String = _path_edit.text.strip_edges()
        if name.is_empty():
                _set_status("Enter a save name to load.", true)
                return
        var path: String = "%s/%s.json" % [_saves_dir, name]
        _load_from_path(path)

func _on_item_activated(idx: int) -> void:
        var name: String = _list.get_item_text(idx)
        _path_edit.text = name
        _load_from_path("%s/%s.json" % [_saves_dir, name])

func _load_from_path(path: String) -> void:
        if not FileAccess.file_exists(path):
                _set_status("File not found: %s" % path, true)
                return
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null:
                _set_status("Failed to open %s." % path, true)
                return
        var text: String = file.get_as_text()
        file.close()
        var parsed: Variant = JSON.parse_string(text)
        if parsed == null or not (parsed is Dictionary):
                _set_status("Failed to parse JSON.", true)
                return
        var data: Dictionary = parsed
        # We can't directly replace the population reference from here, so we emit.
        _set_status("Loaded generation %d (best=%.3f). Apply via app." % [int(data.get("generation", 0)), float(data.get("best_fitness", 0))])
        # Store the data for the app to pick up.
        _pending_load = data

var _pending_load: Dictionary = {}

func has_pending_load() -> bool:
        return not _pending_load.is_empty()

func take_pending_load() -> Dictionary:
        var d: Dictionary = _pending_load
        _pending_load = {}
        return d

func _refresh_list() -> void:
        _list.clear()
        var dir := DirAccess.open(_saves_dir)
        if dir == null:
                return
        dir.list_dir_begin()
        var fname: String = dir.get_next()
        while not fname.is_empty():
                if fname.ends_with(".json"):
                        _list.add_item(fname.substr(0, fname.length() - 5))
                fname = dir.get_next()
        dir.list_dir_end()

# --- Serialization helpers ---

func _config_to_dict(c: NeatConfig) -> Dictionary:
        var d: Dictionary = {}
        # Properties to skip: underscore-prefixed (private), "script" (engine),
        # and "threshold_adjustment_speed" (a getter/setter alias that sets both
        # threshold_up_speed and threshold_down_speed — serializing it would
        # override the individual up/down values on load).
        var skip: Array = ["script", "threshold_adjustment_speed"]
        for prop in c.get_property_list():
                var pname: String = prop.name
                if pname.begins_with("_") or skip.has(pname):
                        continue
                var val: Variant = c.get(pname)
                # Only serialize primitive types.
                if val is int or val is float or val is bool or val is String:
                        d[pname] = val
        return d

func _config_from_dict(d: Dictionary) -> NeatConfig:
        var c := NeatConfig.new()
        for key in d:
                c.set(key, d[key])
        return c

func _population_to_dict(pop: Population) -> Dictionary:
        var d: Dictionary = {
                "generation": pop.generation,
                "best_fitness": pop.best_fitness,
                "genomes": [],
                "tracker": _tracker_to_dict(pop.tracker),
        }
        var genomes_arr: Array = []
        for g: Genome in pop.genomes:
                genomes_arr.append(_genome_to_dict(g))
        d["genomes"] = genomes_arr
        return d

func _tracker_to_dict(t: InnovationTracker) -> Dictionary:
        return {
                "next_conn_innov": t._next_conn_innov,
                "next_node_id": t._next_node_id,
                "conn_innov": t._conn_innov,
                "split_node": t._split_node,
        }

func _genome_to_dict(g: Genome) -> Dictionary:
        var d: Dictionary = {
                "fitness": g.fitness,
                "adjusted_fitness": g.adjusted_fitness,
                "species_id": g.species_id,
                "parent_species_id": g.parent_species_id,
                "nodes": [],
                "connections": [],
        }
        var nodes_arr: Array = []
        for n: NodeGene in g.nodes.values():
                nodes_arr.append({"id": n.id, "kind": n.kind, "activation": n.activation, "bias": n.bias, "depth": n.depth, "times_selected": n.times_selected})
        d["nodes"] = nodes_arr
        var conns_arr: Array = []
        for c: ConnectionGene in g.connections.values():
                conns_arr.append({"innovation": c.innovation, "from": c.from_node, "to": c.to_node, "weight": c.weight, "enabled": c.enabled, "times_selected": c.times_selected})
        d["connections"] = conns_arr
        return d

func load_population_from_dict(data: Dictionary, cfg: NeatConfig) -> Population:
        var pop := Population.new(cfg)
        # Restore tracker.
        var tdata: Dictionary = data.get("tracker", {})
        pop.tracker._next_conn_innov = int(tdata.get("next_conn_innov", 0))
        pop.tracker._next_node_id = int(tdata.get("next_node_id", 0))
        pop.tracker._conn_innov = tdata.get("conn_innov", {})
        pop.tracker._split_node = tdata.get("split_node", {})
        # Restore genomes.
        pop.genomes.clear()
        var genomes_arr: Array = data.get("genomes", [])
        for gd: Dictionary in genomes_arr:
                var g := Genome.new()
                g.fitness = float(gd.get("fitness", 0.0))
                g.adjusted_fitness = float(gd.get("adjusted_fitness", 0.0))
                g.species_id = int(gd.get("species_id", -1))
                g.parent_species_id = int(gd.get("parent_species_id", -1))
                for nd: Dictionary in gd.get("nodes", []):
                        var n := NodeGene.new(int(nd["id"]), int(nd["kind"]), int(nd["activation"]))
                        n.bias = float(nd.get("bias", 0.0))
                        n.depth = int(nd.get("depth", -1))
                        n.times_selected = int(nd.get("times_selected", 0))
                        g.add_node(n)
                for cd: Dictionary in gd.get("connections", []):
                        var c := ConnectionGene.new(int(cd["innovation"]), int(cd["from"]), int(cd["to"]), float(cd["weight"]), bool(cd["enabled"]))
                        c.times_selected = int(cd.get("times_selected", 0))
                        g.add_connection(c)
                pop.genomes.append(g)
        pop.generation = int(data.get("generation", 0))
        pop.best_fitness = float(data.get("best_fitness", 0.0))
        # Find the actual best genome (highest fitness) instead of just using
        # genomes[0], which may not be the best.
        if not pop.genomes.is_empty():
                var best_idx := 0
                var best_f: float = pop.genomes[0].fitness
                for i in range(1, pop.genomes.size()):
                        if pop.genomes[i].fitness > best_f:
                                best_f = pop.genomes[i].fitness
                                best_idx = i
                pop.best_genome = pop.genomes[best_idx].duplicate()
        # Re-speciate.
        var ctx := pop._make_ctx()
        pop.species_list = pop.speciation.speciate(pop.genomes, [], pop.similarity, ctx)
        return pop
