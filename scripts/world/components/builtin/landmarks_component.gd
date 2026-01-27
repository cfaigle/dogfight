extends WorldComponentBase
class_name LandmarksComponent

func get_priority() -> int:
    return 50

func get_optional_params() -> Dictionary:
    return {
        "landmark_count": 24,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("LandmarksComponent: missing ctx/terrain_generator")
        return

    var props_layer: Node3D = ctx.get_layer("Props")
    ctx.terrain_generator.build_landmarks(props_layer, params, rng)
