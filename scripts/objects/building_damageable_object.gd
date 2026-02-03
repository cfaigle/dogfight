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
    # Find the building mesh in parent's children (siblings)
    building_mesh = _find_building_mesh()

    # Use the building_type set during creation, or fall back to name
    if building_type.is_empty():
        building_type = name.to_lower()

    # Assign appropriate object set based on building type
    var object_set = _determine_object_set(building_type)

    # Initialize with appropriate health based on set
    var health = _get_health_for_set(object_set)

    # Check if we can get the original material
    var test_material = _get_original_building_material()
    var material_found = test_material != null
    var material_color = "none"
    if test_material:
        material_color = "%.2f,%.2f,%.2f" % [test_material.albedo_color.r, test_material.albedo_color.g, test_material.albedo_color.b]

    print("🏗️ NEW CODE: Initializing building '%s' - type: %s, set: %s, health: %.1f, mesh: %s, material: %s, color: %s" % [
        get_parent().name if get_parent() else "?", building_type, object_set, health,
        building_mesh != null, material_found, material_color
    ])
    initialize_damageable(health, object_set)

    # CRITICAL: Connect to DamageManager signals to apply our custom effects
    # DamageManager bypasses apply_damage() and calls set_health() directly, so we need to hook into its signals
    if DamageManager:
        print("🔌 Connecting to DamageManager signals for: %s" % get_parent().name)
        DamageManager.destruction_stage_changed.connect(_on_damage_manager_stage_changed)
        DamageManager.object_destroyed.connect(_on_damage_manager_destroyed)

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
        "maple": "Natural",
        "spruce": "Natural",
        "fir": "Natural",
        "cedar": "Natural",
        "ash": "Natural",
        "palm": "Natural",
        "conifer": "Natural",
        "broadleaf": "Natural",
        "bush": "Natural",
        "rock": "Natural",
        "stone": "Natural"
    }
    
    if type_to_set_map.has(building_type):
        return type_to_set_map[building_type]
    
    # Default to residential if no specific mapping
    return "Residential"

## Check if this object is a tree
func _is_tree() -> bool:
    var tree_types = ["tree", "pine", "oak", "birch", "maple", "spruce", "fir", "cedar"]
    return building_type.to_lower() in tree_types

## Handle DamageManager's stage change signal (this is how effects are ACTUALLY triggered)
func _on_damage_manager_stage_changed(object, old_stage: int, new_stage: int) -> void:
    # Only respond if this is OUR object
    if object != self:
        return

    print("🎯 DamageManager stage change: %s from %d to %d" % [get_parent().name if get_parent() else "?", old_stage, new_stage])

    # Apply appropriate effects based on new stage
    match new_stage:
        1:  # Damaged
            _apply_damaged_effects()
        2:  # Ruined
            _apply_ruined_effects()
        3:  # Destroyed
            _apply_destroyed_effects()

## Handle DamageManager's destruction signal
func _on_damage_manager_destroyed(object) -> void:
    # Only respond if this is OUR object
    if object != self:
        return

    print("💀 DamageManager destroyed: %s" % (get_parent().name if get_parent() else "?"))
    # _apply_destroyed_effects() should have already been called by stage change to stage 3
    # But call it again just in case
    _apply_destroyed_effects()

## NOTE: apply_damage() is NOT called when DamageManager is active
## DamageManager calls set_health() directly and uses its own effect system
## We hook into DamageManager via signals instead (see _on_damage_manager_stage_changed)

## Get appropriate health for the object set
func _get_health_for_set(object_set: String) -> float:
    var set_config = {}
    if DamageManager:
        var damage_manager = DamageManager
        set_config = damage_manager.get_set_config(object_set)
    
    if set_config.has("health_range"):
        var health_range = set_config.health_range
        var min_health = health_range.get("min", 50.0)
        var max_health = health_range.get("max", 100.0)
        return randf_range(min_health, max_health)
    
    # Default health
    return 100.0

## Find the MAIN building mesh (prefer largest mesh, avoid roofs/details)
func _find_building_mesh() -> MeshInstance3D:
    var parent = get_parent()
    if not parent:
        return null

    var candidate_meshes: Array[MeshInstance3D] = []

    # Collect all MeshInstance3D children
    for child in parent.get_children():
        if child is MeshInstance3D and child.is_inside_tree():
            # Skip meshes that are clearly secondary (roof, trim, etc.)
            if "Roof" in child.name or "Trim" in child.name or "Detail" in child.name:
                continue
            candidate_meshes.append(child)

        # Recursively search children
        if child.is_inside_tree():
            for grandchild in child.get_children():
                if grandchild is MeshInstance3D and grandchild.is_inside_tree():
                    if "Roof" in grandchild.name or "Trim" in grandchild.name:
                        continue
                    candidate_meshes.append(grandchild)

    if candidate_meshes.is_empty():
        return null

    # Return the mesh with largest AABB (main building, not details)
    var largest_mesh: MeshInstance3D = candidate_meshes[0]
    var largest_volume = _calculate_mesh_volume(largest_mesh)

    for mesh in candidate_meshes:
        var volume = _calculate_mesh_volume(mesh)
        if volume > largest_volume:
            largest_volume = volume
            largest_mesh = mesh

    print("🏗️ Found main building mesh: %s (volume: %.1f)" % [largest_mesh.name, largest_volume])
    return largest_mesh

## Helper: Calculate mesh bounding volume
func _calculate_mesh_volume(mesh: MeshInstance3D) -> float:
    if not mesh.mesh:
        return 0.0
    var aabb = mesh.get_aabb()
    return aabb.size.x * aabb.size.y * aabb.size.z

## Get the building's ORIGINAL material (from surface or override)
## For trees: material is on material_override. For buildings: on surface.
func _get_original_building_material() -> StandardMaterial3D:
    if not building_mesh:
        return null

    # For trees: material is set via material_override
    if building_mesh.material_override and building_mesh.material_override is StandardMaterial3D:
        return building_mesh.material_override as StandardMaterial3D

    # For buildings: material is on the mesh surface
    if building_mesh.mesh and building_mesh.mesh.get_surface_count() > 0:
        var surface_mat = building_mesh.mesh.surface_get_material(0)
        if surface_mat and surface_mat is StandardMaterial3D:
            return surface_mat as StandardMaterial3D

    return null

## Apply damaged effects
func _apply_damaged_effects() -> void:
    print("🔧 _apply_damaged_effects CALLED for: %s (in_tree: %s, has_mesh: %s)" % [
        get_parent().name if get_parent() else "?", is_inside_tree(), building_mesh != null
    ])

    if not is_inside_tree() or not building_mesh:
        print("⚠️ EARLY RETURN: Not in tree or no mesh")
        return

    # Get ORIGINAL material from surface (not override)
    var original_material: StandardMaterial3D = _get_original_building_material()

    if not original_material:
        print("⚠️ Cannot find material for building damage effects on: %s" % get_parent().name)
        return

    # DUPLICATE the original material to avoid modifying shared resources
    var damaged_material = original_material.duplicate() as StandardMaterial3D

    # Get original color
    var original_color = damaged_material.albedo_color

    # DRAMATIC darkening: 50% of ORIGINAL (not compounding)
    damaged_material.albedo_color = Color(
        original_color.r * 0.5,
        original_color.g * 0.5,
        original_color.b * 0.5,
        original_color.a
    )

    # Apply the modified material
    building_mesh.material_override = damaged_material

    print("💥 DAMAGE EFFECT: Darkened '%s' to 50%% brightness (from %.2f,%.2f,%.2f)" % [get_parent().name, original_color.r, original_color.g, original_color.b])

## Apply ruined effects
func _apply_ruined_effects() -> void:
    print("🔧 _apply_ruined_effects CALLED for: %s (in_tree: %s, has_mesh: %s)" % [
        get_parent().name if get_parent() else "?", is_inside_tree(), building_mesh != null
    ])

    if not is_inside_tree() or not building_mesh:
        print("⚠️ EARLY RETURN: Not in tree or no mesh")
        return

    # Get ORIGINAL material from surface (not override)
    var original_material: StandardMaterial3D = _get_original_building_material()
    if not original_material:
        return

    var ruined_material = original_material.duplicate() as StandardMaterial3D

    # VERY DRAMATIC darkening: 70% of ORIGINAL (not compounding)
    var original_color = ruined_material.albedo_color
    ruined_material.albedo_color = Color(
        original_color.r * 0.3,
        original_color.g * 0.3,
        original_color.b * 0.3,
        original_color.a
    )

    # INTENSE fire/damage glow
    ruined_material.emission_enabled = true
    ruined_material.emission = Color(1.0, 0.5, 0.0)  # Bright orange
    ruined_material.emission_energy = 2.0  # Double intensity

    building_mesh.material_override = ruined_material

    # Add smoke particles (much more visible)
    _spawn_heavy_smoke()

    print("🔥 RUINED EFFECT: Building heavily damaged with fire! (from %.2f,%.2f,%.2f)" % [original_color.r, original_color.g, original_color.b])

## Apply destroyed effects
func _apply_destroyed_effects() -> void:
    print("🔧 _apply_destroyed_effects CALLED for: %s (in_tree: %s)" % [
        get_parent().name if get_parent() else "?", is_inside_tree()
    ])

    if not is_inside_tree():
        print("⚠️ EARLY RETURN: Not in tree")
        return

    # Generate debris FIRST (before geometry changes)
    _generate_building_debris()

    var building_node = get_parent()
    print("🏚️ Building node: %s, mesh: %s" % [building_node != null, building_mesh != null])

    # Trees and buildings have different destruction behavior
    if _is_tree():
        # TREES: Hide the mesh, remove collision, leave debris visible
        if building_node:
            # Immediately hide all mesh children (trunk and leaves)
            for child in building_node.get_children():
                if child is MeshInstance3D:
                    child.visible = false

            # Remove collision body so it can't be hit anymore
            if CollisionManager:
                CollisionManager.remove_collision_from_object(building_node)

            print("🌲 TREE DESTROYED: Mesh hidden, collision removed, debris remains visible")
    else:
        # BUILDINGS: Shrink to rubble (foundation-sized)
        if building_node and building_mesh:
            # Create rubble effect: shrink to 30% height, darken completely
            var tween = create_tween()

            # Collapse animation: shrink height over 1 second
            var original_scale = building_node.scale
            var original_pos = building_node.position
            var collapsed_scale = Vector3(original_scale.x, original_scale.y * 0.3, original_scale.z)
            print("📏 COLLAPSE: Scaling from %s to %s" % [original_scale, collapsed_scale])
            print("📏 COLLAPSE: Lowering Y from %.1f to %.1f" % [original_pos.y, original_pos.y - 3.0])

            tween.tween_property(building_node, "scale", collapsed_scale, 1.0)

            # Lower position to ground level
            tween.parallel().tween_property(building_node, "position:y", building_node.position.y - 3.0, 1.0)

            # Material: VERY dark (almost black) with intense fire
            var original_material = _get_original_building_material()
            if original_material:
                var destroyed_mat = original_material.duplicate()
                destroyed_mat.albedo_color = Color(0.1, 0.1, 0.12)  # Nearly black
                destroyed_mat.emission_enabled = true
                destroyed_mat.emission = Color(1.0, 0.6, 0.2)  # Bright fire
                destroyed_mat.emission_energy = 3.0  # Very intense
                building_mesh.material_override = destroyed_mat

            print("💥 BUILDING DESTROYED: Collapsed to rubble!")

    # Explosion and effects for both trees and buildings
    _spawn_destruction_explosion()

    # Heavy smoke/fire
    _spawn_heavy_smoke()
    _spawn_fire_particles()

## Spawn heavy, visible smoke (not subtle)
func _spawn_heavy_smoke() -> void:
    if get_parent().has_node("HeavySmoke"):
        return  # Already smoking

    var smoke = GPUParticles3D.new()
    smoke.name = "HeavySmoke"
    smoke.position = Vector3(0, 5.0, 0)  # High above building
    smoke.amount = 50  # Lots of particles (was 15)
    smoke.lifetime = 3.0  # Long-lasting (was 2.0)
    smoke.explosiveness = 0.3
    smoke.randomness = 0.5

    # Make smoke LARGE and VISIBLE
    var process_mat = ParticleProcessMaterial.new()
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    process_mat.emission_sphere_radius = 3.0
    process_mat.direction = Vector3(0, 1, 0)  # Rise upward
    process_mat.gravity = Vector3(0, -1, 0)  # Slight downward (heavy smoke)
    process_mat.initial_velocity_min = 2.0
    process_mat.initial_velocity_max = 5.0
    process_mat.scale_min = 2.0  # Large particles
    process_mat.scale_max = 4.0
    smoke.process_material = process_mat

    get_parent().add_child(smoke)
    smoke.emitting = true

    print("💨 Heavy smoke spawned on: %s" % get_parent().name)

## Spawn fire particles (for destroyed buildings)
func _spawn_fire_particles() -> void:
    if get_parent().has_node("FireEffect"):
        return

    var fire = GPUParticles3D.new()
    fire.name = "FireEffect"
    fire.position = Vector3(0, 2.0, 0)
    fire.amount = 30
    fire.lifetime = 1.5
    fire.explosiveness = 0.5

    # Orange/red fire particles
    var process_mat = ParticleProcessMaterial.new()
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    process_mat.emission_box_extents = Vector3(2, 1, 2)
    process_mat.direction = Vector3(0, 1, 0)
    process_mat.initial_velocity_min = 3.0
    process_mat.initial_velocity_max = 6.0
    process_mat.scale_min = 1.0
    process_mat.scale_max = 2.0
    fire.process_material = process_mat

    get_parent().add_child(fire)
    fire.emitting = true

## Spawn destruction explosion effect
func _spawn_destruction_explosion() -> void:
    # Create a massive one-shot explosion
    var explosion = GPUParticles3D.new()
    explosion.name = "DestructionExplosion"
    explosion.position = Vector3(0, 3.0, 0)
    explosion.amount = 30  # Reduced from 100 for less particle spam
    explosion.lifetime = 0.5
    explosion.one_shot = true
    explosion.explosiveness = 1.0

    # Explosive burst in all directions
    var process_mat = ParticleProcessMaterial.new()
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    process_mat.emission_sphere_radius = 1.0
    process_mat.direction = Vector3(0, 1, 0)
    process_mat.spread = 180.0  # All directions
    process_mat.initial_velocity_min = 10.0
    process_mat.initial_velocity_max = 20.0
    process_mat.gravity = Vector3(0, -9.8, 0)
    process_mat.scale_min = 0.5
    process_mat.scale_max = 2.0
    process_mat.color = Color(1.0, 0.7, 0.3)  # Bright orange
    process_mat.damping_min = 2.0
    process_mat.damping_max = 5.0
    explosion.process_material = process_mat

    get_parent().add_child(explosion)
    explosion.emitting = true

    # Remove after explosion finishes
    get_tree().create_timer(2.0).timeout.connect(
        func():
            if is_instance_valid(explosion):
                explosion.queue_free()
    , CONNECT_ONE_SHOT)

## Called when the building is destroyed
func _on_destroyed() -> void:
    # Apply destruction effects
    _apply_destroyed_effects()

    # Notify DamageManager
    if DamageManager:
        var damage_manager = DamageManager
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
    if not DamageManager:
        return

    var damage_manager = DamageManager
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

    # Use parent's position (the actual tree/building node) not self (the damageable component)
    var parent = get_parent()
    if not parent or not parent.is_inside_tree():
        return

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

    # Add to scene FIRST (so global_position works)
    # CRITICAL: Add to parent's PARENT (scene root), not tree itself, so debris persists when tree is hidden
    var scene_root = parent.get_parent() if parent else null
    if scene_root and scene_root.is_inside_tree():
        scene_root.add_child(debris)
    else:
        get_tree().root.add_child(debris)

    # NOW set position (after debris is in scene tree)
    debris.global_position = parent.global_position + Vector3(x_offset, y_offset, z_offset)

    # Apply explosive impulse from building center + upward component
    var direction_from_center = (debris.global_position - parent.global_position).normalized()
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
    