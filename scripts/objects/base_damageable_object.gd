## Base class for all damageable objects in the game
## Implements the DamageableObject interface and integrates with DamageManager

class_name BaseDamageableObject
extends Node3D

## Signal emitted when the object is destroyed
signal destroyed

## Current health of the object
var health: float = 100.0

## Maximum health of the object
var max_health: float = 100.0

## Object set this object belongs to (e.g., "Industrial", "Residential", etc.)
var object_set: String = "Default"

## Current destruction stage (0-3: intact, damaged, ruined, destroyed)
var destruction_stage: int = 0

## Whether the object is destroyed
var is_destroyed_flag: bool = false

## Reference to the hitbox/area that detects collisions
var hitbox: CollisionObject3D = null

## Initialize the damageable object with health and set
func initialize_damageable(health_value: float, set_name: String = "Default") -> void:
    health = health_value
    max_health = health_value
    object_set = set_name

    # Debug tree initialization
    var parent_name = get_parent().name if get_parent() else "NO_PARENT"
    if "Tree" in parent_name or "Tree" in name:
        print("🌳 INIT DAMAGEABLE: '%s' (parent: '%s') - Health: %.1f, Set: %s, In tree: %s" % [
            name, parent_name, health_value, set_name, is_inside_tree()
        ])

    # Register with DamageManager
    if DamageManager:
        var damage_manager = DamageManager
        damage_manager.register_damageable_object(self, object_set)
        if "Tree" in parent_name or "Tree" in name:
            print("✅ Registered '%s' with DamageManager" % name)
    else:
        print("⚠️ ERROR: DamageManager not available!")

## Apply damage to this object
func apply_damage(amount: float) -> void:
    if is_destroyed_flag:
        return

    # Debug tree damage
    var parent_name = get_parent().name if get_parent() else "NO_PARENT"
    if "Tree" in parent_name or "Tree" in name:
        print("💔 APPLY_DAMAGE: '%s' taking %.1f damage (Health: %.1f -> %.1f)" % [
            parent_name, amount, health, max(health - amount, 0.0)
        ])

    health = max(health - amount, 0.0)
    
    # Check if destroyed
    if health <= 0:
        health = 0
        is_destroyed_flag = true
        _on_destroyed()
    else:
        _on_damaged(amount)

## Get current health of the object
func get_health() -> float:
    return health

## Get maximum health of the object
func get_max_health() -> float:
    return max_health

## Check if the object is destroyed
func is_destroyed() -> bool:
    return is_destroyed_flag

## Get the current destruction stage of the object
func get_destruction_stage() -> int:
    return destruction_stage

## Set the object's health
func set_health(new_health: float) -> void:
    health = clamp(new_health, 0.0, max_health)

## Get the object set this object belongs to
func get_object_set() -> String:
    return object_set

## Set the object set for this object
func set_object_set(set_name: String) -> void:
    object_set = set_name
    if DamageManager:
        var damage_manager = DamageManager
        damage_manager.set_object_set(self, set_name)

## Called when the object takes damage
func _on_damaged(damage_amount: float) -> void:
    # Check if the object is still in the tree before updating
    if not is_inside_tree():
        return

    # Update destruction stage based on current health ratio
    var health_ratio = health / max_health
    if health_ratio <= 0.0:
        _update_destruction_stage(3)  # destroyed
    elif health_ratio <= 0.25:
        _update_destruction_stage(2)  # ruined
    elif health_ratio <= 0.5:
        _update_destruction_stage(1)  # damaged
    else:
        _update_destruction_stage(0)  # intact

## Update the destruction stage and apply corresponding effects
func _update_destruction_stage(new_stage: int) -> void:
    # Check if the object is still in the tree before updating
    if not is_inside_tree():
        return

    if new_stage != destruction_stage:
        var old_stage = destruction_stage
        destruction_stage = new_stage

        # Apply stage-specific visual effects
        _apply_stage_effects(new_stage)

        # Notify DamageManager of stage change
        if DamageManager:
            var damage_manager = DamageManager
            damage_manager.destruction_stage_changed.emit(self, old_stage, new_stage)

## Apply effects for the current destruction stage
func _apply_stage_effects(stage: int) -> void:
    # Check if the object is still in the tree before applying effects
    if not is_inside_tree():
        return

    # This would apply visual, audio, and other effects based on the stage
    # Implementation depends on the specific object type
    match stage:
        0:  # Intact
            # No special effects
            pass
        1:  # Damaged
            # Apply minor visual effects like cracks or scorch marks
            _apply_damaged_effects()
        2:  # Ruined
            # Apply moderate effects like broken parts or structural damage
            _apply_ruined_effects()
        3:  # Destroyed
            # Apply destruction effects
            _apply_destroyed_effects()

## Apply effects for damaged state
func _apply_damaged_effects() -> void:
    # Check if the object is still in the tree before applying effects
    if not is_inside_tree():
        return
    # Override in derived classes to implement specific effects
    pass

## Apply effects for ruined state
func _apply_ruined_effects() -> void:
    # Check if the object is still in the tree before applying effects
    if not is_inside_tree():
        return
    # Override in derived classes to implement specific effects
    pass

## Apply effects for destroyed state
func _apply_destroyed_effects() -> void:
    # Check if the object is still in the tree before applying effects
    if not is_inside_tree():
        return
    # Override in derived classes to implement specific effects
    pass

## Called when the object is destroyed
func _on_destroyed() -> void:
    # Apply destruction effects
    _apply_destroyed_effects()

    # Notify DamageManager
    if DamageManager:
        var damage_manager = DamageManager
        damage_manager.object_destroyed.emit(self)

    # Emit local signal
    destroyed.emit()

    # Optionally queue for deletion after delay to allow effects to play
    await get_tree().create_timer(2.0).timeout
    # Check if the node is still in the tree before queuing for removal
    if is_inside_tree():
        queue_free()

## Clean up when the object is freed
func _exit_tree() -> void:
    # Unregister from DamageManager
    if DamageManager:
        var damage_manager = DamageManager
        damage_manager.unregister_damageable_object(self)