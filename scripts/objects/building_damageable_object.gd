## Building-specific damageable object
## Extends the base damageable object with building-specific functionality

class_name BuildingDamageableObject
extends BaseDamageableObject

## Building type (used to determine appropriate object set)
var building_type: String = "generic"

## Reference to the building's mesh
var building_mesh: MeshInstance3D = null

## Initialize the building damageable object
func _ready() -> void:
    # Find the building mesh in children
    building_mesh = _find_building_mesh()
    
    # Use the building_type set during creation, or fall back to name
    if building_type.is_empty():
        building_type = name.to_lower()
    
    # Assign appropriate object set based on building type
    var object_set = _determine_object_set(building_type)
    
    # Initialize with appropriate health based on set
    var health = _get_health_for_set(object_set)
    
    print("DEBUG: Initializing building damageable - type: ", building_type, " set: ", object_set, " health: ", health)
    initialize_damageable(health, object_set)

## Determine the object set based on building type
func _determine_object_set(building_type: String) -> String:
    # Map building types to appropriate object sets
    var type_to_set_map = {
        "factory": "Industrial",
        "warehouse": "Industrial", 
        "mill": "Industrial",
        "power_station": "Industrial",
        "foundry": "Industrial",
        "workshop": "Industrial",
        "industrial": "Industrial",
        "house": "Residential",
        "cottage": "Residential",
        "inn": "Residential",
        "tavern": "Residential",
        "pub": "Residential",
        "farmhouse": "Residential",
        "barn": "Residential",
        "stone_cottage": "Residential",
        "thatched_cottage": "Residential",
        "white_stucco_house": "Residential",
        "house_victorian": "Residential",
        "house_tudor": "Residential",
        "house_colonial": "Residential",
        "shop": "Residential",  # Small shops often residential style
        "windmill": "Residential",  # Often residential style
        "tree": "Natural",
        "pine": "Natural",
        "oak": "Natural",
        "birch": "Natural",
        "bush": "Natural",
        "rock": "Natural",
        "stone": "Natural"
    }
    
    if type_to_set_map.has(building_type):
        return type_to_set_map[building_type]
    
    # Default to residential if no specific mapping
    return "Residential"

## Get appropriate health for the object set
func _get_health_for_set(object_set: String) -> float:
    var set_config = {}
    if Engine.has_singleton("DamageManager"):
        var damage_manager = Engine.get_singleton("DamageManager")
        set_config = damage_manager.get_set_config(object_set)
    
    if set_config.has("health_range"):
        var health_range = set_config.health_range
        var min_health = health_range.get("min", 50.0)
        var max_health = health_range.get("max", 100.0)
        return randf_range(min_health, max_health)
    
    # Default health
    return 100.0

## Find the building mesh in the children
func _find_building_mesh() -> MeshInstance3D:
    for child in get_children():
        if child is MeshInstance3D and child.is_inside_tree():
            return child
        # Recursively search in children (only if child is in tree)
        if child.is_inside_tree():
            var result = _search_mesh_recursive(child)
            if result:
                return result
    return null

## Recursively search for mesh in children
func _search_mesh_recursive(node) -> MeshInstance3D:
    if node is MeshInstance3D and node.is_inside_tree():
        return node

    for child in node.get_children():
        if child is MeshInstance3D and child.is_inside_tree():
            return child
        var result = _search_mesh_recursive(child)
        if result:
            return result

    return null

## Apply damaged effects
func _apply_damaged_effects() -> void:
    # Check if the object is still in the tree before applying effects
    if not is_inside_tree() or not building_mesh:
        return

    # Change material to show damage
    var material = building_mesh.material_override
    if not material:
        material = StandardMaterial3D.new()
        building_mesh.material_override = material

    # Darken the material slightly
    var current_color = material.albedo_color
    material.albedo_color = Color(current_color.r * 0.8, current_color.g * 0.8, current_color.b * 0.8, current_color.a)

## Apply ruined effects
func _apply_ruined_effects() -> void:
    # Check if the object is still in the tree before applying effects
    if not is_inside_tree() or not building_mesh:
        return

    # More significant material changes
    var material = building_mesh.material_override
    if not material:
        material = StandardMaterial3D.new()
        building_mesh.material_override = material

    # Further darken and add damage indicators
    var current_color = material.albedo_color
    material.albedo_color = Color(current_color.r * 0.6, current_color.g * 0.6, current_color.b * 0.7, current_color.a)

    # Add emissive effect to simulate fires or damage
    material.emission_enabled = true
    material.emission = Color(0.8, 0.4, 0.1)  # Reddish orange for damage/fire
    material.emission_energy = 0.5

## Apply destroyed effects
func _apply_destroyed_effects() -> void:
    # Check if the object is still in the tree before applying effects
    if not is_inside_tree():
        return

    # Generate building debris before material changes
    _generate_building_debris()

    if building_mesh:
        # Significant material changes for destruction
        var material = building_mesh.material_override
        if not material:
            material = StandardMaterial3D.new()
            building_mesh.material_override = material

        # Make almost completely dark
        material.albedo_color = Color(0.2, 0.2, 0.2, material.albedo_color.a)

        # Increase emission for fire/smoke effect
        material.emission_enabled = true
        material.emission = Color(0.9, 0.5, 0.2)  # More intense fire color
        material.emission_energy = 1.0

## Called when the building is destroyed
func _on_destroyed() -> void:
    # Apply destruction effects
    _apply_destroyed_effects()

    # Notify DamageManager
    if Engine.has_singleton("DamageManager"):
        var damage_manager = Engine.get_singleton("DamageManager")
        damage_manager.object_destroyed.emit(self)

    # Emit local signal
    destroyed.emit()

    # In a full implementation, we would:
    # - Apply geometry changes (remove parts, add holes, break into pieces)
    # - Spawn debris
    # - Apply physics to parts
    # For now, we'll just fade out
    var tween = create_tween()
    tween.tween_method(func(val):
        if building_mesh and building_mesh.material_override and is_instance_valid(building_mesh.material_override):
            var mat = building_mesh.material_override
            mat.albedo_color = Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, val)
    , 1.0, 0.0, 2.0)

    # Queue for removal after effect completes
    await tween.finished
    # Check if the node is still in the tree before queuing for removal
    if is_inside_tree():
        queue_free()

## Generate building debris based on object set
func _generate_building_debris() -> void:
    # Check if the object is still in the tree before generating debris
    if not is_inside_tree():
        return

    # Get debris configuration from DamageManager
    if not Engine.has_singleton("DamageManager"):
        return

    var damage_manager = Engine.get_singleton("DamageManager")
    var obj_set = damage_manager.get_object_set(self)
    var set_config = damage_manager.get_set_config(obj_set)

    var physics_config = set_config.get("physics_properties", {})
    if not physics_config.get("debris_enabled", false):
        return

    # Get debris count range
    var debris_count_range = physics_config.get("debris_count_range", {"min": 2, "max": 4})
    var debris_size_range = physics_config.get("debris_size_range", {"min": 0.5, "max": 1.5})
    var debris_count = randi_range(debris_count_range.min, debris_count_range.max)

    # Get building AABB for positioning
    var building_aabb = AABB()
    if building_mesh:
        building_aabb = building_mesh.get_aabb()
    else:
        # Default fallback size
        building_aabb = AABB(Vector3(-2, 0, -2), Vector3(4, 6, 4))

    # Create debris pieces
    for i in range(debris_count):
        _create_debris_piece(building_aabb, debris_size_range)

## Create a debris piece within building bounds
func _create_debris_piece(source_aabb: AABB, size_range: Dictionary) -> void:
    # Check if the object is still in the tree before creating debris
    if not is_inside_tree() or not building_mesh:
        return

    # Create RigidBody3D for physics simulation
    var debris = RigidBody3D.new()

    # Random position within building AABB (±40% XZ, 0-80% Y)
    var x_offset = randf_range(-source_aabb.size.x * 0.4, source_aabb.size.x * 0.4)
    var y_offset = randf_range(0, source_aabb.size.y * 0.8)
    var z_offset = randf_range(-source_aabb.size.z * 0.4, source_aabb.size.z * 0.4)

    debris.global_position = global_position + Vector3(x_offset, y_offset, z_offset)

    # Create MeshInstance3D with box shape
    var mesh_instance = MeshInstance3D.new()
    var box_mesh = BoxMesh.new()
    var debris_size = randf_range(size_range.min, size_range.max)
    # Make pieces slightly taller
    box_mesh.size = Vector3(debris_size, debris_size * 1.5, debris_size)
    mesh_instance.mesh = box_mesh

    # Copy material from building
    if building_mesh.material_override:
        mesh_instance.material_override = building_mesh.material_override.duplicate()
    elif building_mesh.mesh and building_mesh.mesh.surface_get_material(0):
        mesh_instance.material_override = building_mesh.mesh.surface_get_material(0).duplicate()

    debris.add_child(mesh_instance)

    # Add collision shape
    var collision_shape = CollisionShape3D.new()
    var box_shape = BoxShape3D.new()
    box_shape.size = Vector3(debris_size, debris_size * 1.5, debris_size)
    collision_shape.shape = box_shape
    debris.add_child(collision_shape)

    # Add to scene
    var parent = get_parent()
    if parent and parent.is_inside_tree():
        parent.add_child(debris)
    else:
        get_tree().root.add_child(debris)

    # Apply explosive impulse from building center + upward component
    var direction_from_center = (debris.global_position - global_position).normalized()
    if direction_from_center.length() < 0.1:
        direction_from_center = Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)).normalized()
    else:
        # Add upward component
        direction_from_center = (direction_from_center + Vector3(0, 0.5, 0)).normalized()

    var impulse_force = randf_range(40, 100)
    debris.apply_central_impulse(direction_from_center * impulse_force)

    # Add angular velocity for tumbling
    var angular_velocity = Vector3(
        randf_range(-5, 5),
        randf_range(-5, 5),
        randf_range(-5, 5)
    )
    debris.angular_velocity = angular_velocity

    # Fade out at 7s, remove at 8s using CONNECT_ONE_SHOT to prevent memory leaks
    get_tree().create_timer(7.0).timeout.connect(
        func():
            if is_instance_valid(debris) and is_instance_valid(mesh_instance):
                var mat = mesh_instance.material_override
                if mat:
                    var tween = debris.create_tween()
                    var fade_func = func(val):
                        if is_instance_valid(mat):
                            mat.albedo_color = Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, val)
                    tween.tween_method(fade_func, 1.0, 0.0, 1.0)
    , CONNECT_ONE_SHOT)

    get_tree().create_timer(8.0).timeout.connect(
        func():
            if is_instance_valid(debris):
                debris.queue_free()
    , CONNECT_ONE_SHOT)
    