extends Node3D
## Base helper for one-shot particle effect scenes.

@export var lifetime: float = 1.0

func get_lifetime() -> float:
    return lifetime

func _ready() -> void:
    # Start any particle children if they exist.
    for c in get_children():
        if c is GPUParticles3D:
            var p := c as GPUParticles3D
            p.emitting = true
