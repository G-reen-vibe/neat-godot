## Live visualization of a single env instance. Runs the env as a child Node
## (for physics processing) and renders it via custom _draw() using the env's
## get_visual_state() data. Camera pan/zoom with arrow keys, +/-, 0.
##
## This approach (instead of SubViewport + Camera) gives us:
##   - Full control over rendering (no need for visible sprites on bodies)
##   - No minimum size issues (Control with _draw has min_size = 0)
##   - Consistent visual style across all envs
extends Control
class_name EnvViewport

var env: Node = null
var env_scene: PackedScene = null
var view_type: String = "2d"

var _camera_offset: Vector2 = Vector2.ZERO
var _camera_zoom: float = 1.0
var _scale: float = 80.0  # pixels per world unit
var _auto_follow: bool = true  # auto-center on body for walking envs

var _info_text: String = ""
var _steps: int = 0
var _max_steps: int = 0
var _done: bool = false

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
        # The env is a physics Node; it will run _physics_process automatically.
        # We render it via _draw() reading get_visual_state().

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

func _process(_delta: float) -> void:
        if env == null or not is_instance_valid(env):
                return
        # Read visual state for info display.
        if env.has_method("get_visual_state"):
                var state: Dictionary = env.get_visual_state()
                _steps = int(state.get("steps", 0))
                _max_steps = int(state.get("max_steps", 0))
                _done = bool(state.get("done", false))
                _info_text = _format_info(state)
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
        if event is InputEventKey and event.pressed:
                var pan_speed: float = 20.0
                match event.keycode:
                        KEY_LEFT:
                                _camera_offset.x += pan_speed
                                _auto_follow = false
                        KEY_RIGHT:
                                _camera_offset.x -= pan_speed
                                _auto_follow = false
                        KEY_UP:
                                _camera_offset.y += pan_speed
                                _auto_follow = false
                        KEY_DOWN:
                                _camera_offset.y -= pan_speed
                                _auto_follow = false
                        KEY_EQUAL, KEY_PLUS:
                                _camera_zoom = minf(4.0, _camera_zoom * 1.2)
                        KEY_MINUS:
                                _camera_zoom = maxf(0.2, _camera_zoom / 1.2)
                        KEY_0:
                                _camera_offset = Vector2.ZERO
                                _camera_zoom = 1.0
                                _auto_follow = true

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
        var state: Dictionary = env.get_visual_state()
        # Compute camera transform.
        var center := size_vec * 0.5 + _camera_offset
        var zoom := _camera_zoom * _scale
        # Auto-follow for walking envs: center on body position.
        if _auto_follow and state.has("body_x"):
                var body_x: float = float(state.get("body_x", 0))
                _camera_offset.x = -body_x * zoom
                center = size_vec * 0.5 + _camera_offset
        # Draw env-specific content.
        if env is CartPoleEnvironment:
                _draw_cartpole(state, center, zoom, size_vec)
        elif env is AcrobotEnvironment:
                _draw_acrobot(state, center, zoom, size_vec)
        elif env is PongEnvironment:
                _draw_pong(state, center, zoom, size_vec)
        elif env is SpiderWalker2DEnvironment:
                _draw_spider_2d(state, center, zoom, size_vec)
        elif env is SpiderWalker3DEnvironment:
                _draw_spider_3d(state, center, zoom, size_vec)
        else:
                draw_string(ThemeDB.fallback_font, Vector2(8, 20), "Unknown env type: %s" % env.get_class(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5))
        # Info overlay.
        draw_string(ThemeDB.fallback_font, Vector2(8, 20), _info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.7))
        # Camera help.
        draw_string(ThemeDB.fallback_font, Vector2(8, size_vec.y - 6), "arrows=pan  +/-/0=zoom  0=follow", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))

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

func _draw_spider_2d(state: Dictionary, center: Vector2, zoom: float, size_vec: Vector2) -> void:
        var body_x: float = float(state.get("body_x", 0))
        var body_y: float = float(state.get("body_y", 0))
        var body_r: float = float(state.get("body_radius", 0.4))
        var ground_y: float = float(state.get("ground_y", 0))
        var scale: float = size_vec.y * 0.15 * _camera_zoom
        # Ground line.
        var ground_screen_y: float = center.y + size_vec.y * 0.3
        draw_line(Vector2(0, ground_screen_y), Vector2(size_vec.x, ground_screen_y), Color(0.4, 0.5, 0.3), 2.0)
        # Body (camera follows body_x).
        var body_screen_x: float = center.x
        var body_screen_y: float = ground_screen_y - body_y * scale
        draw_circle(Vector2(body_screen_x, body_screen_y), body_r * scale, Color(0.6, 0.5, 0.8))
        # Legs.
        var feet: Array = state.get("feet", [])
        for i in range(feet.size()):
                var f: Dictionary = feet[i]
                var hip: Vector2 = f["hip"]
                var knee: Vector2 = f["knee"]
                var foot: Vector2 = f["foot"]
                var hip_s := Vector2(body_screen_x + (hip.x - body_x) * scale, ground_screen_y - hip.y * scale)
                var knee_s := Vector2(body_screen_x + (knee.x - body_x) * scale, ground_screen_y - knee.y * scale)
                var foot_s := Vector2(body_screen_x + (foot.x - body_x) * scale, ground_screen_y - foot.y * scale)
                draw_line(hip_s, knee_s, Color(0.8, 0.7, 0.4), 2.0)
                draw_line(knee_s, foot_s, Color(0.9, 0.6, 0.3), 2.0)
                var foot_color: Color = Color(1.0, 0.3, 0.3) if f["touching"] else Color(0.5, 0.5, 0.5)
                draw_circle(foot_s, 3.0, foot_color)

func _draw_spider_3d(state: Dictionary, center: Vector2, zoom: float, size_vec: Vector2) -> void:
        var body_pos: Vector3 = state.get("body_pos", Vector3.ZERO)
        var initial_pos: Vector3 = state.get("initial_pos", Vector3.ZERO)
        var body_r: float = float(state.get("body_radius", 0.4))
        # Top-down projection: world XZ -> screen XY.
        var scale: float = size_vec.y * 0.12 * _camera_zoom
        # Camera follows body.
        var body_screen := center
        # Start position marker.
        var start_offset := Vector2((initial_pos.x - body_pos.x) * scale, (initial_pos.z - body_pos.z) * scale)
        draw_circle(body_screen + start_offset, 4.0, Color(0.3, 0.5, 0.3))
        # Body.
        draw_circle(body_screen, body_r * scale, Color(0.6, 0.5, 0.8))
        # Legs.
        var feet: Array = state.get("feet", [])
        for i in range(feet.size()):
                var f: Dictionary = feet[i]
                var hip: Vector3 = f["hip"]
                var knee: Vector3 = f["knee"]
                var foot: Vector3 = f["foot"]
                var hip_s := body_screen + Vector2((hip.x - body_pos.x) * scale, (hip.z - body_pos.z) * scale)
                var knee_s := body_screen + Vector2((knee.x - body_pos.x) * scale, (knee.z - body_pos.z) * scale)
                var foot_s := body_screen + Vector2((foot.x - body_pos.x) * scale, (foot.z - body_pos.z) * scale)
                draw_line(hip_s, knee_s, Color(0.8, 0.7, 0.4), 2.0)
                draw_line(knee_s, foot_s, Color(0.9, 0.6, 0.3), 2.0)
                var foot_color: Color = Color(1.0, 0.3, 0.3) if f["touching"] else Color(0.5, 0.5, 0.5)
                draw_circle(foot_s, 3.0, foot_color)
