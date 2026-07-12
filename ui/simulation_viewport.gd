## Container that runs live simulations of the current population's genomes and
## visualizes them in one of two modes:
##   - PARALLEL: a grid of small views, one per genome (capped at grid_capacity).
##   - TOP: a single large view of the current best genome.
##
## The simulations are decoupled from the main NEAT evaluation: this view runs
## its own live sim ticks for visualization purposes only (does NOT affect the
## actual fitness used by NEAT).
##
## Camera controls: arrow keys pan, +/- zoom, 0 reset.
class_name SimulationViewport
extends Control

enum Mode { OFF, TOP, PARALLEL }

var mode: int = Mode.OFF:
        set(m):
                mode = m
                _rebuild_views()

var population: Population = null:
        set(p):
                population = p
                _rebuild_views()

# Optional: tournament opponents for Pong live viz. If set, the top-view Pong
# sim will use opponents[0] as player B instead of a static paddle.
var opponents: Array = []:
        set(o):
                opponents = o

var env_factory: Callable = Callable()
var forward_mode: String = "topological"

# Per-genome live simulation state for visualization.
var _live_envs: Array = []  # Array[NeatEnvironment]
var _live_genomes: Array = []  # Array[Genome]
var _live_states: Array = []  # Array[Dictionary]
var _live_steps: Array = []  # Array[int]
var _live_done: Array = []  # Array[bool]
var _live_max_steps: int = 500

# Camera (shared by all EnvView2D instances).
var _camera_offset: Vector2 = Vector2.ZERO
var _camera_zoom: float = 1.0

# View instances.
var _top_view: EnvView2D = null
var _parallel_views: Array = []  # Array[EnvView2D]
var _parallel_capacity: int = 64  # max grid cells

# Top-view tracking.
var _top_genome_idx: int = 0  # which genome to show in TOP mode
var _top_env: NeatEnvironment = null
var _top_state: Dictionary = {}
var _top_steps: int = 0
var _top_done: bool = false
var _top_genome: Genome = null

# UI.
var _info_label: Label
var _mode_label: Label

func _ready() -> void:
        custom_minimum_size = Vector2(640, 480)
        set_anchors_preset(PRESET_FULL_RECT)
        _info_label = Label.new()
        _info_label.position = Vector2(8, 8)
        _info_label.size = Vector2(300, 60)
        _info_label.add_theme_font_size_override("font_size", 12)
        _info_label.text = ""
        add_child(_info_label)
        _mode_label = Label.new()
        _mode_label.position = Vector2(8, 70)
        _mode_label.size = Vector2(300, 30)
        _mode_label.add_theme_font_size_override("font_size", 11)
        _mode_label.text = ""
        add_child(_mode_label)
        set_process(true)
        set_process_input(true)

func _input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed:
                var pan_speed: float = 20.0
                match event.keycode:
                        KEY_LEFT:
                                _camera_offset.x += pan_speed
                        KEY_RIGHT:
                                _camera_offset.x -= pan_speed
                        KEY_UP:
                                _camera_offset.y += pan_speed
                        KEY_DOWN:
                                _camera_offset.y -= pan_speed
                        KEY_EQUAL, KEY_PLUS:  # +
                                _camera_zoom = minf(4.0, _camera_zoom * 1.2)
                        KEY_MINUS:  # -
                                _camera_zoom = maxf(0.2, _camera_zoom / 1.2)
                        KEY_0:
                                _camera_offset = Vector2.ZERO
                                _camera_zoom = 1.0
                        KEY_V:
                                # Cycle modes.
                                mode = (mode + 1) % 3
                                _rebuild_views()
                        KEY_N:
                                # In TOP mode, advance to next genome.
                                if mode == Mode.TOP and population != null and not population.genomes.is_empty():
                                        _top_genome_idx = (_top_genome_idx + 1) % population.genomes.size()
                                        _reset_top_sim()
                        KEY_B:
                                # In TOP mode, jump to best genome.
                                if mode == Mode.TOP and population != null:
                                        var best_idx := _find_best_genome_idx()
                                        if best_idx >= 0:
                                                _top_genome_idx = best_idx
                                                _reset_top_sim()

func _find_best_genome_idx() -> int:
        if population == null or population.genomes.is_empty():
                return -1
        var best_i: int = 0
        var best_f: float = population.genomes[0].fitness
        for i in range(1, population.genomes.size()):
                if population.genomes[i].fitness > best_f:
                        best_f = population.genomes[i].fitness
                        best_i = i
        return best_i

func _process(delta: float) -> void:
        if population == null or env_factory.is_null():
                return
        match mode:
                Mode.OFF:
                        _info_label.text = "Press V to toggle visualization (Top/Parallel/Off)"
                        _mode_label.text = ""
                        return
                Mode.TOP:
                        _step_top_sim()
                        _info_label.text = "TOP view  |  Press V to cycle, N for next genome, B for best"
                        if _top_genome != null:
                                _mode_label.text = "Genome %d/%d  fit=%.3f  step %d/%d" % [_top_genome_idx + 1, population.genomes.size(), _top_genome.fitness, _top_steps, _live_max_steps]
                        else:
                                _mode_label.text = ""
                Mode.PARALLEL:
                        _step_parallel_sims()
                        _info_label.text = "PARALLEL view  |  %d agents  |  arrows=pan  +/-=zoom  0=reset" % _live_genomes.size()
                        _mode_label.text = "Press V to cycle"
        # Update views.
        _update_views()

func _rebuild_views() -> void:
        # Clear existing.
        for c in get_children():
                if c is EnvView2D:
                        remove_child(c)
                        c.queue_free()
        _parallel_views.clear()
        _top_view = null
        if population == null or env_factory.is_null():
                return
        match mode:
                Mode.TOP:
                        _top_view = _make_view_for_env(env_factory.call())
                        _top_view.set_anchors_preset(PRESET_FULL_RECT)
                        _top_view.offset_left = 8
                        _top_view.offset_top = 100
                        _top_view.offset_right = -8
                        _top_view.offset_bottom = -8
                        _top_view.camera_offset = _camera_offset
                        _top_view.camera_zoom = _camera_zoom
                        _top_view.show_label = false
                        add_child(_top_view)
                        _reset_top_sim()
                Mode.PARALLEL:
                        _init_parallel_sims()
                        var n: int = mini(_parallel_capacity, _live_genomes.size())
                        var grid_cols: int = int(ceil(sqrt(float(n))))
                        var grid_rows: int = int(ceil(float(n) / float(grid_cols)))
                        for i in range(n):
                                var v: EnvView2D = _make_view_for_env(_live_envs[i])
                                v.show_label = true
                                v.view_label = "#%d" % i
                                add_child(v)
                                _parallel_views.append(v)
                        _layout_parallel_views()
                _:
                        pass

func _layout_parallel_views() -> void:
        var n := _parallel_views.size()
        if n == 0:
                return
        var cols: int = int(ceil(sqrt(float(n))))
        var rows: int = int(ceil(float(n) / float(cols)))
        var size_rect := Rect2(Vector2(8, 100), get_size() - Vector2(16, 108))
        var cell_w: float = size_rect.size.x / float(cols)
        var cell_h: float = size_rect.size.y / float(rows)
        for i in range(n):
                var v: EnvView2D = _parallel_views[i]
                var col: int = i % cols
                var row: int = i / cols
                var x: float = size_rect.position.x + col * cell_w
                var y: float = size_rect.position.y + row * cell_h
                v.position = Vector2(x + 2, y + 2)
                v.size = Vector2(cell_w - 4, cell_h - 4)
                v.camera_offset = _camera_offset
                v.camera_zoom = _camera_zoom

func _make_view_for_env(p_env: NeatEnvironment) -> EnvView2D:
        if p_env is CartPoleEnvironment:
                return EnvView2D.CartPoleView.new()
        if p_env is AcrobotEnvironment:
                return EnvView2D.AcrobotView.new()
        if p_env is PongEnvironment:
                return EnvView2D.PongView.new()
        if p_env is SpiderWalker2DEnvironment:
                return EnvView2D.Spider2DView.new()
        if p_env is SpiderWalker3DEnvironment:
                return EnvView2D.Spider3DView.new()
        # Fallback: default view (shows env type name).
        return EnvView2D.new()

func _init_parallel_sims() -> void:
        _live_envs.clear()
        _live_genomes.clear()
        _live_states.clear()
        _live_steps.clear()
        _live_done.clear()
        if population == null or population.genomes.is_empty():
                return
        var n: int = mini(_parallel_capacity, population.genomes.size())
        var local_rng := RandomNumberGenerator.new()
        local_rng.seed = 12345
        for i in range(n):
                var env: NeatEnvironment = env_factory.call()
                # Pong envs need player A and B set.
                if env is PongEnvironment:
                        var pe: PongEnvironment = env as PongEnvironment
                        pe.set_player_a(population.genomes[i])
                        # Use tournament opponent if available; else static.
                        if opponents.size() > 0 and opponents[0] != null:
                                pe.set_player_b(opponents[0])
                        else:
                                pe.set_player_b(null)
                env.reset(local_rng)
                _live_envs.append(env)
                _live_genomes.append(population.genomes[i])
                _live_states.append(env.initial_state())
                _live_steps.append(0)
                _live_done.append(false)

func _step_parallel_sims() -> void:
        for i in range(_live_envs.size()):
                if _live_done[i]:
                        # Auto-restart after a brief pause.
                        _live_steps[i] += 1
                        if _live_steps[i] > _live_max_steps + 30:
                                var local_rng := RandomNumberGenerator.new()
                                local_rng.seed = i * 31 + 7
                                _live_envs[i].reset(local_rng)
                                _live_states[i] = _live_envs[i].initial_state()
                                _live_steps[i] = 0
                                _live_done[i] = false
                        continue
                var g: Genome = _live_genomes[i]
                var env: NeatEnvironment = _live_envs[i]
                if env is PongEnvironment:
                        var pong_env: PongEnvironment = env as PongEnvironment
                        var output_a: Dictionary = g.forward(_live_states[i], forward_mode)
                        var output_b: Dictionary = {}
                        if pong_env.player_b != null:
                                output_b = pong_env.player_b.forward(_live_states[i], forward_mode)
                        var action: Dictionary = pong_env.interpret_output(output_a, output_b)
                        _live_states[i] = pong_env.step(action)
                else:
                        var output: Dictionary = g.forward(_live_states[i], forward_mode)
                        var action: Dictionary = env.interpret_output(output)
                        _live_states[i] = env.step(action)
                _live_steps[i] += 1
                _live_done[i] = env.is_done()

func _reset_top_sim() -> void:
        if population == null or population.genomes.is_empty():
                _top_genome = null
                _top_env = null
                return
        _top_genome_idx = _top_genome_idx % population.genomes.size()
        _top_genome = population.genomes[_top_genome_idx]
        _top_env = env_factory.call()
        # Pong envs need player A and player B set.
        if _top_env is PongEnvironment:
                var pe: PongEnvironment = _top_env as PongEnvironment
                pe.set_player_a(_top_genome)
                # Use a tournament opponent if available; otherwise static.
                if opponents.size() > 0 and opponents[0] != null:
                        pe.set_player_b(opponents[0])
                else:
                        pe.set_player_b(null)
        var local_rng := RandomNumberGenerator.new()
        local_rng.seed = 999
        _top_env.reset(local_rng)
        _top_state = _top_env.initial_state()
        _top_steps = 0
        _top_done = false

func _step_top_sim() -> void:
        if _top_genome == null or _top_env == null:
                _reset_top_sim()
                if _top_genome == null:
                        return
        if _top_done:
                _top_steps += 1
                if _top_steps > _live_max_steps + 30:
                        _reset_top_sim()
                return
        if _top_env is PongEnvironment:
                var pong_env: PongEnvironment = _top_env as PongEnvironment
                var output_a: Dictionary = _top_genome.forward(_top_state, forward_mode)
                var output_b: Dictionary = {}
                if pong_env.player_b != null:
                        output_b = pong_env.player_b.forward(_top_state, forward_mode)
                var action: Dictionary = pong_env.interpret_output(output_a, output_b)
                _top_state = pong_env.step(action)
        else:
                var output: Dictionary = _top_genome.forward(_top_state, forward_mode)
                var action: Dictionary = _top_env.interpret_output(output)
                _top_state = _top_env.step(action)
        _top_steps += 1
        _top_done = _top_env.is_done()

func _update_views() -> void:
        if mode == Mode.TOP and _top_view != null:
                _top_view.env = _top_env
                _top_view.camera_offset = _camera_offset
                _top_view.camera_zoom = _camera_zoom
                _top_view.queue_redraw()
        elif mode == Mode.PARALLEL:
                for i in range(_parallel_views.size()):
                        var v: EnvView2D = _parallel_views[i]
                        if i < _live_envs.size():
                                v.env = _live_envs[i]
                        v.camera_offset = _camera_offset
                        v.camera_zoom = _camera_zoom
                        v.queue_redraw()

func _on_resized() -> void:
        if mode == Mode.PARALLEL:
                _layout_parallel_views()
