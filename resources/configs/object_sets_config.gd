@tool
class_name ObjectSetsConfig
extends Resource

## Configuration for different object sets with their properties
## Each set defines health, destruction effects, and geometry changes

@export var sets: Dictionary = {}

## Add a new object set configuration
func add_set(set_name: String, config: Dictionary) -> void:
    sets[set_name] = config

## Get configuration for a specific set
func get_set_config(set_name: String) -> Dictionary:
    if sets.has(set_name):
        return sets[set_name]
    return {}

## Get health range for a set
func get_health_range(set_name: String) -> Dictionary:
    var config = get_set_config(set_name)
    if config.has("health_range"):
        return config.health_range
    # Default health range if not specified
    return {"min": 50.0, "max": 100.0}

## Get destruction stages for a set
func get_destruction_stages(set_name: String) -> Array:
    var config = get_set_config(set_name)
    if config.has("destruction_stages"):
        return config.destruction_stages
    # Default stages if not specified
    return [
        {"threshold": 1.0, "effect": "intact"},
        {"threshold": 0.66, "effect": "damaged"},
        {"threshold": 0.33, "effect": "ruined"},
        {"threshold": 0.0, "effect": "destroyed"}
    ]

## Get geometry changes for a set
func get_geometry_changes(set_name: String) -> Dictionary:
    var config = get_set_config(set_name)
    if config.has("geometry_changes"):
        return config.geometry_changes
    # Default geometry changes if not specified
    return {
        "remove_parts": false,
        "add_holes": false,
        "collapse_sections": false,
        "break_into_pieces": false
    }

## Get visual effects for a set
func get_visual_effects(set_name: String) -> Dictionary:
    var config = get_set_config(set_name)
    if config.has("visual_effects"):
        return config.visual_effects
    # Default visual effects if not specified
    return {
        "particle_effects": [],
        "material_changes": [],
        "animation_triggers": []
    }

## Get audio effects for a set
func get_audio_effects(set_name: String) -> Dictionary:
    var config = get_set_config(set_name)
    if config.has("audio_effects"):
        return config.audio_effects
    # Default audio effects if not specified
    return {
        "damage_sounds": [],
        "destruction_sounds": []
    }

## Get physics properties for a set
func get_physics_properties(set_name: String) -> Dictionary:
    var config = get_set_config(set_name)
    if config.has("physics_properties"):
        return config.physics_properties
    # Default physics properties if not specified
    return {
        "debris_enabled": true,
        "debris_count_range": {"min": 1, "max": 5},
        "debris_size_range": {"min": 0.5, "max": 2.0}
    }