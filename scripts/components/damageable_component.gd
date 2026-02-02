## Component that makes objects damageable
## Can be attached to trees, buildings, or other objects to make them destructible

class_name DamageableComponent
extends Node3D

## Signal emitted when health changes
signal health_changed(current: float, max: float)

## Signal emitted when object is destroyed
signal destroyed

## Properties
var max_health: float = 100.0
var current_health: float = 100.0
var object_type: String = "generic"
var is_destroyed: bool = false

## Visual effects for damage
var damage_effects: Node3D = null

func _ready() -> void:
    current_health = max_health

## Apply damage to this object
func apply_damage(amount: float) -> void:
    if is_destroyed:
        return
    
    current_health -= amount
    current_health = max(current_health, 0.0)
    
    # Emit health changed signal
    health_changed.emit(current_health, max_health)
    
    # Check if destroyed
    if current_health <= 0:
        _on_destroyed()
    
    # Update visual damage effects
    _update_damage_visuals()

## Update visual effects based on damage
func _update_damage_visuals() -> void:
    var health_ratio = current_health / max_health
    
    # Change material based on damage level
    var parent_mesh = get_parent() as MeshInstance3D
    if parent_mesh and parent_mesh.mesh:
        var mat = parent_mesh.mesh.surface_get_material(0) if parent_mesh.mesh.get_surface_count() > 0 else null
        
        if mat and mat is StandardMaterial3D:
            # Darken the material as damage increases
            var base_color = mat.albedo_color
            var damage_factor = 1.0 - health_ratio
            mat.albedo_color = Color(
                base_color.r * (1.0 - damage_factor * 0.5),
                base_color.g * (1.0 - damage_factor * 0.7),
                base_color.b * (1.0 - damage_factor * 0.9)
            )

## Called when the object is destroyed
func _on_destroyed() -> void:
    is_destroyed = true
    
    # Apply destruction effects
    _apply_destruction_effects()
    
    # Emit destroyed signal
    destroyed.emit()
    
    # Optionally remove the object after a delay to allow effects to play
    await get_tree().create_timer(0.1).timeout
    queue_free()

## Apply destruction effects
func _apply_destruction_effects() -> void:
    # Create particle effects for destruction
    _spawn_destruction_particles()
    
    # If this is a building or tree, we might want to break it into pieces
    _break_into_pieces()

## Spawn destruction particles
func _spawn_destruction_particles() -> void:
    # Create a simple particle system for destruction
    var particles = GPUParticles3D.new()
    particles.name = "DestructionParticles"
    particles.emitting = true
    particles.amount = 30
    particles.lifetime = 2.0
    particles.one_shot = true
    
    # Set up particle material
    var particle_mat = ParticleProcessMaterial.new()
    particle_mat.direction = Vector3(0, 1, 0)
    particle_mat.initial_velocity_min = 2.0
    particle_mat.initial_velocity_max = 10.0
    particle_mat.angular_velocity_min = -180
    particle_mat.angular_velocity_max = 180
    particle_mat.scale_min = 0.1
    particle_mat.scale_max = 0.5
    particle_mat.die_after_emit = true
    
    # Color from red/orange/yellow to simulate debris
    var color_ramp = Gradient.new()
    color_ramp.add_point(0.0, Color.YELLOW)
    color_ramp.add_point(0.5, Color.ORANGE)
    color_ramp.add_point(1.0, Color.RED)
    particle_mat.color_ramp = color_ramp
    
    particles.process_material = particle_mat
    
    # Position at the object's location
    global_position = global_position
    
    # Add to parent scene
    var parent_scene = get_tree().root
    parent_scene.add_child(particles)
    
    # Auto-remove after particles finish
    var timer = Timer.new()
    add_child(timer)
    timer.timeout.connect(func():
        if particles and is_instance_valid(particles):
            particles.queue_free()
        if timer and is_instance_valid(timer):
            timer.queue_free()
    )
    timer.start(particles.lifetime + 0.5)

## Break object into pieces (placeholder implementation)
func _break_into_pieces() -> void:
    # In a full implementation, this would break the mesh into smaller pieces
    # For now, we'll just simulate it with particles
    pass

## Get current health percentage
func get_health_percent() -> float:
    return current_health / max_health if max_health > 0 else 0.0