## Live visualization of a single env instance. Runs the env as a child Node
## (for physics processing) and renders it via custom _draw() using the env's
## get_visual_state() data.
##
## The env drives itself via its own _physics_process when live_mode is true
## (set by RunScreen). This class only reads state for rendering — it does NOT
## call step_env/apply_action on the env.
##
## Camera controls (also exposed as methods for on-screen buttons):
##   - Pan: WASD (held = smooth continuous pan)
##   - Zoom: +/- keys, or adjust_zoom(factor)
##   - Reset: 0 key, or reset_view()
##
## Overlay: shows a "Training..." indicator when training is active, plus the
## live genome label and episode counter when paused.
extends Control
class_name EnvViewport

const CAMERA_PAN_SPEED: float = 320.0  # pixels per second (continuous pan)
const CAMERA_MIN_ZOOM: float = 0.2
const CAMERA_MAX_ZOOM: float = 6.0

var env: Node = null
var env_scene: PackedScene = null
var view_type: String = "2d"

var _camera_offset: Vector2 = Vector2.ZERO
var _camera_zoom: float = 1.0
var _scale: float = 80.0  # pixels per world unit

# Track held WASD keys for continuous smooth panning.
var _pan_input: Vector2 = Vector2.ZERO  # unit direction in screen space

var _info_text: String = ""
var _steps: int = 0
var _max_steps: int = 0
var _done: bool = false
# Cached visual state — read once per frame in _process, reused in _draw.
# Without this, get_visual_state() was called twice per frame (once in
# _process for info text, once in _draw for rendering).
var _cached_state: Dictionary = {}

# Overlay info set by RunScreen.
var _overlay_training: bool = false
var _overlay_live_label: String = ""
var _overlay_episode: int = 0
var _overlay_gen: int = 0
var _overlay_best: float = 0.0

func _ready() -> void:
        custom_minimum_size = Vector2(320, 240)
        clip_contents = true
        set_process(true)
        set_process_input(true)

func set_env_scene(p_scene: PackedScene, p_view_type: String) -> void:
        env_scene = p_scene
        view_type = p_view_type
        _rebuild()

func _rebuild() -> void:
        # Clear existing env.
        if env != null and is_instance_valid(env):
                env.queue_free()
                env = null
        if env_scene == null:
                return
        env = env_scene.instantiate()
        add_child(env)
        # The env is a physics Node; it will run _physics_process automatically
        # (when RunScreen enables it via set_physics_process). We render it via
        # _draw() reading get_visual_state().

func set_env_io(input_ids: Array[int], bias_id: int, output_id: int, output_ids: Array[int]) -> void:
        if env == null:
                return
        env.input_node_ids = input_ids
        env.bias_node_id = bias_id
        if output_id >= 0:
                env.output_node_id = output_id
        if output_ids.size() > 0:
                env.output_node_ids = output_ids

func reset_env(genome: Genome, rng: RandomNumberGenerator) -> void:
        if env == null or not is_instance_valid(env):
                return
        env.reset(genome, rng)

## Set overlay info for the _draw() pass. RunScreen calls this every frame
## with the current training state, live genome label, episode counter, and
## population gen/best (for the training overlay).
func set_overlay_info(info: Dictionary) -> void:
        _overlay_training = bool(info.get("training", false))
        _overlay_live_label = String(info.get("live_label", ""))
        _overlay_episode = int(info.get("episode", 0))
        _overlay_gen = int(info.get("gen", 0))
        _overlay_best = float(info.get("best", 0.0))

func adjust_zoom(factor: float) -> void:
        _camera_zoom = clampf(_camera_zoom * factor, CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)

func reset_view() -> void:
        _camera_offset = Vector2.ZERO
        _camera_zoom = 1.0

func _process(delta: float) -> void:
        # Continuous camera pan based on currently-held WASD keys.
        if _pan_input != Vector2.ZERO:
                _camera_offset += _pan_input * CAMERA_PAN_SPEED * delta
        if env == null or not is_instance_valid(env):
                _cached_state = {}
                queue_redraw()
                return
        # Read visual state ONCE per frame and cache it for _draw.
        if env.has_method("get_visual_state"):
                _cached_state = env.get_visual_state()
                _steps = int(_cached_state.get("steps", 0))
                _max_steps = int(_cached_state.get("max_steps", 0))
                _done = bool(_cached_state.get("done", false))
                _info_text = _format_info(_cached_state)
        queue_redraw()

func _format_info(state: Dictionary) -> String:
        var lines: Array = []
        lines.append("step %d/%d" % [_steps, _max_steps])
        if _done:
                lines.append("DONE")
        if state.has("distance"):
                lines.append("dist=%.2f" % float(state.get("distance", 0)))
        if state.has("score_a"):
                lines.append("score %d-%d" % [int(state.get("score_a", 0)), int(state.get("score_b", 0))])
        if state.has("theta"):
                lines.append("theta=%.3f" % float(state.get("theta", 0)))
        if state.has("tip_y"):
                lines.append("tip_y=%.2f" % float(state.get("tip_y", 0)))
        if state.has("x"):
                lines.append("x=%.2f" % float(state.get("x", 0)))
        return "\n".join(lines)

func _input(event: InputEvent) -> void:
        # Track WASD key presses/releases for continuous panning.
        if event is InputEventKey:
                var k := event as InputEventKey
                match k.keycode:
                        KEY_A:
                                _pan_input.x = -1.0 if k.pressed else 0.0
                                _consume()
                        KEY_D:
                                _pan_input.x = 1.0 if k.pressed else 0.0
                                _consume()
                        KEY_W:
                                _pan_input.y = -1.0 if k.pressed else 0.0
                                _consume()
                        KEY_S:
                                _pan_input.y = 1.0 if k.pressed else 0.0
                                _consume()
                        KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
                                if k.pressed:
                                        adjust_zoom(1.2)
                                        _consume()
                        KEY_MINUS, KEY_KP_SUBTRACT:
                                if k.pressed:
                                        adjust_zoom(1.0 / 1.2)
                                        _consume()
                        KEY_0, KEY_KP_0:
                                if k.pressed:
                                        reset_view()
                                        _consume()

# Mark the current input as handled so it doesn't propagate to the run_screen
# (which would otherwise also receive the WASD / zoom keys).
func _consume() -> void:
        get_viewport().set_input_as_handled()

func _draw() -> void:
        var size_vec := get_size()
        if size_vec.x < 2 or size_vec.y < 2:
                return
        # Background.
        draw_rect(Rect2(Vector2.ZERO, size_vec), Color(0.04, 0.04, 0.07), true)
        if env == null or not is_instance_valid(env):
                draw_string(ThemeDB.fallback_font, Vector2(8, 20), "No env", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5))
                return
        if not env.has_method("get_visual_state"):
                draw_string(ThemeDB.fallback_font, Vector2(8, 20), "No visualization", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5))
                return
        # Use the cached state from _process (avoids calling get_visual_state twice).
        var state: Dictionary = _cached_state
        if state.is_empty():
                # Fallback: if _process hasn't run yet, read it now.
                state = env.get_visual_state()
        # Compute camera transform.
        var center := size_vec * 0.5 + _camera_offset
        var zoom := _camera_zoom * _scale
        # Draw env-specific content.
        if env is CartPoleEnvironment:
                _draw_cartpole(state, center, zoom, size_vec)
        elif env is AcrobotEnvironment:
                _draw_acrobot(state, center, zoom, size_vec)
        elif env is PongEnvironment:
                _draw_pong(state, center, zoom, size_vec)
        else:
                draw_string(ThemeDB.fallback_font, Vector2(8, 20), "Unknown env type: %s" % env.get_class(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5))
        # Info overlay (top-left).
        draw_string(ThemeDB.fallback_font, Vector2(8, 20), _info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.7))
        # Genome label (top-right).
        if _overlay_live_label != "":
                draw_string(ThemeDB.fallback_font, Vector2(size_vec.x - 8, 20), _overlay_live_label, HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Color(0.8, 0.85, 1.0))
        # Episode counter (top-right, below genome label).
        if not _overlay_training and _overlay_episode > 0:
                draw_string(ThemeDB.fallback_font, Vector2(size_vec.x - 8, 36), "Episode %d" % _overlay_episode, HORIZONTAL_ALIGNMENT_RIGHT, -1, 11, Color(0.6, 0.7, 0.8))
        # Training overlay (center) when training is active.
        if _overlay_training:
                # Semi-transparent dark overlay.
                draw_rect(Rect2(Vector2.ZERO, size_vec), Color(0, 0, 0, 0.55), true)
                var train_text: String = "Training...\nGen %d | Best: %.2f" % [_overlay_gen, _overlay_best]
                _draw_centered_multiline(train_text, size_vec, 16, Color(0.9, 0.9, 0.95))
        # Camera help (bottom-left).
        draw_string(ThemeDB.fallback_font, Vector2(8, size_vec.y - 6), "WASD=pan  +/-/0=zoom  |  Space=pause  N=next  B=best", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))

func _draw_centered_multiline(text: String, size_vec: Vector2, font_size: int, color: Color) -> void:
        var lines: PackedStringArray = text.split("\n")
        var line_h: float = font_size + 4
        var total_h: float = line_h * lines.size()
        var start_y: float = (size_vec.y - total_h) * 0.5
        for i in range(lines.size()):
                var line_w: float = ThemeDB.fallback_font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
                var x: float = (size_vec.x - line_w) * 0.5
                draw_string(ThemeDB.fallback_font, Vector2(x, start_y + (i + 1) * line_h - 4), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _world_to_screen(p: Vector2, center: Vector2, zoom: float) -> Vector2:
        # World +y = UP, screen +y = DOWN. Flip y.
        return center + Vector2(p.x * zoom, -p.y * zoom)

func _draw_cartpole(state: Dictionary, center: Vector2, zoom: float, size_vec: Vector2) -> void:
        var x: float = float(state.get("x", 0))
        var theta: float = float(state.get("theta", 0))
        var track_half: float = float(state.get("x_threshold", 2.4))
        var pole_half_len: float = float(state.get("pole_half_length", 0.5))
        # Track line.
        var track_y: float = center.y + 30.0
        var track_left := center + Vector2(-track_half * zoom, track_y)
        var track_right := center + Vector2(track_half * zoom, track_y)
        draw_line(track_left, track_right, Color(0.5, 0.5, 0.5), 2.0)
        draw_line(track_left, track_left + Vector2(0, -10), Color(0.7, 0.3, 0.3), 2.0)
        draw_line(track_right, track_right + Vector2(0, -10), Color(0.7, 0.3, 0.3), 2.0)
        # Cart.
        var cart_pos := center + Vector2(x * zoom, track_y)
        var cart_rect := Rect2(cart_pos - Vector2(16, 6), Vector2(32, 12))
        draw_rect(cart_rect, Color(0.3, 0.7, 1.0), true)
        draw_rect(cart_rect, Color(1, 1, 1), false, 1.0)
        # Pole.
        var pole_top := cart_pos + Vector2(sin(theta), -cos(theta)) * (pole_half_len * 2.0 * zoom)
        draw_line(cart_pos, pole_top, Color(1.0, 0.8, 0.3), 3.0)
        draw_circle(pole_top, 4.0, Color(1.0, 0.5, 0.5))

func _draw_acrobot(state: Dictionary, center: Vector2, zoom: float, size_vec: Vector2) -> void:
        var theta1: float = float(state.get("theta1", 0))
        var theta2: float = float(state.get("theta2", 0))
        var l1: float = float(state.get("link_length_1", 1.0))
        var l2: float = float(state.get("link_length_2", 1.0))
        var height_thresh: float = float(state.get("height_threshold", 1.0))
        # Pivot at top center.
        var pivot := center + Vector2(0, -size_vec.y * 0.2)
        # Joint 1 (end of link 1). theta=0 means link hangs straight down.
        var j1 := pivot + Vector2(sin(theta1), cos(theta1)) * (l1 * zoom)
        # Tip (end of link 2).
        var tip := j1 + Vector2(sin(theta1 + theta2), cos(theta1 + theta2)) * (l2 * zoom)
        # Height threshold line.
        var thresh_y: float = pivot.y - height_thresh * zoom
        draw_line(Vector2(0, thresh_y), Vector2(size_vec.x, thresh_y), Color(0.3, 0.7, 0.3), 1.0)
        draw_string(ThemeDB.fallback_font, Vector2(4, thresh_y - 2), "goal", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.8, 0.4))
        # Links.
        draw_line(pivot, j1, Color(0.8, 0.7, 0.3), 3.0)
        draw_line(j1, tip, Color(0.9, 0.5, 0.3), 3.0)
        # Joints.
        draw_circle(pivot, 5.0, Color(0.7, 0.7, 0.7))
        draw_circle(j1, 4.0, Color(0.9, 0.7, 0.4))
        draw_circle(tip, 5.0, Color(1.0, 0.4, 0.4))

func _draw_pong(state: Dictionary, center: Vector2, zoom: float, size_vec: Vector2) -> void:
        var fw: float = float(state.get("field_width", 4.0))
        var fh: float = float(state.get("field_height", 3.0))
        var scale: float = mini(size_vec.x * 0.9 / fw, size_vec.y * 0.9 / fh) * _camera_zoom
        var bx: float = float(state.get("ball_x", 0)) * scale
        var by: float = float(state.get("ball_y", 0)) * scale
        var pay: float = float(state.get("paddle_a_y", 0)) * scale
        var pby: float = float(state.get("paddle_b_y", 0)) * scale
        var ph: float = float(state.get("paddle_height", 0.5)) * scale
        var pw: float = float(state.get("paddle_width", 0.08)) * scale
        var pm: float = float(state.get("paddle_margin", 0.1)) * scale
        var br: float = float(state.get("ball_radius", 0.05)) * scale
        var fw_s := fw * scale
        var fh_s := fh * scale
        # Field border.
        draw_rect(Rect2(center.x - fw_s * 0.5, center.y - fh_s * 0.5, fw_s, fh_s), Color(0.3, 0.3, 0.4), false, 1.0)
        # Center line.
        draw_line(Vector2(center.x, center.y - fh_s * 0.5), Vector2(center.x, center.y + fh_s * 0.5), Color(0.3, 0.3, 0.4), 1.0)
        # Paddles.
        var pa_x: float = center.x - fw_s * 0.5 + pm
        var pb_x: float = center.x + fw_s * 0.5 - pm - pw
        draw_rect(Rect2(pa_x, center.y + pay - ph * 0.5, pw, ph), Color(0.3, 0.9, 1.0), true)
        draw_rect(Rect2(pb_x, center.y + pby - ph * 0.5, pw, ph), Color(1.0, 0.5, 0.4), true)
        # Ball.
        draw_circle(center + Vector2(bx, by), maxf(2.0, br), Color(1.0, 1.0, 0.7))
        # Scores.
        draw_string(ThemeDB.fallback_font, Vector2(center.x - 30, 16), str(state.get("score_a", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.3, 0.9, 1.0))
        draw_string(ThemeDB.fallback_font, Vector2(center.x + 16, 16), str(state.get("score_b", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.5, 0.4))
