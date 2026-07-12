## Environment selection screen: shows a grid of env cards. Emits `selected`.
extends MarginContainer
class_name EnvSelectScreen

signal selected(index: int)
signal back_requested()

const EnvCardScene: PackedScene = preload("res://ui/components/env_card.tscn")

const ENVS: Array = [
        {
                "name": "XOR",
                "desc": "Classic NEAT benchmark.\nLearn the XOR truth table.",
                "color": Color(0.3, 0.8, 0.4),
                "has_viz": false,
                "physics": false,
        },
        {
                "name": "CartPole",
                "desc": "Balance a pole on\na moving cart.",
                "color": Color(0.3, 0.7, 1.0),
                "has_viz": true,
                "physics": true,
        },
        {
                "name": "Acrobot",
                "desc": "Swing up a two-link\nunderactuated pendulum.",
                "color": Color(0.9, 0.6, 0.2),
                "has_viz": true,
                "physics": true,
        },
        {
                "name": "Pong",
                "desc": "Play pong vs top-3 from\nprevious gen (tournament).",
                "color": Color(0.9, 0.3, 0.5),
                "has_viz": true,
                "physics": true,
        },
        {
                "name": "Spider 2D",
                "desc": "Walk a 4-legged creature\nforward (2D side view).",
                "color": Color(0.7, 0.5, 0.9),
                "has_viz": true,
                "physics": true,
        },
        {
                "name": "Spider 3D",
                "desc": "Walk a 4-legged creature\nforward (3D top-down).",
                "color": Color(0.5, 0.9, 0.7),
                "has_viz": true,
                "physics": true,
        },
]

@onready var _grid: GridContainer = $VBox/Center/Grid

func _ready() -> void:
        for i in range(ENVS.size()):
                var card := EnvCardScene.instantiate() as EnvCard
                card.env_index = i
                card.env_name = ENVS[i].name
                card.env_desc = ENVS[i].desc
                _grid.add_child(card)
                card.selected.connect(_on_card_selected)

func _on_card_selected(idx: int) -> void:
        selected.emit(idx)

func _input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
                back_requested.emit()
