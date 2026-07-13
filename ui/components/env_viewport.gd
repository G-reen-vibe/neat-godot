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
# Base scale: pixels per world unit. For RL envs (already in pixels), this is
# 1.0; the user-facing zoom is _camera_zoom.
var _scale: float = 1.0

# Track held WASD keys for continuous smooth panning.
var _pan_input: Vector2 = Vector2.ZERO  # unit direction in screen space

var _info_text: String = ""
var _steps: int = 0
var _max_steps: int = 0
var _done: bool = false
# Cached visual state — read once per frame in _process, reused in _draw.
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

## Set overlay info for the _draw() pass.
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
        if state.has("hits"):
                lines.append("hits=%d" % int(state.get("hits", 0)))
        if state.has("score_a"):
                lines.append("score %d-%d" % [int(state.get("score_a", 0)), int(state.get("score_b", 0))])
        if state.has("theta"):
                lines.append("theta=%.3f" % float(state.get("theta", 0)))
        if state.has("lander_angle"):
                lines.append("ang=%.3f" % float(state.get("lander_angle", 0)))
        if state.has("lander_vy"):
                lines.append("vy=%.1f" % float(state.get("lander_vy", 0)))
        if state.has("torso_x"):
                lines.append("x=%.1f" % float(state.get("torso_x", 0)))
        if state.has("torso_angle"):
                lines.append("torso=%.3f" % float(state.get("torso_angle", 0)))
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
        var state: Dictionary = _cached_state
        if state.is_empty():
                state = env.get_visual_state()
        # Compute camera transform. For RL envs, coordinates are already in pixels
        # (y-down), so we use _scale = 1.0 and do NOT flip y.
        var center := size_vec * 0.5 + _camera_offset
        var zoom := _camera_zoom * _scale
        # Draw env-specific content.
        if env is NeatCartPoleEnv:
                _draw_cartpole(state, center, zoom, size_vec)
        elif env is NeatPongEnv:
                _draw_pong(state, center, zoom, size_vec)
        elif env is NeatLunarLanderEnv:
                _draw_lunar_lander(state, center, zoom, size_vec)
        elif env is NeatBipedalWalkerEnv:
                _draw_bipedal_walker(state, center, zoom, size_vec)
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

## Convert a world position (RL env pixel coords, y-down) to screen coords.
## center is the screen center + camera pan. zoom is the camera zoom.
func _world_to_screen_px(p: Vector2, center: Vector2, zoom: float) -> Vector2:
        return center + p * zoom

## Convert a world position with an offset (e.g. body local pos + parent pos).
func _world_to_screen_offset(p: Vector2, offset: Vector2, center: Vector2, zoom: float) -> Vector2:
        return center + (p + offset) * zoom

func _draw_cartpole(state: Dictionary, center: Vector2, zoom: float, size_vec: Vector2) -> void:
        var cart_pos: Vector2 = state.get("cart_pos", Vector2.ZERO)
        var theta: float = float(state.get("theta", 0))
        var track_half: float = float(state.get("x_threshold", 192.0))
        var pole_half_len: float = float(state.get("pole_half_length", 60.0))
        var track_y: float = float(state.get("track_y", 160.0))
        # Track line (at y = track_y in world coords, y-down).
        var track_left := _world_to_screen_px(Vector2(-track_half, track_y), center, zoom)
        var track_right := _world_to_screen_px(Vector2(track_half, track_y), center, zoom)
        draw_line(track_left, track_right, Color(0.5, 0.5, 0.5), 2.0)
        # Track boundary markers.
        draw_line(track_left, track_left + Vector2(0, -10), Color(0.7, 0.3, 0.3), 2.0)
        draw_line(track_right, track_right + Vector2(0, -10), Color(0.7, 0.3, 0.3), 2.0)
        # Cart (80x32 pixels in RL env). Draw at cart_pos.
        var cart_screen := _world_to_screen_px(cart_pos, center, zoom)
        var cart_w: float = 80.0 * zoom
        var cart_h: float = 32.0 * zoom
        var cart_rect := Rect2(cart_screen - Vector2(cart_w * 0.5, cart_h * 0.5), Vector2(cart_w, cart_h))
        draw_rect(cart_rect, Color(0.3, 0.7, 1.0), true)
        draw_rect(cart_rect, Color(1, 1, 1), false, 1.0)
        # Pole: the pole is ABOVE the cart, pivoting at the bottom (where it meets
        # the cart). In the RL env, the PinJoint2D is at the top of the cart
        # (cart_pos.y - 16). The pole extends UPWARD from the pivot. When theta=0,
        # the pole points up (-y in world coords). Positive theta rotates the pole
        # CW on screen (Godot 2D convention, y-down).
        var pivot_screen := _world_to_screen_px(Vector2(cart_pos.x, cart_pos.y - 16.0), center, zoom)
        var pole_dir := Vector2(sin(theta), -cos(theta))  # up direction, rotated by theta
        var pole_end := pivot_screen + pole_dir * (pole_half_len * 2.0 * zoom)
        draw_line(pivot_screen, pole_end, Color(1.0, 0.8, 0.3), 3.0)
        draw_circle(pole_end, 4.0, Color(1.0, 0.5, 0.5))

func _draw_pong(state: Dictionary, center: Vector2, zoom: float, size_vec: Vector2) -> void:
        var fw: float = float(state.get("field_width", 320.0))
        var fh: float = float(state.get("field_height", 200.0))
        # Fit the arena into the viewport.
        var fit_scale: float = mini(size_vec.x * 0.9 / fw, size_vec.y * 0.9 / fh) * _camera_zoom
        var bx: float = float(state.get("ball_x", 0)) * fit_scale
        var by: float = float(state.get("ball_y", 0)) * fit_scale
        var pay: float = float(state.get("paddle_a_y", 0)) * fit_scale
        var pby: float = float(state.get("paddle_b_y", 0)) * fit_scale
        var ph: float = float(state.get("paddle_height", 80.0)) * fit_scale
        var pw: float = float(state.get("paddle_width", 8.0)) * fit_scale
        var pm: float = float(state.get("paddle_margin", 10.0)) * fit_scale
        var br: float = float(state.get("ball_radius", 6.0)) * fit_scale
        var fw_s := fw * fit_scale
        var fh_s := fh * fit_scale
        # Field border.
        draw_rect(Rect2(center.x - fw_s * 0.5, center.y - fh_s * 0.5, fw_s, fh_s), Color(0.3, 0.3, 0.4), false, 1.0)
        # Center line.
        draw_line(Vector2(center.x, center.y - fh_s * 0.5), Vector2(center.x, center.y + fh_s * 0.5), Color(0.3, 0.3, 0.4), 1.0)
        # Paddles (y-down: paddle_a_y is already in screen-oriented coords).
        var pa_x: float = center.x - fw_s * 0.5 + pm
        var pb_x: float = center.x + fw_s * 0.5 - pm - pw
        draw_rect(Rect2(pa_x, center.y + pay - ph * 0.5, pw, ph), Color(0.3, 0.9, 1.0), true)
        draw_rect(Rect2(pb_x, center.y + pby - ph * 0.5, pw, ph), Color(1.0, 0.5, 0.4), true)
        # Ball.
        draw_circle(center + Vector2(bx, by), maxf(2.0, br), Color(1.0, 1.0, 0.7))
        # Scores.
        draw_string(ThemeDB.fallback_font, Vector2(center.x - 30, 16), str(state.get("score_a", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.3, 0.9, 1.0))
        draw_string(ThemeDB.fallback_font, Vector2(center.x + 16, 16), str(state.get("score_b", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.5, 0.4))

func _draw_lunar_lander(state: Dictionary, center: Vector2, zoom: float, size_vec: Vector2) -> void:
        var lander_x: float = float(state.get("lander_x", 0))
        var lander_y: float = float(state.get("lander_y", 0))
        var lander_angle: float = float(state.get("lander_angle", 0))
        var pad_x: float = float(state.get("pad_x", 0))
        var pad_y: float = float(state.get("pad_y", 130))
        var pad_half: float = float(state.get("pad_half_width", 40))
        var half_size: float = float(state.get("lander_half_size", 12))
        var ground_y: float = float(state.get("arena_height", 300) * 0.5)
        # Offset so that the ground line is near the bottom of the viewport.
        var origin := center + Vector2(0, -size_vec.y * 0.2)
        # Ground line.
        var ground_screen := _world_to_screen_px(Vector2(0, ground_y), origin, zoom)
        draw_line(Vector2(0, ground_screen.y), Vector2(size_vec.x, ground_screen.y), Color(0.4, 0.35, 0.3), 2.0)
        # Pad (green rectangle on the ground).
        var pad_screen := _world_to_screen_px(Vector2(pad_x, pad_y), origin, zoom)
        var pad_w: float = pad_half * 2.0 * zoom
        var pad_h: float = 8.0 * zoom
        draw_rect(Rect2(pad_screen.x - pad_w * 0.5, pad_screen.y - pad_h * 0.5, pad_w, pad_h), Color(0.3, 0.7, 0.4), true)
        # Lander (rotated square).
        var lander_screen := _world_to_screen_px(Vector2(lander_x, lander_y), origin, zoom)
        var ls: float = half_size * 2.0 * zoom
        # Draw lander as a rotated rectangle.
        var half: float = ls * 0.5
        var corners := PackedVector2Array([
                lander_screen + Vector2(-half, -half).rotated(lander_angle),
                lander_screen + Vector2(half, -half).rotated(lander_angle),
                lander_screen + Vector2(half, half).rotated(lander_angle),
                lander_screen + Vector2(-half, half).rotated(lander_angle),
        ])
        draw_colored_polygon(corners, Color(0.9, 0.8, 0.4))
        # Thruster indicator (small triangle below lander when vy < 0, i.e. thrusting up).
        var vy: float = float(state.get("lander_vy", 0))
        if vy < -10.0:
                var flame_tip := lander_screen + Vector2(0, half + 10.0 * zoom).rotated(lander_angle)
                var flame_l := lander_screen + Vector2(-half * 0.5, half).rotated(lander_angle)
                var flame_r := lander_screen + Vector2(half * 0.5, half).rotated(lander_angle)
                draw_colored_polygon(PackedVector2Array([flame_tip, flame_l, flame_r]), Color(1.0, 0.5, 0.2, 0.8))

func _draw_bipedal_walker(state: Dictionary, center: Vector2, zoom: float, size_vec: Vector2) -> void:
        var torso_pos: Vector2 = state.get("torso_pos", Vector2(0, 30))
        var torso_angle: float = float(state.get("torso_angle", 0))
        var ground_y: float = float(state.get("ground_y", 111))
        # Offset so the walker is centered horizontally and the ground is near the bottom.
        var origin := center + Vector2(0, -size_vec.y * 0.15)
        # Ground line.
        var ground_screen := _world_to_screen_px(Vector2(0, ground_y), origin, zoom)
        draw_line(Vector2(0, ground_screen.y), Vector2(size_vec.x, ground_screen.y), Color(0.35, 0.4, 0.3), 2.0)
        # Torso (30x30 rotated square).
        var torso_screen := _world_to_screen_px(torso_pos, origin, zoom)
        var half: float = 15.0 * zoom
        var corners := PackedVector2Array([
                torso_screen + Vector2(-half, -half).rotated(torso_angle),
                torso_screen + Vector2(half, -half).rotated(torso_angle),
                torso_screen + Vector2(half, half).rotated(torso_angle),
                torso_screen + Vector2(-half, half).rotated(torso_angle),
        ])
        draw_colored_polygon(corners, Color(0.6, 0.5, 0.9))
        # Legs: draw each link as a line from its position with rotation.
        _draw_leg(state, origin, zoom, "left_thigh", "left_shin", "left_foot", Color(0.5, 0.7, 0.9), Color(0.4, 0.6, 0.8), Color(0.3, 0.5, 0.7))
        _draw_leg(state, origin, zoom, "right_thigh", "right_shin", "right_foot", Color(0.9, 0.5, 0.7), Color(0.8, 0.4, 0.6), Color(0.7, 0.3, 0.5))

func _draw_leg(state: Dictionary, origin: Vector2, zoom: float, thigh_key: String, shin_key: String, foot_key: String, thigh_color: Color, shin_color: Color, foot_color: Color) -> void:
        var thigh_pos: Vector2 = state.get(thigh_key + "_pos", Vector2.ZERO)
        var thigh_angle: float = float(state.get(thigh_key + "_angle", 0))
        var shin_pos: Vector2 = state.get(shin_key + "_pos", Vector2.ZERO)
        var shin_angle: float = float(state.get(shin_key + "_angle", 0))
        var foot_pos: Vector2 = state.get(foot_key + "_pos", Vector2.ZERO)
        # Thigh (8x30): draw as a rotated rectangle centered at thigh_pos.
        _draw_link(thigh_pos, thigh_angle, 8.0, 30.0, origin, zoom, thigh_color)
        # Shin.
        _draw_link(shin_pos, shin_angle, 8.0, 30.0, origin, zoom, shin_color)
        # Foot (20x6).
        _draw_link(foot_pos, 0.0, 20.0, 6.0, origin, zoom, foot_color)

func _draw_link(pos: Vector2, angle: float, width: float, height: float, origin: Vector2, zoom: float, color: Color) -> void:
        var screen := _world_to_screen_px(pos, origin, zoom)
        var hw: float = width * 0.5 * zoom
        var hh: float = height * 0.5 * zoom
        var corners := PackedVector2Array([
                screen + Vector2(-hw, -hh).rotated(angle),
                screen + Vector2(hw, -hh).rotated(angle),
                screen + Vector2(hw, hh).rotated(angle),
                screen + Vector2(-hw, hh).rotated(angle),
        ])
        draw_colored_polygon(corners, color)
