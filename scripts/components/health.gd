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

    # Apply damage using the new damage system if available
    if Engine.has_singleton("DamageManager"):
        var damage_manager = Engine.get_singleton("DamageManager")
        # Since this is called from the plane, we'll apply damage to the parent
        var parent = get_parent()
        if parent and parent.has_method("apply_damage"):
            # Call the parent's apply_damage which will route through the damage manager
            parent.apply_damage(amount)
            return

    # Fallback to original damage application
    hp = max(hp - amount, 0.0)
    changed.emit(hp, max_hp)  # Emit current hp and max hp
    if hp <= 0.0:
        died.emit()
