extends Node
@export var life = 1.0
var _t = 0.0

func _process(dt: float) -> void:
    _t += dt
    if _t >= life:
        get_parent().queue_free()
