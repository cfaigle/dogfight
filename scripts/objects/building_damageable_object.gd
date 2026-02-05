## Building-specific damageable object
## Extends the base damageable object with building-specific functionality

class_name BuildingDamageableObject
extends BaseDamageableObject

## Building type (used to determine appropriate object set)
var building_type: String = "generic"

## Reference to the building's mesh
var building_mesh: MeshInstance3D = null

## Red Square special effects tracking
var _is_red_square: bool = false
var _red_square_fire_particles: Array[GPUParticles3D] = []
var _red_square_smoke_particles: Array[GPUParticles3D] = []
var _red_square_lights: Array[OmniLight3D] = []

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

    # Detect if this is Red Square (special fire/smoke effects)
    if building_type == "red_square":
        _is_red_square = true
        print("🏛️ RED SQUARE DETECTED: Special Moskva-style fire/smoke effects will be applied")

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
        "red_square": "Industrial",
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
        "windmill": "Coastal",  # Often residential style
        "radio_tower": "Industrial",  # 150-300 HP instead of 80-150
        "grain_silo": "Residential",  # 150-300 HP instead of 80-150
        "corn_feeder": "Residential",  # 150-300 HP instead of 80-150
        "lighthouse": "Natural",  # 150-300 HP instead of 80-150
        "tower": "Industrial",
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

## Helper: Apply darkening to ALL mesh instances in a node tree
func _apply_darkening_to_all_meshes(node: Node, brightness_multiplier: float) -> void:
    if node is MeshInstance3D:
        var mesh_inst = node as MeshInstance3D
        # Get the ORIGINAL material for this specific mesh (from surface, not override)
        var original_mat: BaseMaterial3D = null
        if mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
            var surf_mat = mesh_inst.mesh.surface_get_material(0)
            if surf_mat and surf_mat is BaseMaterial3D:
                original_mat = surf_mat as BaseMaterial3D

        if original_mat:
            var darkened_mat = original_mat.duplicate()
            var original_color = darkened_mat.albedo_color
            darkened_mat.albedo_color = Color(
                original_color.r * brightness_multiplier,
                original_color.g * brightness_multiplier,
                original_color.b * brightness_multiplier,
                original_color.a
            )
            mesh_inst.material_override = darkened_mat
            print("🎨 Darkened mesh '%s' to %.0f%% brightness (from %.2f,%.2f,%.2f to %.2f,%.2f,%.2f)" % [
                mesh_inst.name, brightness_multiplier * 100,
                original_color.r, original_color.g, original_color.b,
                darkened_mat.albedo_color.r, darkened_mat.albedo_color.g, darkened_mat.albedo_color.b
            ])
        else:
            print("⚠️ Could not find material for mesh: %s" % mesh_inst.name)

    # Recurse to children
    for child in node.get_children():
        _apply_darkening_to_all_meshes(child, brightness_multiplier)

## Helper: Apply material color to ALL mesh instances in a node tree
func _apply_material_to_all_meshes(node: Node, target_color: Color) -> void:
    if node is MeshInstance3D:
        var mesh_inst = node as MeshInstance3D
        # Get the ORIGINAL material for this specific mesh (from surface, not override)
        var original_mat: BaseMaterial3D = null
        if mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
            var surf_mat = mesh_inst.mesh.surface_get_material(0)
            if surf_mat and surf_mat is BaseMaterial3D:
                original_mat = surf_mat as BaseMaterial3D

        if original_mat:
            var destroyed_mat = original_mat.duplicate()
            destroyed_mat.albedo_color = target_color
            destroyed_mat.emission_enabled = false  # Changed CTF
            destroyed_mat.emission = Color(1.0, 0.6, 0.2)  # Bright fire
            destroyed_mat.emission_energy_multiplier = 3.0  # Very intense
            mesh_inst.material_override = destroyed_mat
            print("🎨 Applied destroyed material to mesh: %s (color: %s)" % [mesh_inst.name, target_color])
        else:
            print("⚠️ Could not find material for mesh: %s" % mesh_inst.name)

    # Recurse to children
    for child in node.get_children():
        _apply_material_to_all_meshes(child, target_color)

## Get the building's ORIGINAL material (from surface or override)
## For trees: material is on material_override. For buildings: on surface.
func _get_original_building_material() -> BaseMaterial3D:
    if not building_mesh:
        print("⚠️ _get_original_building_material: No building_mesh!")
        return null

    # For trees: material is set via material_override
    if building_mesh.material_override and building_mesh.material_override is BaseMaterial3D:
        print("✓ Found material via material_override: %s" % building_mesh.material_override.get_class())
        return building_mesh.material_override as BaseMaterial3D

    # For buildings: material is on the mesh surface
    if building_mesh.mesh and building_mesh.mesh.get_surface_count() > 0:
        var surface_mat = building_mesh.mesh.surface_get_material(0)
        if surface_mat and surface_mat is BaseMaterial3D:
            print("✓ Found material via surface 0: %s (color: %s)" % [surface_mat.get_class(), surface_mat.albedo_color])
            return surface_mat as BaseMaterial3D
        else:
            print("⚠️ Surface 0 material not found or wrong type: %s" % (surface_mat.get_class() if surface_mat else "null"))

    print("⚠️ _get_original_building_material: Could not find material!")
    return null

## Apply damaged effects
func _apply_damaged_effects() -> void:
    print("🔧 _apply_damaged_effects CALLED for: %s (in_tree: %s, has_mesh: %s)" % [
        get_parent().name if get_parent() else "?", is_inside_tree(), building_mesh != null
    ])

    if not is_inside_tree():
        print("⚠️ EARLY RETURN: Not in tree")
        return

    var building_node = get_parent()
    if not building_node:
        return

    # Apply 50% darkening to ALL meshes
    _apply_darkening_to_all_meshes(building_node, 0.5)

    # Add antenna sparks for towers
    if "tower" in building_type.to_lower():
        _spawn_antenna_sparks()

    print("💥 DAMAGE EFFECT: Darkened '%s' to 50%% brightness" % building_node.name)

## Apply ruined effects
func _apply_ruined_effects() -> void:
    print("🔧 _apply_ruined_effects CALLED for: %s (in_tree: %s, has_mesh: %s)" % [
        get_parent().name if get_parent() else "?", is_inside_tree(), building_mesh != null
    ])

    if not is_inside_tree():
        print("⚠️ EARLY RETURN: Not in tree")
        return

    var building_node = get_parent()
    if not building_node:
        return

    # Apply 30% brightness (70% darkening) to ALL meshes
    _apply_darkening_to_all_meshes(building_node, 0.3)

    # Red Square gets Moskva-style effects, others get standard
    if _is_red_square:
        _apply_red_square_ruined_effects()
    else:
        _spawn_heavy_smoke()

    print("🔥 RUINED EFFECT: Building heavily damaged with fire!")

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

    # Special case: Red Square destruction triggers Ukrainian flag
    if building_type == "red_square" and building_node:
        print("🇺🇦 RED SQUARE DESTROYED! Emitting GameEvents signal...")
        GameEvents.red_square_destroyed.emit(building_node.global_position)

    # Intensify Red Square fire/smoke if already damaged
    if _is_red_square and building_node:
        _apply_red_square_destroyed_effects()

    # Trees, towers, and buildings have different destruction behavior
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
    elif "tower" in building_type.to_lower():
        # TOWERS: Tilting/toppling animation instead of shrinking
        if building_node and building_mesh:
            # Remove collision
            if CollisionManager:
                CollisionManager.remove_collision_from_object(building_node)

            # Dramatic toppling tween
            var tween = create_tween()
            var tilt_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
            var tilt_angle = deg_to_rad(90)  # Fall to ground

            # Tilt over 2 seconds with ease-in (accelerating fall)
            tween.tween_property(building_node, "rotation",
                Vector3(tilt_direction.x * tilt_angle, 0, tilt_direction.z * tilt_angle),
                2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

            # Fade out during fall
            tween.parallel().tween_method(_apply_fade_to_all_meshes.bind(building_node), 1.0, 0.0, 2.0)

            # Darken material (crushed metal)
            _apply_material_to_all_meshes(building_node, Color(0.15, 0.15, 0.18))

            print("📡 TOWER DESTROYED: Toppling!")
    else:
        # BUILDINGS: Shrink to rubble (foundation-sized) and REMOVE COLLISION
        if building_node and building_mesh:
            # Remove collision body so it can't be hit anymore
            if CollisionManager:
                CollisionManager.remove_collision_from_object(building_node)

                # ALSO check for manually-created collision (like Red Square)
                if building_node.has_meta("manual_collision_body"):
                    var manual_collision = building_node.get_meta("manual_collision_body")
                    if is_instance_valid(manual_collision) and manual_collision.get_parent():
                        manual_collision.get_parent().remove_child(manual_collision)
                        manual_collision.queue_free()
                        print("🔨 MANUAL COLLISION REMOVED from building")

                print("🔨 COLLISION REMOVED from building")

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

            # Material: VERY dark (almost black) with intense fire - APPLY TO ALL MESHES
            _apply_material_to_all_meshes(building_node, Color(0.1, 0.1, 0.12))

            print("💥 BUILDING DESTROYED: Collapsed to rubble!")

    # Different effects for trees vs buildings
    if _is_tree():
        _spawn_tree_destruction_effects()
    elif _is_red_square:
        # Red Square already has Moskva-style effects, just add explosion
        _spawn_destruction_explosion()
    else:
        # Standard buildings get basic effects
        _spawn_destruction_explosion()
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

    # Auto-cleanup after 10 seconds to prevent infinite smoke
    get_tree().create_timer(10.0).timeout.connect(
        func(): if is_instance_valid(smoke): smoke.queue_free(),
        CONNECT_ONE_SHOT
    )

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

    # Auto-cleanup after 8 seconds to prevent infinite fire
    get_tree().create_timer(8.0).timeout.connect(
        func(): if is_instance_valid(fire): fire.queue_free(),
        CONNECT_ONE_SHOT
    )

## Spawn reduced effects for tree destruction (much lighter than buildings)
func _spawn_tree_destruction_effects() -> void:
    # Small explosion burst (10 particles instead of 30)
    var explosion = GPUParticles3D.new()
    explosion.name = "SmallExplosion"
    explosion.position = Vector3(0, 3.0, 0)
    explosion.amount = 10  # Reduced from 30
    explosion.lifetime = 0.5
    explosion.one_shot = true
    explosion.explosiveness = 0.95

    var explosion_mat = ParticleProcessMaterial.new()
    explosion_mat.direction = Vector3(0, 1, 0)
    explosion_mat.spread = 180.0
    explosion_mat.initial_velocity_min = 8.0
    explosion_mat.initial_velocity_max = 16.0
    explosion_mat.gravity = Vector3(0, -15.0, 0)
    explosion_mat.scale_min = 2.0
    explosion_mat.scale_max = 5.0

    var explosion_mesh = SphereMesh.new()
    explosion_mesh.radial_segments = 4
    explosion_mesh.rings = 4
    explosion_mesh.radius = 0.3
    explosion_mesh.height = 0.6
    var explosion_sm = StandardMaterial3D.new()
    explosion_sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    explosion_sm.albedo_color = Color(0.8, 0.6, 0.3, 1.0)
    explosion_mesh.material = explosion_sm
    explosion.draw_pass_1 = explosion_mesh
    explosion.process_material = explosion_mat

    get_parent().add_child(explosion)
    explosion.emitting = true
    get_tree().create_timer(0.6).timeout.connect(func(): if is_instance_valid(explosion): explosion.queue_free())

    # Light smoke for trees (10 particles, 0.8s instead of 50 particles, 3.0s)
    var smoke = GPUParticles3D.new()
    smoke.name = "LightSmoke"
    smoke.position = Vector3(0, 3.0, 0)
    smoke.amount = 10  # Reduced from 50
    smoke.lifetime = 0.8  # Reduced from 3.0
    smoke.explosiveness = 0.4
    smoke.randomness = 0.5

    var smoke_mat = ParticleProcessMaterial.new()
    smoke_mat.direction = Vector3(0, 1, 0)
    smoke_mat.spread = 50.0
    smoke_mat.initial_velocity_min = 1.5
    smoke_mat.initial_velocity_max = 4.0
    smoke_mat.gravity = Vector3(0, 2.0, 0)  # Rising smoke
    smoke_mat.scale_min = 2.0
    smoke_mat.scale_max = 5.0

    var smoke_mesh = SphereMesh.new()
    smoke_mesh.radial_segments = 6
    smoke_mesh.rings = 6
    smoke_mesh.radius = 1.0
    var smoke_sm = StandardMaterial3D.new()
    smoke_sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    smoke_sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    smoke_sm.albedo_color = Color(0.3, 0.3, 0.3, 0.4)
    smoke_mesh.material = smoke_sm
    smoke.draw_pass_1 = smoke_mesh
    smoke.process_material = smoke_mat

    get_parent().add_child(smoke)
    smoke.emitting = true
    get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(smoke): smoke.queue_free())

    # Small fire effect (8 particles, 0.6s instead of 30 particles, 1.5s)
    var fire = GPUParticles3D.new()
    fire.name = "SmallFire"
    fire.position = Vector3(0, 2.0, 0)
    fire.amount = 8  # Reduced from 30
    fire.lifetime = 0.6  # Reduced from 1.5
    fire.one_shot = true
    fire.explosiveness = 0.8

    var fire_mat = ParticleProcessMaterial.new()
    fire_mat.direction = Vector3(0, 1, 0)
    fire_mat.spread = 45.0
    fire_mat.initial_velocity_min = 2.0
    fire_mat.initial_velocity_max = 5.0
    fire_mat.gravity = Vector3(0, 3.0, 0)
    fire_mat.scale_min = 1.0
    fire_mat.scale_max = 2.5

    var fire_mesh = SphereMesh.new()
    fire_mesh.radial_segments = 4
    fire_mesh.rings = 4
    fire_mesh.radius = 0.4
    var fire_sm = StandardMaterial3D.new()
    fire_sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    fire_sm.albedo_color = Color(1.0, 0.5, 0.1, 1.0)
    fire_mesh.material = fire_sm
    fire.draw_pass_1 = fire_mesh
    fire.process_material = fire_mat

    get_parent().add_child(fire)
    fire.emitting = true
    get_tree().create_timer(0.8).timeout.connect(func(): if is_instance_valid(fire): fire.queue_free())

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

    # Fade out at 2s, remove at 3s using CONNECT_ONE_SHOT to prevent memory leaks
    get_tree().create_timer(2.0).timeout.connect(
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

    get_tree().create_timer(3.0).timeout.connect(
        func():
            if is_instance_valid(debris):
                debris.queue_free()
    , CONNECT_ONE_SHOT)

## Helper: Apply fade to all mesh instances in a node tree
func _apply_fade_to_all_meshes(fade_value: float, node: Node) -> void:
    if node is MeshInstance3D:
        var mesh_inst = node as MeshInstance3D
        var mat = mesh_inst.material_override
        if not mat and mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
            mat = mesh_inst.mesh.surface_get_material(0)
        if mat and mat is BaseMaterial3D:
            var faded_mat = mat.duplicate()
            faded_mat.albedo_color.a = fade_value
            mesh_inst.material_override = faded_mat

    # Recurse to children
    for child in node.get_children():
        _apply_fade_to_all_meshes(fade_value, child)

## Spawn antenna sparks for damaged radio towers
func _spawn_antenna_sparks() -> void:
    var building_node = get_parent()
    if not building_node:
        return

    # Get tower height from metadata (set during mesh creation)
    var tower_height = 40.0
    if building_mesh and building_mesh.mesh and building_mesh.mesh.has_meta("tower_height"):
        tower_height = building_mesh.mesh.get_meta("tower_height")

    var sparks = GPUParticles3D.new()
    sparks.name = "AntennaSparks"
    sparks.position = Vector3(0, tower_height, 0)  # At antenna level
    sparks.amount = 20
    sparks.lifetime = 0.3
    sparks.explosiveness = 0.8

    var spark_mat = ParticleProcessMaterial.new()
    spark_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    spark_mat.emission_box_extents = Vector3(2, 0.5, 2)
    spark_mat.direction = Vector3(0, -1, 0)
    spark_mat.spread = 45.0
    spark_mat.initial_velocity_min = 5.0
    spark_mat.initial_velocity_max = 10.0
    spark_mat.gravity = Vector3(0, -15, 0)
    spark_mat.scale_min = 0.1
    spark_mat.scale_max = 0.3
    sparks.process_material = spark_mat

    building_node.add_child(sparks)
    sparks.emitting = true

    # Auto-cleanup
    get_tree().create_timer(2.0).timeout.connect(
        func(): if is_instance_valid(sparks): sparks.queue_free()
    , CONNECT_ONE_SHOT)

## Spawn Red Square fire emitter (Moskva-style with gradients and lights)
func _spawn_red_square_fire_emitter(position: Vector3, scale_range: Vector2) -> GPUParticles3D:
    var fire = GPUParticles3D.new()
    fire.amount = 50  # Base amount (Moskva uses 63, but Red Square is smaller)
    fire.lifetime = 2.5
    fire.one_shot = false
    fire.explosiveness = 0.3

    var process_mat = ParticleProcessMaterial.new()
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    process_mat.emission_box_extents = Vector3(10.0, 8.0, 10.0)  # Slightly smaller than Moskva
    process_mat.direction = Vector3(0, 1, 0)
    process_mat.spread = 30.0
    process_mat.initial_velocity_min = 8.0
    process_mat.initial_velocity_max = 15.0
    process_mat.gravity = Vector3(0, 1.5, 0)  # CRITICAL: Upward gravity for rising flames
    process_mat.scale_min = scale_range.x
    process_mat.scale_max = scale_range.y

    # Orange-red fire gradient (4-point gradient like Moskva)
    var gradient = Gradient.new()
    gradient.add_point(0.0, Color(1.0, 0.7, 0.2, 1.0))   # Bright orange start
    gradient.add_point(0.3, Color(1.0, 0.4, 0.1, 0.9))   # Orange-red
    gradient.add_point(0.7, Color(0.8, 0.2, 0.0, 0.4))   # Dark red
    gradient.add_point(1.0, Color(0.3, 0.1, 0.0, 0.0))   # Fade to black

    var gradient_texture = GradientTexture1D.new()
    gradient_texture.gradient = gradient
    process_mat.color_ramp = gradient_texture

    fire.process_material = process_mat
    fire.draw_pass_1 = SphereMesh.new()  # Simple sphere mesh for particles

    get_parent().add_child(fire)
    fire.global_position = position
    fire.emitting = true

    _red_square_fire_particles.append(fire)
    return fire


## Spawn Red Square smoke emitter (Moskva-style with gradients)
func _spawn_red_square_smoke_emitter(position: Vector3, scale_range: Vector2) -> GPUParticles3D:
    var smoke = GPUParticles3D.new()
    smoke.amount = 160  # More than standard (Moskva uses 160, but Red Square is smaller)
    smoke.lifetime = 1.0  # Long-lasting like Moskva
    smoke.one_shot = false
    smoke.explosiveness = 0.08  # Very low for natural drift
    smoke.randomness = 0.8

    var process_mat = ParticleProcessMaterial.new()
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    process_mat.emission_sphere_radius = 25.0  # Large emission area
    process_mat.direction = Vector3(0, 1, 0)
    process_mat.spread = 35.0
    process_mat.initial_velocity_min = 5.0
    process_mat.initial_velocity_max = 10.0
    process_mat.gravity = Vector3(0, -0.3, 0)  # CRITICAL: Negative gravity for upward float
    process_mat.scale_min = scale_range.x
    process_mat.scale_max = scale_range.y

    # Dark grey-to-black smoke gradient (4-point like Moskva)
    var gradient = Gradient.new()
    gradient.add_point(0.0, Color(0.3, 0.3, 0.3, 0.8))   # Medium grey
    gradient.add_point(0.3, Color(0.2, 0.2, 0.2, 0.9))   # Dark grey
    gradient.add_point(0.7, Color(0.15, 0.15, 0.15, 0.5)) # Very dark
    gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))   # Fade to transparent

    var gradient_texture = GradientTexture1D.new()
    gradient_texture.gradient = gradient
    process_mat.color_ramp = gradient_texture

    smoke.process_material = process_mat
    smoke.draw_pass_1 = SphereMesh.new()

    get_parent().add_child(smoke)
    smoke.global_position = position
    smoke.emitting = true

    _red_square_smoke_particles.append(smoke)
    return smoke


## Cleanup Red Square effects
func _cleanup_red_square_effects():
    for fire in _red_square_fire_particles:
        if is_instance_valid(fire):
            fire.emitting = false
            fire.queue_free()
    for smoke in _red_square_smoke_particles:
        if is_instance_valid(smoke):
            smoke.emitting = false
            smoke.queue_free()
    for light in _red_square_lights:
        if is_instance_valid(light):
            light.queue_free()

    _red_square_fire_particles.clear()
    _red_square_smoke_particles.clear()
    _red_square_lights.clear()


## Apply Red Square specific ruined effects (Stage 2: Initial fire/smoke)
func _apply_red_square_ruined_effects():
    var building_node = get_parent()
    if not building_node:
        return
    
    # Cleanup existing effects to prevent accumulation
    _cleanup_red_square_effects()

    # Get mesh size from metadata (set during building construction)
    var mesh_size: Vector3 = building_node.get_meta("mesh_size", Vector3(200, 165, 563))
    var building_pos = building_node.global_position

    print("🔥 RED SQUARE RUINED: Spawning Moskva-style fire/smoke effects...")
    print("   Mesh size: %s, Position: %s" % [mesh_size, building_pos])

    # Calculate fire positions (5 strategic points across the building)
    # Red Square is LONG (563 in Z), so distribute along length
    var fire_positions = [
        building_pos + Vector3(0, mesh_size.y * 0.4, mesh_size.z * 0.3),      # Front section, elevated
        building_pos + Vector3(0, mesh_size.y * 0.4, -mesh_size.z * 0.3),     # Rear section, elevated
        building_pos + Vector3(mesh_size.x * 0.25, mesh_size.y * 0.5, 0),     # Right side, high
        building_pos + Vector3(-mesh_size.x * 0.25, mesh_size.y * 0.5, 0),    # Left side, high
        building_pos + Vector3(0, mesh_size.y * 0.6, 0)                       # Center top
    ]

    # Spawn fire emitters with lights
    for fire_pos in fire_positions:
        var fire = _spawn_red_square_fire_emitter(fire_pos, Vector2(10.0, 20.0))

        # Add OmniLight3D at fire position
        var light = OmniLight3D.new()
        light.light_color = Color(1.0, 0.5, 0.2)  # Orange fire glow
        light.light_energy = 20.0
        light.omni_range = 100.0
        light.omni_attenuation = 2.0

        get_parent().add_child(light)
        light.global_position = fire_pos
        _red_square_lights.append(light)

    # Calculate smoke positions (2 main plumes)
    var smoke_positions = [
        building_pos + Vector3(0, mesh_size.y * 0.5, mesh_size.z * 0.2),   # Front plume
        building_pos + Vector3(0, mesh_size.y * 0.5, -mesh_size.z * 0.2)   # Rear plume
    ]

    # Spawn smoke emitters
    for smoke_pos in smoke_positions:
        _spawn_red_square_smoke_emitter(smoke_pos, Vector2(30.0, 60.0))

    # Apply material glow (orange emission like Moskva)
    _apply_material_to_all_meshes(building_node, Color(0.3, 0.3, 0.35))

    # Add emission to all meshes
    for child in building_node.get_children():
        if child is MeshInstance3D:
            var mesh_inst = child as MeshInstance3D
            if mesh_inst.material_override and mesh_inst.material_override is StandardMaterial3D:
                var mat = mesh_inst.material_override as StandardMaterial3D
                mat.emission_enabled = true
                mat.emission = Color(1.0, 0.4, 0.1)  # Orange glow
                mat.emission_energy_multiplier = 2.0

    print("🔥 RED SQUARE: Spawned %d fire emitters, %d smoke emitters, %d lights" %
          [fire_positions.size(), smoke_positions.size(), _red_square_lights.size()])


## Apply Red Square specific destroyed effects (Stage 3: Massive fire/smoke)
func _apply_red_square_destroyed_effects():
    var building_node = get_parent()
    if not building_node:
        return

    # CRITICAL: Clean up Stage 2 effects before adding Stage 3 effects
    _cleanup_red_square_effects()

    var mesh_size: Vector3 = building_node.get_meta("mesh_size", Vector3(200, 165, 563))
    var building_pos = building_node.global_position

    print("💥 RED SQUARE DESTROYED: Intensifying fire/smoke effects...")

    # Add 3 more INTENSE fire emitters at new positions
    var additional_fire_positions = [
        building_pos + Vector3(mesh_size.x * 0.15, mesh_size.y * 0.55, mesh_size.z * 0.15),  # Corner 1
        building_pos + Vector3(-mesh_size.x * 0.15, mesh_size.y * 0.55, mesh_size.z * 0.15), # Corner 2
        building_pos + Vector3(0, mesh_size.y * 0.45, -mesh_size.z * 0.15)                   # Rear mid
    ]

    for fire_pos in additional_fire_positions:
        var fire = _spawn_red_square_fire_emitter(fire_pos, Vector2(15.0, 30.0))  # LARGER flames

        # BRIGHTER lights for destroyed state
        var light = OmniLight3D.new()
        light.light_color = Color(1.0, 0.5, 0.2)
        light.light_energy = 50.0  # Much brighter
        light.omni_range = 150.0   # Wider range
        light.omni_attenuation = 2.0

        get_parent().add_child(light)
        light.global_position = fire_pos
        _red_square_lights.append(light)

    # Add ONE MASSIVE central smoke plume
    var central_smoke_pos = building_pos + Vector3(0, mesh_size.y * 0.6, 0)

    var massive_smoke = GPUParticles3D.new()
    massive_smoke.amount = 200  # MASSIVE particle count
    massive_smoke.lifetime = 8.0  # Very long-lasting
    massive_smoke.one_shot = false
    massive_smoke.explosiveness = 0.05
    massive_smoke.randomness = 0.5

    var process_mat = ParticleProcessMaterial.new()
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    process_mat.emission_sphere_radius = 35.0  # HUGE emission area
    process_mat.direction = Vector3(0, 1, 0)
    process_mat.spread = 40.0
    process_mat.initial_velocity_min = 7.0
    process_mat.initial_velocity_max = 14.0
    process_mat.gravity = Vector3(0, -0.4, 0)  # Stronger upward float
    process_mat.scale_min = 50.0  # MASSIVE smoke clouds
    process_mat.scale_max = 100.0

    # Same gradient as smaller smoke
    var gradient = Gradient.new()
    gradient.add_point(0.0, Color(0.3, 0.3, 0.3, 0.8))
    gradient.add_point(0.3, Color(0.2, 0.2, 0.2, 0.9))
    gradient.add_point(0.7, Color(0.15, 0.15, 0.15, 0.5))
    gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))

    var gradient_texture = GradientTexture1D.new()
    gradient_texture.gradient = gradient
    process_mat.color_ramp = gradient_texture

    massive_smoke.process_material = process_mat
    massive_smoke.draw_pass_1 = SphereMesh.new()

    get_parent().add_child(massive_smoke)
    massive_smoke.global_position = central_smoke_pos
    massive_smoke.emitting = true
    _red_square_smoke_particles.append(massive_smoke)

    # Intensify emission glow
    for child in building_node.get_children():
        if child is MeshInstance3D:
            var mesh_inst = child as MeshInstance3D
            if mesh_inst.material_override and mesh_inst.material_override is StandardMaterial3D:
                var mat = mesh_inst.material_override as StandardMaterial3D
                mat.emission_energy_multiplier = 3.0  # Even brighter

    print("💥 RED SQUARE DESTROYED: Added %d more fires + massive smoke plume" % additional_fire_positions.size())
