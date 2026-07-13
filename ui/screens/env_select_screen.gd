## Environment selection screen: shows a grid of env cards. Emits `selected`.
extends MarginContainer
class_name EnvSelectScreen

signal selected(index: int)
signal back_requested()

const EnvCardScene: PackedScene = preload("res://ui/components/env_card.tscn")

const ENVS: Array = [
        {
                "name": "CartPole",
                "desc": "Balance a pole on\na moving cart.",
                "color": Color(0.3, 0.7, 1.0),
                "has_viz": true,
                "physics": true,
        },
        {
                "name": "Pong",
                "desc": "Control a paddle to hit\nthe bouncing ball.",
                "color": Color(0.9, 0.3, 0.5),
                "has_viz": true,
                "physics": true,
        },
        {
                "name": "LunarLander",
                "desc": "Fire thrusters to land\nsafely on the pad.",
                "color": Color(0.4, 0.9, 0.5),
                "has_viz": true,
                "physics": true,
        },
        {
                "name": "BipedalWalker",
                "desc": "Walk forward on two legs\nwithout falling.",
                "color": Color(0.9, 0.6, 0.2),
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
                card.env_color = ENVS[i].color
                _grid.add_child(card)
                card.selected.connect(_on_card_selected)

func _on_card_selected(idx: int) -> void:
        selected.emit(idx)
