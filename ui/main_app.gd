## Main application: composes EnvSelectScreen, ConfigScreen, and RunScreen.
## Switches between them based on user navigation.
extends Control

const EnvSelectScreenScene: PackedScene = preload("res://ui/screens/env_select_screen.tscn")
const ConfigScreenScene: PackedScene = preload("res://ui/screens/config_screen.tscn")
const RunScreenScene: PackedScene = preload("res://ui/screens/run_screen.tscn")

enum Screen { ENV_SELECT, CONFIG, RUN }

@onready var _screens: Control = $Screens
@onready var _env_select_slot: MarginContainer = $Screens/EnvSelectScreen
@onready var _config_slot: MarginContainer = $Screens/ConfigScreen
@onready var _run_slot: MarginContainer = $Screens/RunScreen

var _env_select: EnvSelectScreen
var _config_screen: ConfigScreen
var _run_screen: RunScreen

var _env_idx: int = -1

func _ready() -> void:
        _env_select = EnvSelectScreenScene.instantiate()
        _env_select_slot.add_child(_env_select)
        _env_select.selected.connect(_on_env_selected)
        _env_select.back_requested.connect(func(): get_tree().quit())
        _config_screen = ConfigScreenScene.instantiate()
        _config_slot.add_child(_config_screen)
        _config_screen.back_requested.connect(func(): _show_screen(Screen.ENV_SELECT))
        _config_screen.start_requested.connect(_on_start_training)
        # Run screen is instantiated lazily when training starts.
        _show_screen(Screen.ENV_SELECT)

func _show_screen(s: int) -> void:
        # When leaving the RUN screen, free the RunScreen so its SceneEvaluator's
        # SubViewports stop consuming CPU. The user always starts a fresh training
        # when they next click "Start Training", so no state is lost.
        if s != Screen.RUN and _run_screen != null:
                _free_run_screen()
        _env_select_slot.visible = (s == Screen.ENV_SELECT)
        _config_slot.visible = (s == Screen.CONFIG)
        _run_slot.visible = (s == Screen.RUN)

func _free_run_screen() -> void:
        if _run_screen == null:
                return
        for c in _run_slot.get_children():
                c.queue_free()
        _run_screen = null

func _on_env_selected(idx: int) -> void:
        _env_idx = idx
        _config_screen.configure_for_env(idx)
        _show_screen(Screen.CONFIG)

func _on_start_training(config: NeatConfig, extra: Dictionary) -> void:
        # Free any existing run screen (also disposes its SceneEvaluator).
        _free_run_screen()
        # Wait a frame for the queue_free to take effect, then instantiate.
        await get_tree().process_frame
        _run_screen = RunScreenScene.instantiate()
        _run_slot.add_child(_run_screen)
        var pop := Population.new(config)
        pop.initialize()
        _run_screen.setup(_env_idx, config, extra, pop)
        _run_screen.back_requested.connect(func(): _show_screen(Screen.ENV_SELECT))
        _run_screen.config_requested.connect(func():
                _config_screen.configure_for_env(_env_idx)
                _show_screen(Screen.CONFIG))
        _show_screen(Screen.RUN)
