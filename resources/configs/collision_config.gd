@tool
class_name CollisionConfig
extends Resource

## Configuration resource for collision properties
## Allows defining different collision behaviors for different object types

@export var enabled: bool = true
@export var distance_threshold: float = 2500.0
@export var lod_distances: Dictionary = {
    "near": 50.0,
    "mid": 100.0,
    "far": 200.0
}

@export var object_types: Dictionary = {
    "tree": {
        "enabled": true,
        "shape": "capsule",
        "scale_factor": 6.0,  # Match tree trunk height (6m)
        "density": 1.0,  # All trees get collision
        "flags": ["environment", "vegetation"]
    },
    "building": {
        "enabled": true,
        "shape": "box",
        "scale_factor": 0.9,
        "density": 1.0,
        "flags": ["structure", "obstacle"]
    },
    "rock": {
        "enabled": true,
        "shape": "sphere",
        "scale_factor": 0.7,
        "density": 0.3,
        "flags": ["environment", "terrain"]
    },
    "decoration": {
        "enabled": false,
        "shape": "box",
        "scale_factor": 0.5,
        "density": 0.1,
        "flags": ["environment", "detail"]
    }
}

## Get configuration for a specific object type
func get_object_type_config(object_type: String) -> Dictionary:
    if object_types.has(object_type):
        return object_types[object_type]
    return {}

## Check if collisions are enabled for an object type
func is_type_enabled(object_type: String) -> bool:
    var config = get_object_type_config(object_type)
    if config.has("enabled"):
        return config.enabled
    return false

## Get the collision shape type for an object type
func get_shape_type(object_type: String) -> String:
    var config = get_object_type_config(object_type)
    if config.has("shape"):
        return config.shape
    return "box"

## Get the scale factor for an object type
func get_scale_factor(object_type: String) -> float:
    var config = get_object_type_config(object_type)
    if config.has("scale_factor"):
        return config.scale_factor
    return 1.0

## Get the density for an object type (how frequently to apply collision)
func get_density(object_type: String) -> float:
    var config = get_object_type_config(object_type)
    if config.has("density"):
        return config.density
    return 1.0

## Update configuration for an object type
func update_object_type_config(object_type: String, new_config: Dictionary) -> void:
    object_types[object_type] = new_config

## Add a new object type to the configuration
func add_object_type(object_type: String, config: Dictionary) -> void:
    object_types[object_type] = config

## Get the flags for an object type
func get_flags(object_type: String) -> Array:
    var config = get_object_type_config(object_type)
    if config.has("flags"):
        return config.flags
    return []

## Check if an object type has a specific flag
func has_flag(object_type: String, flag: String) -> bool:
    var flags = get_flags(object_type)
    return flags.has(flag)

## Remove an object type from the configuration
func remove_object_type(object_type: String) -> void:
    object_types.erase(object_type)