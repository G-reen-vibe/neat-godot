## Renders the visual state of a single environment instance.
## Subclasses override [method _draw_state] to draw environment-specific content.
## The base class handles camera offset, zoom, and the border / label.
class_name EnvView2D
extends Control

# Camera offset and zoom (shared across all EnvView2D instances via the parent).
var camera_offset: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0

var env: NeatEnvironment = null:
	set(e):
		env = e
		queue_redraw()

var view_label: String = ""
var show_label: bool = true

func _ready() -> void:
	custom_minimum_size = Vector2(160, 120)

func _draw() -> void:
	var size := get_size()
	if size.x < 2 or size.y < 2:
		return
	# Background.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.08), true)
	# Border.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.3, 0.4), false, 1.0)
	if env == null:
		return
	# Translate to center + camera offset, scale by zoom.
	var transform_offset := size * 0.5 + camera_offset
	# Clip drawing to our rect.
	# Note: Godot doesn't have easy clip rect in _draw, but since we're in a
	# bounded Control, draws outside are clipped automatically by the parent.
	_draw_state(env, transform_offset, camera_zoom, size)
	# Label / overlay.
	if show_label and not view_label.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(4, 12), view_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.9, 0.9))
	# Done indicator.
	if env.is_done():
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 40, 12), "DONE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.6, 0.3))

## Override in subclasses. Draw env-specific content using [method draw_*].
## [param center] is the screen-space center to draw around (already includes camera offset).
## [param zoom] is the camera zoom factor (multiply world units by this).
## [param size] is the total control size.
func _draw_state(p_env: NeatEnvironment, center: Vector2, zoom: float, size: Vector2) -> void:
	# Default: draw env type name.
	var vt: String = p_env.view_type()
	draw_string(ThemeDB.fallback_font, center - Vector2(40, 0), vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5))


## Specific renderer for CartPoleEnvironment.
class CartPoleView:
	extends EnvView2D

	func _draw_state(p_env: NeatEnvironment, center: Vector2, zoom: float, size: Vector2) -> void:
		if not (p_env is CartPoleEnvironment):
			super(p_env, center, zoom, size)
			return
		var state: Dictionary = p_env.get_visual_state()
		var x: float = state.get("x", 0.0)
		var theta: float = state.get("theta", 0.0)
		var track_half: float = state.get("track_half_length", 2.4)
		var pole_half_len: float = state.get("pole_half_length", 0.5)
		# Scale: world units to pixels. Track is 2*track_half wide, fits in 80% of view width.
		var scale: float = (size.x * 0.8) / (2.0 * track_half) * zoom
		# Track line.
		var track_y: float = center.y + 30.0
		var track_left: Vector2 = center + Vector2(-track_half * scale, track_y)
		var track_right: Vector2 = center + Vector2(track_half * scale, track_y)
		draw_line(track_left, track_right, Color(0.5, 0.5, 0.5), 2.0)
		# Track end markers.
		draw_line(track_left, track_left + Vector2(0, -10), Color(0.7, 0.3, 0.3), 2.0)
		draw_line(track_right, track_right + Vector2(0, -10), Color(0.7, 0.3, 0.3), 2.0)
		# Cart.
		var cart_pos: Vector2 = center + Vector2(x * scale, track_y)
		var cart_rect := Rect2(cart_pos - Vector2(16, 6), Vector2(32, 12))
		draw_rect(cart_rect, Color(0.3, 0.7, 1.0), true)
		draw_rect(cart_rect, Color(1, 1, 1), false, 1.0)
		# Pole (rotates by theta from vertical).
		var pole_top: Vector2 = cart_pos + Vector2(sin(theta), -cos(theta)) * (pole_half_len * 2.0 * scale)
		draw_line(cart_pos, pole_top, Color(1.0, 0.8, 0.3), 3.0)
		draw_circle(pole_top, 4.0, Color(1.0, 0.5, 0.5))
		# Step counter.
		draw_string(ThemeDB.fallback_font, Vector2(4, size.y - 6), "step %d" % state.get("steps", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))


## Specific renderer for AcrobotEnvironment.
class AcrobotView:
	extends EnvView2D

	func _draw_state(p_env: NeatEnvironment, center: Vector2, zoom: float, size: Vector2) -> void:
		if not (p_env is AcrobotEnvironment):
			super(p_env, center, zoom, size)
			return
		var state: Dictionary = p_env.get_visual_state()
		var theta1: float = state.get("theta1", 0.0)
		var theta2: float = state.get("theta2", 0.0)
		var l1: float = state.get("link_length_1", 1.0)
		var l2: float = state.get("link_length_2", 1.0)
		var height_thresh: float = state.get("height_threshold", 1.0)
		# Scale: total reach is l1+l2, fits in 80% of view height.
		var scale: float = (size.y * 0.4) / (l1 + l2) * zoom
		# Pivot at origin (top of screen, since theta=0 means link points down).
		var pivot: Vector2 = center + Vector2(0, -size.y * 0.2)
		# Joint 1 position (end of link 1).
		var j1: Vector2 = pivot + Vector2(sin(theta1), cos(theta1)) * (l1 * scale)
		# Tip (end of link 2).
		var tip: Vector2 = j1 + Vector2(sin(theta1 + theta2), cos(theta1 + theta2)) * (l2 * scale)
		# Height threshold line (y in world = -height_thresh; in screen, y increases downward,
		# so threshold is at pivot.y - height_thresh * scale).
		var thresh_y: float = pivot.y - height_thresh * scale
		draw_line(Vector2(0, thresh_y), Vector2(size.x, thresh_y), Color(0.3, 0.7, 0.3), 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(4, thresh_y - 2), "goal", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.8, 0.4))
		# Draw links.
		draw_line(pivot, j1, Color(0.8, 0.7, 0.3), 3.0)
		draw_line(j1, tip, Color(0.9, 0.5, 0.3), 3.0)
		# Joints.
		draw_circle(pivot, 5.0, Color(0.7, 0.7, 0.7))
		draw_circle(j1, 4.0, Color(0.9, 0.7, 0.4))
		draw_circle(tip, 5.0, Color(1.0, 0.4, 0.4))
		# Step counter.
		draw_string(ThemeDB.fallback_font, Vector2(4, size.y - 6), "step %d  tip_y=%.2f" % [state.get("steps", 0), state.get("tip_y", 0.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))


## Specific renderer for PongEnvironment.
class PongView:
	extends EnvView2D

	func _draw_state(p_env: NeatEnvironment, center: Vector2, zoom: float, size: Vector2) -> void:
		if not (p_env is PongEnvironment):
			super(p_env, center, zoom, size)
			return
		var state: Dictionary = p_env.get_visual_state()
		var fw: float = state.get("field_width", 4.0)
		var fh: float = state.get("field_height", 3.0)
		var scale: float = mini(size.x * 0.9 / fw, size.y * 0.9 / fh) * zoom
		var bx: float = float(state.get("ball_x", 0.0)) * scale
		var by: float = float(state.get("ball_y", 0.0)) * scale
		var pay: float = float(state.get("paddle_a_y", 0.0)) * scale
		var pby: float = float(state.get("paddle_b_y", 0.0)) * scale
		var ph: float = float(state.get("paddle_height", 0.5)) * scale
		var pw: float = float(state.get("paddle_width", 0.08)) * scale
		var pm: float = float(state.get("paddle_margin", 0.1)) * scale
		var br: float = float(state.get("ball_radius", 0.05)) * scale
		# Field border.
		var fw_s: float = fw * scale
		var fh_s: float = fh * scale
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
		# Score.
		draw_string(ThemeDB.fallback_font, Vector2(center.x - 30, 16), str(state.get("score_a", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.3, 0.9, 1.0))
		draw_string(ThemeDB.fallback_font, Vector2(center.x + 16, 16), str(state.get("score_b", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.5, 0.4))


## Specific renderer for SpiderWalker2DEnvironment (top-down 2D).
class Spider2DView:
	extends EnvView2D

	func _draw_state(p_env: NeatEnvironment, center: Vector2, zoom: float, size: Vector2) -> void:
		if not (p_env is SpiderWalker2DEnvironment):
			super(p_env, center, zoom, size)
			return
		var state: Dictionary = p_env.get_visual_state()
		var body_x: float = float(state.get("body_x", 0.0))
		var body_y: float = float(state.get("body_y", 0.0))
		var body_r: float = float(state.get("body_radius", 0.4))
		var ground_y: float = float(state.get("ground_y", 0.0))
		# Side-view scale.
		var scale: float = size.y * 0.15 * zoom
		# Ground line.
		var ground_screen_y: float = center.y + size.y * 0.3
		draw_line(Vector2(0, ground_screen_y), Vector2(size.x, ground_screen_y), Color(0.4, 0.5, 0.3), 2.0)
		# Body (centered; we render world coords relative to body_x).
		# Show world as if camera follows body.
		var body_screen_x: float = center.x  # camera follows body
		var body_screen_y: float = ground_screen_y - body_y * scale
		draw_circle(Vector2(body_screen_x, body_screen_y), body_r * scale, Color(0.6, 0.5, 0.8))
		# Draw legs.
		var feet: Array = state.get("feet", [])
		for i in range(feet.size()):
			var f: Dictionary = feet[i]
			var hip: Vector2 = f["hip"]
			var knee: Vector2 = f["knee"]
			var foot: Vector2 = f["foot"]
			# Convert world to screen (subtract body_x to follow body, scale).
			var hip_s := Vector2(body_screen_x + (hip.x - body_x) * scale, ground_screen_y - hip.y * scale)
			var knee_s := Vector2(body_screen_x + (knee.x - body_x) * scale, ground_screen_y - knee.y * scale)
			var foot_s := Vector2(body_screen_x + (foot.x - body_x) * scale, ground_screen_y - foot.y * scale)
			draw_line(hip_s, knee_s, Color(0.8, 0.7, 0.4), 2.0)
			draw_line(knee_s, foot_s, Color(0.9, 0.6, 0.3), 2.0)
			var foot_color: Color = Color(1.0, 0.3, 0.3) if f["touching"] else Color(0.5, 0.5, 0.5)
			draw_circle(foot_s, 3.0, foot_color)
		# Distance label.
		draw_string(ThemeDB.fallback_font, Vector2(4, size.y - 6), "dist=%.2f  step %d" % [float(state.get("distance", 0.0)), state.get("steps", 0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))


## Specific renderer for SpiderWalker3DEnvironment (top-down projection).
class Spider3DView:
	extends EnvView2D

	func _draw_state(p_env: NeatEnvironment, center: Vector2, zoom: float, size: Vector2) -> void:
		if not (p_env is SpiderWalker3DEnvironment):
			super(p_env, center, zoom, size)
			return
		var state: Dictionary = p_env.get_visual_state()
		var body_pos: Vector3 = state.get("body_pos", Vector3.ZERO)
		var initial_pos: Vector3 = state.get("initial_pos", Vector3.ZERO)
		var body_r: float = float(state.get("body_radius", 0.4))
		# Top-down projection: world XZ -> screen XY.
		var scale: float = size.y * 0.12 * zoom
		# Camera follows body.
		var body_screen := center + Vector2(0, 0)
		# Ground grid.
		draw_rect(Rect2(Vector2(0, 0), size), Color(0.1, 0.15, 0.1), false, 1.0)
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
		# Distance label.
		draw_string(ThemeDB.fallback_font, Vector2(4, size.y - 6), "dist=%.2f  step %d  pos=(%.1f,%.1f,%.1f)" % [float(state.get("distance", 0.0)), state.get("steps", 0), body_pos.x, body_pos.y, body_pos.z], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))
