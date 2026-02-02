## System for managing progressive destruction stages of objects
## Handles transitions between intact, damaged, ruined, and destroyed states

class_name DestructionStageSystem
extends RefCounted

## Destruction stage enum
enum DestructionStage {
    INTACT = 0,      ## Object is in perfect condition
    DAMAGED = 1,     ## Object has minor damage
    RUINED = 2,      ## Object has significant damage
    DESTROYED = 3    ## Object is completely destroyed
}

## Apply a destruction stage to an object based on its health percentage
static func apply_destruction_stage(object, health_percentage: float, object_set: String) -> DestructionStage:
    var stage = _determine_stage_from_health(health_percentage)
    
    # Apply stage-specific changes based on object set
    _apply_stage_changes(object, stage, object_set)
    
    return stage

## Determine the destruction stage based on health percentage
static func _determine_stage_from_health(health_percentage: float) -> DestructionStage:
    if health_percentage <= 0.0:
        return DestructionStage.DESTROYED
    elif health_percentage <= 0.25:
        return DestructionStage.RUINED
    elif health_percentage <= 0.5:
        return DestructionStage.DAMAGED
    else:
        return DestructionStage.INTACT

## Apply changes for a specific destruction stage
static func _apply_stage_changes(object, stage: DestructionStage, object_set: String) -> void:
    # Apply changes based on the stage and object set
    match stage:
        DestructionStage.INTACT:
            _apply_intact_stage(object, object_set)
        DestructionStage.DAMAGED:
            _apply_damaged_stage(object, object_set)
        DestructionStage.RUINED:
            _apply_ruined_stage(object, object_set)
        DestructionStage.DESTROYED:
            _apply_destroyed_stage(object, object_set)

## Apply changes for intact stage
static func _apply_intact_stage(object, object_set: String) -> void:
    # Reset any damage effects
    _reset_damage_effects(object)
    
    # Apply intact-specific properties based on object set
    _apply_set_properties(object, object_set, "intact")

## Apply changes for damaged stage
static func _apply_damaged_stage(object, object_set: String) -> void:
    # Apply visual effects for damage
    _apply_visual_damage_effects(object, "minor")
    
    # Apply damaged-specific properties based on object set
    _apply_set_properties(object, object_set, "damaged")

## Apply changes for ruined stage
static func _apply_ruined_stage(object, object_set: String) -> void:
    # Apply visual effects for severe damage
    _apply_visual_damage_effects(object, "major")
    
    # Apply ruined-specific properties based on object set
    _apply_set_properties(object, object_set, "ruined")

## Apply changes for destroyed stage
static func _apply_destroyed_stage(object, object_set: String) -> void:
    # Apply destruction effects
    _apply_destruction_effects(object, object_set)
    
    # Apply destroyed-specific properties based on object set
    _apply_set_properties(object, object_set, "destroyed")

## Apply visual damage effects
static func _apply_visual_damage_effects(object, severity: String) -> void:
    # This function would apply visual damage effects to the object
    # such as cracks, scorch marks, missing parts, etc.
    
    # For now, this is a placeholder - in a full implementation:
    # - Add crack textures based on severity
    # - Modify material properties (darkening, roughness changes)
    # - Hide/remove parts of the mesh
    # - Add burn marks or other damage indicators
    pass

## Apply destruction effects
static func _apply_destruction_effects(object, object_set: String) -> void:
    # Apply effects when object is destroyed
    # This would include:
    # - Particle effects
    # - Sound effects
    # - Physics effects (debris, forces)
    # - Geometry changes (breaking apart)
    
    # Get object set configuration
    if Engine.has_singleton("DamageManager"):
        var damage_manager = Engine.get_singleton("DamageManager")
        var config = damage_manager.get_set_config(object_set)
        
        # Apply effects based on configuration
        _apply_effects_from_config(object, config)

## Apply effects from configuration
static func _apply_effects_from_config(object, config: Dictionary) -> void:
    # Apply visual effects
    var visual_effects = config.get("visual_effects", {})
    _apply_visual_effects(object, visual_effects)
    
    # Apply audio effects
    var audio_effects = config.get("audio_effects", {})
    _apply_audio_effects(object, audio_effects)
    
    # Apply physics effects
    var physics_props = config.get("physics_properties", {})
    _apply_physics_effects(object, physics_props)

## Apply visual effects from config
static func _apply_visual_effects(object, effects_config: Dictionary) -> void:
    # Apply particle effects, material changes, etc.
    var particle_effects = effects_config.get("particle_effects", [])
    for effect_name in particle_effects:
        _spawn_particle_effect(object, effect_name)

## Apply audio effects from config
static func _apply_audio_effects(object, effects_config: Dictionary) -> void:
    # Play sound effects
    var destruction_sounds = effects_config.get("destruction_sounds", [])
    if destruction_sounds.size() > 0:
        var sound_to_play = destruction_sounds[randi() % destruction_sounds.size()]
        _play_sound_effect(object, sound_to_play)

## Apply physics effects from config
static func _apply_physics_effects(object, physics_config: Dictionary) -> void:
    # Apply physics changes like debris generation
    var debris_enabled = physics_config.get("debris_enabled", true)
    if debris_enabled:
        var count_range = physics_config.get("debris_count_range", {"min": 1, "max": 5})
        var size_range = physics_config.get("debris_size_range", {"min": 0.5, "max": 2.0})
        
        _generate_debris(object, count_range, size_range)

## Apply set-specific properties
static func _apply_set_properties(object, object_set: String, stage: String) -> void:
    # Apply properties specific to the object set and current stage
    # This could include material changes, mesh modifications, etc.
    pass

## Reset damage effects
static func _reset_damage_effects(object) -> void:
    # Reset any applied damage effects to return to intact state
    pass

## Spawn a particle effect at the object's location
static func _spawn_particle_effect(object, effect_name: String) -> void:
    # Placeholder for spawning particle effects
    # In a full implementation, this would instantiate and configure
    # particle systems based on the effect name
    pass

## Play a sound effect at the object's location
static func _play_sound_effect(object, sound_name: String) -> void:
    # Placeholder for playing sound effects
    # In a full implementation, this would play appropriate sounds
    pass

## Generate debris from the object
static func _generate_debris(object, count_range: Dictionary, size_range: Dictionary) -> void:
    # Placeholder for generating debris
    # In a full implementation, this would create debris objects
    # with appropriate physics properties
    pass