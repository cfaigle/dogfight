extends Node
signal died
signal changed(hp: float, max_hp: float)

@export var max_hp = 100.0
var hp = 100.0

func _ready() -> void:
    hp = max_hp

func reset() -> void:
    hp = max_hp
    changed.emit(hp, max_hp)

func apply_damage(amount: float) -> void:
    if hp <= 0.0:
        return
    hp = max(hp - amount, 0.0)
    changed.emit(hp, max_hp)
    if hp <= 0.0:
        died.emit()
