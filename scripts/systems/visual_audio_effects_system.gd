## System for managing visual and audio effects for destruction
## Handles particle effects, material changes, sounds, and animations

class_name VisualAudioEffectsSystem
extends RefCounted

## Dictionary of available particle effects
var particle_effects: Dictionary = {
    "smoke": preload("res://effects/particle_smoke.tscn"),
    "dust": preload("res://effects/particle_dust.tscn"),
    "sparks": preload("res://effects/particle_sparks.tscn"),
    "debris": preload("res://effects/particle_debris.tscn"),
    "wood_debris": preload("res://effects/particle_wood_debris.tscn"),
    "leaves": preload("res://effects/particle_leaves.tscn"),
    "bark_debris": preload("res://effects/particle_bark_debris.tscn")
}

## Dictionary of available audio effects
var audio_effects: Dictionary = {
    "metal_impact": preload("res://sounds/metal_impact.wav"),
    "explosion": preload("res://sounds/explosion.wav"),
    "wood_crack": preload("res://sounds/wood_crack.wav"),
    "structure_collapse": preload("res://sounds/structure_collapse.wav"),
    "tree_crack": preload("res://sounds/tree_crack.wav"),
    "tree_fall": preload("res://sounds/tree_fall.wav")
}

## Dictionary of available animation effects
var animation_effects: Dictionary = {
    "shake": "shake_animation",
    "slight_shake": "slight_shake_animation",
    "fall_animation": "fall_animation"
}

## Apply visual effects to an object based on its destruction stage and set
func apply_visual_effects(object, stage: int, object_set: String, effects_config: Dictionary) -> void:
    # Apply material changes
    _apply_material_changes(object, effects_config.get("material_changes", []))
    
    # Apply particle effects
    var particle_effects_list = effects_config.get("particle_effects", [])
    for effect_name in particle_effects_list:
        _spawn_particle_effect(object, effect_name)
    
    # Trigger animations
    var animation_triggers = effects_config.get("animation_triggers", [])
    for anim_name in animation_triggers:
        _trigger_animation(object, anim_name)

## Apply audio effects to an object based on its destruction stage and set
func apply_audio_effects(object, stage: int, object_set: String, effects_config: Dictionary) -> void:
    var sound_list = []
    
    # Choose sounds based on stage
    if stage == 1:  # Damaged
        sound_list = effects_config.get("damage_sounds", [])
    elif stage == 2:  # Ruined
        sound_list = effects_config.get("damage_sounds", [])
    elif stage == 3:  # Destroyed
        sound_list = effects_config.get("destruction_sounds", [])
    
    # Play a random sound from the list
    if sound_list.size() > 0:
        var sound_to_play = sound_list[randi() % sound_list.size()]
        _play_sound_effect(object, sound_to_play)

## Apply material changes to an object
func _apply_material_changes(object, material_changes: Array) -> void:
    # Check if the object is still in the tree before applying material changes
    if not object.is_inside_tree():
        return

    # Apply material changes to the object's mesh
    var mesh_instance = _get_mesh_instance(object)
    if mesh_instance:
        var material = mesh_instance.material_override
        if not material:
            material = mesh_instance.mesh.surface_get_material(0) if mesh_instance.mesh else null

        if material and material is BaseMaterial3D:
            for change in material_changes:
                match change:
                    "darken":
                        # Darken the material
                        var albedo = material.albedo_color
                        material.albedo_color = Color(albedo.r * 0.7, albedo.g * 0.7, albedo.b * 0.7, albedo.a)
                    "crack_texture":
                        # Apply a crack texture overlay
                        # This would require a more complex material setup
                        pass
                    "change_color":
                        # Change color based on object type
                        material.albedo_color = Color(0.6, 0.4, 0.2)  # Brown/earth tone

## Spawn a particle effect at the object's location
func _spawn_particle_effect(object, effect_name: String) -> void:
    if particle_effects.has(effect_name):
        var effect_scene = particle_effects[effect_name]
        if effect_scene:
            var effect_instance = effect_scene.instantiate()

            # Check if the object is still in the tree before accessing its properties
            if not object.is_inside_tree():
                # If object is not in tree, skip spawning the effect
                effect_instance.queue_free()
                return

            # Add to the scene first
            var parent = object.get_parent()
            if parent and parent.is_inside_tree():
                parent.add_child(effect_instance)
            else:
                # If no parent or parent not in tree, add to the root
                var root = object.get_tree().root
                root.add_child(effect_instance)

            # Now position the effect at the object's location (after it's in the tree)
            effect_instance.global_position = object.global_position

            # Auto-remove after lifetime
            var lifetime = 1.0  # Default lifetime
            if effect_instance.has_method("get_lifetime"):
                lifetime = effect_instance.get_lifetime()

            # Schedule removal using CONNECT_ONE_SHOT to prevent memory leaks
            object.get_tree().create_timer(lifetime).timeout.connect(
                func():
                    if is_instance_valid(effect_instance):
                        effect_instance.queue_free()
            , CONNECT_ONE_SHOT)

## Play a sound effect at the object's location
func _play_sound_effect(object, sound_name: String) -> void:
    if audio_effects.has(sound_name):
        var audio_stream = audio_effects[sound_name]
        if audio_stream:
            # Check if the object is still in the tree before proceeding
            if not object.is_inside_tree():
                # If object is not in tree, skip playing the sound
                return

            # Create an AudioStreamPlayer3D to play the sound at the object's location
            var audio_player = AudioStreamPlayer3D.new()
            audio_player.stream = audio_stream
            audio_player.volume_db = 5.0  # Adjust volume as needed
            audio_player.unit_size = 100.0  # Adjust audible range as needed
            audio_player.max_polyphony = 16  # Allow multiple simultaneous effects

            # Add to the scene first
            var parent = object.get_parent()
            if parent and parent.is_inside_tree():
                parent.add_child(audio_player)
            else:
                var root = object.get_tree().root
                root.add_child(audio_player)

            # Now set position (after it's in the tree)
            audio_player.global_position = object.global_position

            # Play the sound
            audio_player.play()

            # Auto-remove after sound finishes using CONNECT_ONE_SHOT to prevent memory leaks
            audio_player.finished.connect(func():
                if is_instance_valid(audio_player):
                    audio_player.queue_free()
            , CONNECT_ONE_SHOT)

## Trigger an animation on the object
func _trigger_animation(object, animation_name: String) -> void:
    # Placeholder for animation triggering
    # In a full implementation, this would trigger specific animations
    # based on the animation name
    match animation_name:
        "shake_animation":
            _apply_shake_animation(object)
        "slight_shake_animation":
            _apply_slight_shake_animation(object)
        "fall_animation":
            _apply_fall_animation(object)

## Apply shake animation to the object
func _apply_shake_animation(object) -> void:
    # Check if the object is still in the tree before applying animation
    if not object.is_inside_tree():
        return

    # Apply a shaking effect to the object
    var tween = object.create_tween()
    tween.set_parallel(false)

    var original_pos = object.position
    var shake_intensity = 0.5

    for i in range(10):
        var offset = Vector3(randf_range(-shake_intensity, shake_intensity),
                            randf_range(-shake_intensity, shake_intensity),
                            randf_range(-shake_intensity, shake_intensity))
        tween.tween_property(object, "position", original_pos + offset, 0.05)
        tween.tween_property(object, "position", original_pos, 0.05)

## Apply slight shake animation to the object
func _apply_slight_shake_animation(object) -> void:
    # Check if the object is still in the tree before applying animation
    if not object.is_inside_tree():
        return

    # Apply a subtle shaking effect to the object
    var tween = object.create_tween()
    tween.set_parallel(false)

    var original_pos = object.position
    var shake_intensity = 0.2

    for i in range(5):
        var offset = Vector3(randf_range(-shake_intensity, shake_intensity),
                            randf_range(-shake_intensity, shake_intensity),
                            randf_range(-shake_intensity, shake_intensity))
        tween.tween_property(object, "position", original_pos + offset, 0.08)
        tween.tween_property(object, "position", original_pos, 0.08)

## Apply fall animation to the object
func _apply_fall_animation(object) -> void:
    # Check if the object is still in the tree before applying animation
    if not object.is_inside_tree():
        return

    # Apply a falling animation to the object
    var tween = object.create_tween()
    tween.set_parallel(false)

    # Rotate the object to simulate falling
    var rotation_target = object.rotation + Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
    tween.tween_property(object, "rotation", rotation_target, 2.0)

    # Move downward
    var position_target = object.position - Vector3(0, 5, 0)
    tween.tween_property(object, "position", position_target, 2.0)

## Get the mesh instance from an object if it exists
func _get_mesh_instance(object) -> MeshInstance3D:
    # Try to find a MeshInstance3D in the object or its children
    if object is MeshInstance3D and object.is_inside_tree():
        return object

    # Search in children
    for child in object.get_children():
        if child is MeshInstance3D and child.is_inside_tree():
            return child
        # Recursively search deeper (only if child is in tree)
        if child.is_inside_tree():
            var result = _get_mesh_instance(child)
            if result:
                return result

    return null

## Preload all effect resources
func preload_effects() -> void:
    # This would preload all effect resources to avoid hitches during gameplay
    # Currently handled in the dictionary initialization
    pass