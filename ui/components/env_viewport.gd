## Live visualization of a single env instance. Instantiates the env's scene
## inside a SubViewport with a camera, and reads env state each frame to
## display info. The env's physics is driven by the SceneTree (NOT by the
## Evaluator), so this is purely for visualization.
extends SubViewportContainer
class_name EnvViewport

@onready var _viewport: SubViewport = $Viewport
@onready var _camera_2d: Camera2D = $Viewport/Camera2D
@onready var _camera_3d: Camera3D = $Viewport/Camera3D
@onready var _info: Label = $Info

var env: Node = null
var env_scene: PackedScene = null
var view_type: String = "2d"

func set_env_scene(p_scene: PackedScene, p_view_type: String) -> void:
        env_scene = p_scene
        view_type = p_view_type
        _rebuild()

func _rebuild() -> void:
        # Clear existing env.
        for c in _viewport.get_children():
                if c is Camera2D or c is Camera3D:
                        continue
                c.queue_free()
        if env_scene == null:
                return
        env = env_scene.instantiate()
        _viewport.add_child(env)
        # Enable the right camera.
        _camera_2d.visible = (view_type == "2d")
        _camera_3d.visible = (view_type == "3d")
        # Auto-position camera based on env type. Camera2D.zoom is the zoom-in
        # factor, so zoom=(80, 80) means 1 world unit = 80 px on screen.
        if view_type == "2d":
                _camera_2d.position = Vector2.ZERO
                _camera_2d.zoom = Vector2(80, 80)
        else:
                _camera_3d.position = Vector3(0, 2, 3)

func _process(_delta: float) -> void:
        if env == null or not is_instance_valid(env):
                return
        if env.has_method("get_visual_state"):
                var state: Dictionary = env.get_visual_state()
                _info.text = _format_info(state)

func _format_info(state: Dictionary) -> String:
        var lines: Array = []
        if state.has("steps"):
                lines.append("step %d/%d" % [int(state.get("steps", 0)), int(state.get("max_steps", 0))])
        if state.has("done") and state.get("done"):
                lines.append("DONE")
        if state.has("distance"):
                lines.append("dist=%.2f" % float(state.get("distance", 0)))
        if state.has("score_a"):
                lines.append("score %d-%d" % [int(state.get("score_a", 0)), int(state.get("score_b", 0))])
        if state.has("best") or state.has("best_fitness"):
                pass  # already shown elsewhere
        return "\n".join(lines)
