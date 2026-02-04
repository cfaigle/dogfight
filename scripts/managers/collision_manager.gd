## Collision Manager Singleton
## Manages physics collisions for environmental objects like trees and buildings

extends Node

## Configuration for collision properties
var collision_config: CollisionConfig = null

func _init():
    # Load the default configuration
    var config_resource = load("res://resources/configs/collision_config.tres")
    if config_resource and config_resource is CollisionConfig:
        collision_config = config_resource
    else:
        # Create a default configuration if resource doesn't exist
        collision_config = CollisionConfig.new()

## Pool of collision shapes to reduce allocation
var collision_shape_pool: Dictionary = {
    "box": [],
    "sphere": [],
    "capsule": []
}

## Spatial partitioning grid for optimizing collision management
var spatial_grid: Dictionary = {}
var grid_cell_size: float = 50.0  # Size of each grid cell in world units

## Maximum number of shapes to keep in pool for each type
const MAX_POOL_SIZE: int = 100

## Track active collision objects
var active_collisions: Dictionary = {}

## Signal emitted when a collision is added
signal collision_added(object)

## Signal emitted when a collision is removed
signal collision_removed(object)

func _ready() -> void:
    # The singleton is registered via the project settings, not here
    print("CollisionManager initialized - distance_threshold: %.0fm" % collision_config.distance_threshold)

## Enable or disable the collision system
func set_collision_enabled(enabled: bool) -> void:
    collision_config.enabled = enabled

## Add collision to an object based on its type
func add_collision_to_object(object, object_type: String) -> void:
    # Debug tree and boat collision creation
    var is_tree = "Tree" in object.name if object is Node else false
    var is_boat = object_type == "boat" if object is Node else false

    if is_tree or is_boat:
        print("🔧 ADD_COLLISION called: name='%s', type='%s', instance_id=%d" % [
            object.name, object_type, object.get_instance_id()
        ])

    if not collision_config.enabled:
        if is_tree:
            print("⚠️ COLLISION BLOCKED: collision_config.enabled = false")
        return

    if not collision_config.object_types.has(object_type):
        print("⚠️ COLLISION BLOCKED: Unknown object type '%s'" % object_type)
        return

    if not collision_config.is_type_enabled(object_type):
        if is_tree:
            print("⚠️ COLLISION BLOCKED: object type '%s' is not enabled" % object_type)
        return

    # Create appropriate collision shape based on object type
    var shape_type = collision_config.get_shape_type(object_type)
    var scale_factor = collision_config.get_scale_factor(object_type)

    # Debug tree collision shape creation
    if is_tree:
        print("🔨 Creating collision body: shape='%s', scale=%.2f" % [shape_type, scale_factor])

    var collision_body = _create_collision_body(object, shape_type, scale_factor)

    if is_tree:
        print("🔨 Collision body created: %s (Valid: %s)" % [
            collision_body.name if collision_body else "null",
            collision_body != null
        ])

    if collision_body:
        active_collisions[object.get_instance_id()] = collision_body
        _add_object_to_grid(object, object.global_position)
        collision_added.emit(object)
        if "Tree" in object.name and active_collisions.size() <= 10:  # Debug first 10 tree collisions
            print("🎯 DEBUG: Added collision to '%s' (Total active: %d, Distance threshold: %.1fm)" % [object.name, active_collisions.size(), collision_config.distance_threshold])

## Add collisions to multiple objects in a batch
func add_collisions_batch(objects_data: Array) -> void:
    # objects_data should be an array of dictionaries with "object" and "type" keys
    for obj_data in objects_data:
        if obj_data.has("object") and obj_data.has("type"):
            add_collision_to_object(obj_data.object, obj_data.type)

## Add collisions to all objects in a scene root that match criteria
func add_collisions_for_scene(scene_root: Node, object_types_filter: Array = []) -> void:
    var objects_to_add = []
    _collect_objects_recursive(scene_root, objects_to_add, object_types_filter)

    # Add collisions in batch for better performance
    add_collisions_batch(objects_to_add)

## Collect objects recursively for batch processing
func _collect_objects_recursive(node: Node, result_array: Array, object_types_filter: Array) -> void:
    # Check if this node is a potential collision object
    if _is_potential_collision_object(node):
        var object_type = _get_object_type_from_name(node.name)

        # If filter is empty, add all types, otherwise only add matching types
        if object_types_filter.is_empty() or object_types_filter.has(object_type):
            result_array.append({
                "object": node,
                "type": object_type
            })

    # Recursively check all children
    for child in node.get_children():
        _collect_objects_recursive(child, result_array, object_types_filter)

## Remove collision from an object
func remove_collision_from_object(object) -> void:
    var object_id = object.get_instance_id()
    if active_collisions.has(object_id):
        if "Tree" in object.name:  # Debug tree collision removal
            print("⚠️ COLLISION REMOVED: '%s' (Total remaining: %d)" % [object.name, active_collisions.size() - 1])
        var collision_body = active_collisions[object_id]
        if collision_body.get_parent():
            collision_body.get_parent().remove_child(collision_body)
        collision_body.queue_free()
        active_collisions.erase(object_id)
        _remove_object_from_grid(object, object.global_position)
        collision_removed.emit(object)

## Create compound collision for trees (trunk + leaves boxes)
func _create_tree_collision_body(tree_object: Node3D) -> StaticBody3D:
    # Find trunk and leaves meshes
    var trunk_mesh: MeshInstance3D = null
    var leaves_mesh: MeshInstance3D = null

    for child in tree_object.get_children():
        if child is MeshInstance3D:
            if "Trunk" in child.name:
                trunk_mesh = child
            elif "Leaves" in child.name:
                leaves_mesh = child

    if not trunk_mesh or not leaves_mesh:
        print("⚠️ Tree collision: Could not find trunk/leaves meshes for '%s', using fallback" % tree_object.name)
        return null

    # Create StaticBody3D
    var static_body = StaticBody3D.new()
    static_body.name = tree_object.name + "_Collision"
    static_body.set_meta("damage_target", tree_object)
    static_body.collision_layer = 1
    static_body.collision_mask = 1

    # Create trunk collision box
    var trunk_shape = CollisionShape3D.new()
    var trunk_box = BoxShape3D.new()
    # Trunk dimensions (from prop_generator.gd:1022-1025)
    # CylinderMesh: top_radius=0.6, bottom_radius=1.0, height=12.0
    # Use average radius for box width
    trunk_box.size = Vector3(1.6, 12.0, 1.6)  # Width based on bottom radius * 2, height 12
    trunk_shape.shape = trunk_box
    trunk_shape.position = trunk_mesh.position  # (0, 6, 0)
    static_body.add_child(trunk_shape)

    # Create leaves collision box
    var leaves_shape = CollisionShape3D.new()
    var leaves_box = BoxShape3D.new()
    # Leaves dimensions (from prop_generator.gd:1039-1042)
    # Cone: top_radius=0, bottom_radius=3.5, height=10.0
    leaves_box.size = Vector3(7.0, 10.0, 7.0)  # Width = bottom_radius * 2, height 10
    leaves_shape.shape = leaves_box
    leaves_shape.position = leaves_mesh.position  # (0, 17, 0)
    static_body.add_child(leaves_shape)

    # Position at tree's location
    static_body.global_transform = tree_object.global_transform

    # Add to scene
    var parent = tree_object.get_parent()
    if parent:
        parent.add_child(static_body)
        static_body.owner = parent
    else:
        var root = tree_object.get_tree().root
        root.add_child(static_body)
        static_body.owner = root

    print("🌲 Created compound tree collision for '%s': trunk box (1.6x12x1.6) + leaves box (7x10x7)" % tree_object.name)

    return static_body

## Create a collision body for an object
func _create_collision_body(object, shape_type: String, scale_factor: float = 1.0) -> StaticBody3D:
    if not object or not is_instance_valid(object):
        return null

    # SPECIAL CASE: Trees get compound collision (trunk + leaves boxes)
    if "Tree" in object.name:
        return _create_tree_collision_body(object)

    # SPECIAL CASE: Radio towers get tapered cylinder collision
    if object.has_meta("tower_height"):
        var cylinder_shape = CylinderShape3D.new()
        cylinder_shape.height = object.get_meta("tower_height", 40.0)
        cylinder_shape.radius = object.get_meta("tower_base_width", 4.0) * 0.5

        var static_body = StaticBody3D.new()
        static_body.name = object.name + "_Collision"
        static_body.set_meta("damage_target", object)
        static_body.collision_layer = 1
        static_body.collision_mask = 1

        var collision_shape = CollisionShape3D.new()
        collision_shape.shape = cylinder_shape
        collision_shape.position.y = cylinder_shape.height * 0.5  # Center at mid-height
        static_body.add_child(collision_shape)

        static_body.global_transform = object.global_transform

        var parent = object.get_parent()
        if parent:
            parent.add_child(static_body)
            static_body.owner = parent
        else:
            var root = object.get_tree().root
            root.add_child(static_body)
            static_body.owner = root

        print("📡 Created cylindrical collision for radio tower '%s': height=%.1f, radius=%.1f" % [
            object.name, cylinder_shape.height, cylinder_shape.radius
        ])

        return static_body

    # Debug boat collision creation
    if "Boat" in object.name:
        print("🔨 Creating collision body for boat '%s'" % object.name)
        print("  - Shape: %s, Scale: %.2f" % [shape_type, scale_factor])
    else:
        print("🔨 Creating collision body for non-boat '%s'" % object.name)
        print("  - Shape: %s, Scale: %.2f" % [shape_type, scale_factor])

    # Create a StaticBody3D for the collision
    var static_body = StaticBody3D.new()
    static_body.name = object.name + "_Collision"

    # CRITICAL: Link collision body back to the original object for damage application
    static_body.set_meta("damage_target", object)

    # Debug: Verify metadata was set correctly
    if "Tree" in object.name or "Boat" in object.name:
        var verify_meta = static_body.get_meta("damage_target")
        print("🔗 DEBUG: Set metadata on '%s' -> Target: '%s' (Valid: %s)" % [
            static_body.name,
            verify_meta.name if verify_meta else "null",
            is_instance_valid(verify_meta)
        ])

    # Add explicit collision layer assignment
    static_body.collision_layer = 1  # Environment layer
    static_body.collision_mask = 1   # Match layer
    
    # Create appropriate collision shape
    var collision_shape = _get_collision_shape_from_pool(shape_type)
    if not collision_shape:
        # If pool is empty, create a new shape
        collision_shape = _create_collision_shape(shape_type)
    
    if collision_shape:
        var collision_node = CollisionShape3D.new()
        collision_node.shape = collision_shape
        static_body.add_child(collision_node)
        collision_node.owner = static_body
        
        # Position the collision body at the same location as the object
        static_body.global_transform = object.global_transform

        # Scale the collision shape based on the object's scale and scale factor
        var object_scale = object.scale
        var final_scale: Vector3

        # For boats, use mesh_size metadata if available for accurate collision
        if "Boat" in object.name and object.has_meta("mesh_size"):
            var mesh_size = object.get_meta("mesh_size")
            if mesh_size is Vector3:
                # Use actual boat dimensions with slight padding (0.9x for forgiving hitbox)
                final_scale = mesh_size * 0.9
                if "Boat" in object.name:
                    print("  - Using mesh_size for boat collision: %s" % final_scale)
            else:
                # Fallback to scale_factor method
                final_scale = object_scale * scale_factor
        else:
            # Standard scaling for non-boat objects
            final_scale = Vector3(
                object_scale.x * scale_factor,
                object_scale.y * scale_factor,
                object_scale.z * scale_factor
            )

        collision_node.scale = final_scale
        
        # Add the collision body to the scene
        var parent = object.get_parent()
        if parent:
            parent.add_child(static_body)
            static_body.owner = parent

            # Debug boat collision
            if "Boat" in object.name:
                print("  - Added to parent: %s" % parent.name)
                print("  - Is in tree: %s" % static_body.is_inside_tree())
                print("  - Collision layers: %d, mask: %d" % [static_body.collision_layer, static_body.collision_mask])
        else:
            # If no parent, add to the root
            var root = object.get_tree().root
            root.add_child(static_body)
            static_body.owner = root

            if "Boat" in object.name:
                print("  - Added to root (no parent)")

        return static_body
    
    return null

## Get a collision shape from the pool or create a new one
func _get_collision_shape_from_pool(shape_type: String) -> Shape3D:
    if collision_shape_pool.has(shape_type) and collision_shape_pool[shape_type].size() > 0:
        return collision_shape_pool[shape_type].pop_back()
    
    return null

## Return a collision shape to the pool
func _return_collision_shape_to_pool(shape: Shape3D, shape_type: String) -> void:
    if collision_shape_pool.has(shape_type):
        if collision_shape_pool[shape_type].size() < MAX_POOL_SIZE:
            # Reset shape properties before returning to pool
            _reset_shape_properties(shape, shape_type)
            collision_shape_pool[shape_type].append(shape)

## Reset shape properties before pooling
func _reset_shape_properties(shape: Shape3D, shape_type: String) -> void:
    # Reset any custom properties that might have been set
    match shape_type:
        "box":
            if shape is BoxShape3D:
                shape.size = Vector3(1.0, 1.0, 1.0)
        "sphere":
            if shape is SphereShape3D:
                shape.radius = 0.5
        "capsule":
            if shape is CapsuleShape3D:
                shape.radius = 0.5
                shape.height = 1.0

## Create a new collision shape
func _create_collision_shape(shape_type: String) -> Shape3D:
    match shape_type:
        "box":
            var box_shape = BoxShape3D.new()
            box_shape.size = Vector3(1.0, 1.0, 1.0)
            return box_shape
        "sphere":
            var sphere_shape = SphereShape3D.new()
            sphere_shape.radius = 0.5
            return sphere_shape
        "capsule":
            var capsule_shape = CapsuleShape3D.new()
            capsule_shape.radius = 0.5
            capsule_shape.height = 1.0
            return capsule_shape
        _:
            print("Warning: Unknown shape type '%s'" % shape_type)
            return null

## Update collision based on distance from player with LOD system
func update_collision_for_distance(object, player_position: Vector3) -> void:
    if not object or not is_instance_valid(object):
        return

    var object_id = object.get_instance_id()
    var distance = (object.global_position - player_position).length()

    # Determine LOD level based on distance
    var lod_level = _get_lod_level(distance)

    # Determine if collision should be active based on distance
    if distance > collision_config.distance_threshold:
        # Too far, remove collision
        if active_collisions.has(object_id):
            remove_collision_from_object(object)
    else:
        # Within range, ensure collision is active based on LOD
        if not active_collisions.has(object_id):
            # Need to determine object type to add collision
            # This would need to be stored with the object
            var object_type = _get_object_type_from_name(object.name)
            if object_type:
                # Check if this object type should have collision based on density
                var density = collision_config.get_density(object_type)
                if randf() <= density:
                    # Apply LOD-appropriate collision based on distance
                    _apply_lod_collision(object, object_type, lod_level)

## Determine LOD level based on distance
func _get_lod_level(distance: float) -> String:
    var lod_distances = collision_config.lod_distances
    if distance <= lod_distances.near:
        return "near"
    elif distance <= lod_distances.mid:
        return "mid"
    else:
        return "far"

## Apply LOD-appropriate collision
func _apply_lod_collision(object, object_type: String, lod_level: String) -> void:
    # Adjust collision properties based on LOD level
    var adjusted_config = collision_config.get_object_type_config(object_type).duplicate()

    # Modify properties based on LOD level
    match lod_level:
        "near":
            # Full detail collision
            add_collision_to_object(object, object_type)
        "mid":
            # Simplified collision - maybe use a simpler shape or reduced scale
            var shape_type = collision_config.get_shape_type(object_type)
            var scale_factor = collision_config.get_scale_factor(object_type) * 0.8  # Slightly smaller
            _add_collision_with_custom_properties(object, shape_type, scale_factor)
        "far":
            # Minimal collision - possibly skip some objects or use very simplified shapes
            var density_factor = 0.5  # Only apply collision to 50% of objects at this distance
            if randf() <= density_factor:
                var shape_type = collision_config.get_shape_type(object_type)
                var scale_factor = collision_config.get_scale_factor(object_type) * 0.6  # Much smaller
                _add_collision_with_custom_properties(object, shape_type, scale_factor)

## Add collision with custom properties (for LOD adjustments)
func _add_collision_with_custom_properties(object, shape_type: String, scale_factor: float) -> void:
    if not collision_config.enabled:
        return

    var collision_body = _create_collision_body(object, shape_type, scale_factor)
    if collision_body:
        active_collisions[object.get_instance_id()] = collision_body
        collision_added.emit(object)

## Update all collisions based on player position with distance-based activation
func update_all_collisions_for_player_new(player_position: Vector3) -> void:
    # This would iterate through all managed objects and update their collision state
    # based on distance to player
    var root = get_tree().root
    _update_collisions_recursive(root, player_position)

## Recursive function to update collisions for all objects in the scene
func _update_collisions_recursive(node: Node, player_position: Vector3) -> void:
    # Check if this node is a potential candidate for collision
    if _is_potential_collision_object(node):
        update_collision_for_distance(node, player_position)

    # Recursively check all children
    for child in node.get_children():
        _update_collisions_recursive(child, player_position)

## Check if a node is a potential collision object
func _is_potential_collision_object(node) -> bool:
    # Check if the node has a mesh and is not already a StaticBody3D
    if node is MeshInstance3D:
        # Check if it's not already a collision body
        var parent = node.get_parent()
        return not (parent is StaticBody3D)

    # Check if it's a named object that might be a building/tree
    if node is Node3D and node.name != "":
        var lower_name = node.name.to_lower()
        for object_type in collision_config.object_types:
            if lower_name.contains(object_type):
                return true

    return false

## Get object type from its name
func _get_object_type_from_name(name: String) -> String:
    name = name.to_lower()

    for object_type in collision_config.object_types:
        if name.contains(object_type):
            return object_type

    # Default to decoration if no match found
    return "decoration"

## Check if an object has a specific flag
func has_object_flag(object, flag: String) -> bool:
    var object_type = _get_object_type_from_name(object.name)
    return collision_config.has_flag(object_type, flag)

## Get all flags for an object
func get_object_flags(object) -> Array:
    var object_type = _get_object_type_from_name(object.name)
    return collision_config.get_flags(object_type)

## Enable collisions for objects with a specific flag
func enable_collisions_for_flag(flag: String) -> void:
    # Update configuration to enable objects with this flag
    var updated_types = {}
    for object_type in collision_config.object_types:
        var config = collision_config.get_object_type_config(object_type)
        var flags = config.get("flags", [])
        if flags.has(flag):
            updated_types[object_type] = config.duplicate()
            updated_types[object_type]["enabled"] = true

    for object_type in updated_types:
        collision_config.update_object_type_config(object_type, updated_types[object_type])

## Disable collisions for objects with a specific flag
func disable_collisions_for_flag(flag: String) -> void:
    # Update configuration to disable objects with this flag
    var updated_types = {}
    for object_type in collision_config.object_types:
        var config = collision_config.get_object_type_config(object_type)
        var flags = config.get("flags", [])
        if flags.has(flag):
            updated_types[object_type] = config.duplicate()
            updated_types[object_type]["enabled"] = false

    for object_type in updated_types:
        collision_config.update_object_type_config(object_type, updated_types[object_type])

## Toggle collisions for objects with a specific flag
func toggle_collisions_for_flag(flag: String) -> void:
    # Count how many object types have this flag currently enabled
    var enabled_count = 0
    var total_count = 0
    var updated_types = {}

    for object_type in collision_config.object_types:
        var config = collision_config.get_object_type_config(object_type)
        var flags = config.get("flags", [])
        if flags.has(flag):
            total_count += 1
            if config.get("enabled", false):
                enabled_count += 1
            updated_types[object_type] = config.duplicate()

    # If more than half are enabled, disable them all, otherwise enable them all
    var should_enable = enabled_count < (total_count / 2.0)

    for object_type in updated_types:
        updated_types[object_type]["enabled"] = should_enable
        collision_config.update_object_type_config(object_type, updated_types[object_type])

## Get all objects with a specific flag in the scene
func get_objects_with_flag(scene_root: Node, flag: String) -> Array:
    var objects_with_flag = []
    _find_objects_with_flag_recursive(scene_root, flag, objects_with_flag)
    return objects_with_flag

## Recursive function to find all objects with a specific flag
func _find_objects_with_flag_recursive(node: Node, flag: String, result_array: Array) -> void:
    # Check if this node has the flag
    if _is_potential_collision_object(node) and has_object_flag(node, flag):
        result_array.append(node)

    # Recursively check all children
    for child in node.get_children():
        _find_objects_with_flag_recursive(child, flag, result_array)

## Get current configuration
func get_config():
    return collision_config

## Update configuration
func update_config(new_config: Dictionary) -> void:
    # Update the properties of the collision_config object with values from the dictionary
    if collision_config:
        for key in new_config:
            if collision_config.has_method("set_" + str(key)):
                collision_config.call("set_" + str(key), new_config[key])
            elif collision_config.has_signal(str(key)):
                continue  # Skip signals
            else:
                # For direct property access
                collision_config.set(str(key), new_config[key])

## Get count of active collisions
func get_active_collision_count() -> int:
    return active_collisions.size()

## Get grid cell coordinates for a position
func _get_grid_cell_coords(position: Vector3) -> Vector3i:
    var x = int(floor(position.x / grid_cell_size))
    var y = int(floor(position.y / grid_cell_size))
    var z = int(floor(position.z / grid_cell_size))
    return Vector3i(x, y, z)

## Add an object to the spatial grid
func _add_object_to_grid(object, position: Vector3) -> void:
    var cell_coords = _get_grid_cell_coords(position)
    var cell_key = str(cell_coords)

    if not spatial_grid.has(cell_key):
        spatial_grid[cell_key] = []

    spatial_grid[cell_key].append(object)

## Remove an object from the spatial grid
func _remove_object_from_grid(object, position: Vector3) -> void:
    var cell_coords = _get_grid_cell_coords(position)
    var cell_key = str(cell_coords)

    if spatial_grid.has(cell_key):
        spatial_grid[cell_key].erase(object)

## Get nearby objects in the spatial grid
func _get_nearby_objects(position: Vector3, radius: float) -> Array:
    var objects = []
    var cells_x = int(ceil(radius / grid_cell_size))
    var cells_y = int(ceil(radius / grid_cell_size))
    var cells_z = int(ceil(radius / grid_cell_size))

    for x in range(-cells_x, cells_x + 1):
        for y in range(-cells_y, cells_y + 1):
            for z in range(-cells_z, cells_z + 1):
                var cell_coords = _get_grid_cell_coords(position) + Vector3i(x, y, z)
                var cell_key = str(cell_coords)

                if spatial_grid.has(cell_key):
                    for obj in spatial_grid[cell_key]:
                        if not objects.has(obj):
                            objects.append(obj)

    return objects

## Performance monitoring variables
var performance_stats: Dictionary = {
    "last_update_time": 0.0,
    "collision_operations_count": 0,
    "active_collisions_peak": 0,
    "frame_time_ms": 0.0
}

## Record performance statistics
func record_performance_stat(operation: String, time_taken: float) -> void:
    performance_stats.last_update_time = Time.get_ticks_msec()
    performance_stats.collision_operations_count += 1

    # Update peak active collisions
    var current_count = active_collisions.size()
    if current_count > performance_stats.active_collisions_peak:
        performance_stats.active_collisions_peak = current_count

    performance_stats.frame_time_ms = time_taken

## Get performance statistics
func get_performance_stats() -> Dictionary:
    return performance_stats.duplicate()

## Reset performance statistics
func reset_performance_stats() -> void:
    performance_stats = {
        "last_update_time": 0.0,
        "collision_operations_count": 0,
        "active_collisions_peak": 0,
        "frame_time_ms": 0.0
    }

## Toggle options for the collision system
func set_global_collision_enabled(enabled: bool) -> void:
    collision_config.enabled = enabled
    # Update all active collisions based on new setting
    if not enabled:
        cleanup_all_collisions()

## Toggle collision activation based on object type
func set_collision_type_enabled(object_type: String, enabled: bool) -> void:
    if collision_config.object_types.has(object_type):
        var current_config = collision_config.get_object_type_config(object_type).duplicate()
        current_config["enabled"] = enabled
        collision_config.update_object_type_config(object_type, current_config)

## Toggle distance-based collision activation
func set_distance_based_activation_enabled(enabled: bool) -> void:
    # This would enable/disable the distance-based activation system
    # For now, we'll just store this setting
    if not collision_config.has("distance_activation_enabled"):
        collision_config.set_meta("distance_activation_enabled", enabled)
    else:
        collision_config.set_meta("distance_activation_enabled", enabled)

## Get the current state of distance-based activation
func is_distance_based_activation_enabled() -> bool:
    if collision_config.has_meta("distance_activation_enabled"):
        return collision_config.get_meta("distance_activation_enabled")
    return true  # Default to enabled

## Toggle LOD-based collision activation
func set_lod_based_activation_enabled(enabled: bool) -> void:
    if not collision_config.has("lod_activation_enabled"):
        collision_config.set_meta("lod_activation_enabled", enabled)
    else:
        collision_config.set_meta("lod_activation_enabled", enabled)

## Get the current state of LOD-based activation
func is_lod_based_activation_enabled() -> bool:
    if collision_config.has_meta("lod_activation_enabled"):
        return collision_config.get_meta("lod_activation_enabled")
    return true  # Default to enabled

## Set the distance threshold for collision activation
func set_distance_threshold(new_threshold: float) -> void:
    collision_config.distance_threshold = new_threshold

## Get the current distance threshold
func get_distance_threshold() -> float:
    return collision_config.distance_threshold

## Toggle collision system with performance considerations
func toggle_collision_system(performance_mode: String = "balanced") -> void:
    # Different performance modes:
    # "high_detail" - Full collisions with all features
    # "balanced" - Moderate collisions with some optimizations
    # "performance" - Minimal collisions for better performance
    match performance_mode:
        "high_detail":
            collision_config.enabled = true
            set_distance_based_activation_enabled(true)
            set_lod_based_activation_enabled(true)
            # Reset to default values
            collision_config.distance_threshold = 200.0
        "balanced":
            collision_config.enabled = true
            set_distance_based_activation_enabled(true)
            set_lod_based_activation_enabled(true)
            # Moderate distance threshold
            collision_config.distance_threshold = 150.0
        "performance":
            collision_config.enabled = true
            set_distance_based_activation_enabled(true)
            set_lod_based_activation_enabled(true)
            # Reduced distance threshold for better performance
            collision_config.distance_threshold = 100.0
        "disabled":
            collision_config.enabled = false
            cleanup_all_collisions()

## Clean up all collisions
func cleanup_all_collisions() -> void:
    for object_id in active_collisions:
        var collision_body = active_collisions[object_id]
        if collision_body and is_instance_valid(collision_body):
            if collision_body.get_parent():
                collision_body.get_parent().remove_child(collision_body)
            collision_body.queue_free()

    active_collisions.clear()

    # Clear spatial grid as well
    spatial_grid.clear()

## Debug visualization system (F5)
var debug_visualization_enabled: bool = false
var debug_visualization_meshes: Dictionary = {}  # collision_id -> MeshInstance3D
var debug_material: StandardMaterial3D = null

## Toggle collision visualization
func toggle_collision_visualization(enabled: bool) -> void:
    debug_visualization_enabled = enabled

    if enabled:
        _create_debug_visualization()
    else:
        _hide_debug_visualization()

## Create debug visualization meshes for all active collisions
func _create_debug_visualization() -> void:
    if not debug_material:
        debug_material = StandardMaterial3D.new()
        debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        debug_material.albedo_color = Color(0.0, 1.0, 1.0, 0.5)
        debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED

    # First, visualize all CollisionManager-tracked collisions
    for instance_id in active_collisions:
        var collision_body = active_collisions[instance_id]
        if not is_instance_valid(collision_body):
            continue

        _create_debug_mesh_for_collision(collision_body, instance_id)

    # ALSO find manually-created collision bodies (like Red Square) by scanning scene tree
    var root = get_tree().root
    if root:
        _find_and_visualize_manual_collisions(root)

## Create debug mesh for a single collision body
func _create_debug_mesh_for_collision(collision_body: StaticBody3D, collision_id: int) -> void:
    # Handle collision bodies with MULTIPLE collision shapes (e.g., trees with trunk + leaves)
    var collision_shapes: Array = []
    for child in collision_body.get_children():
        if child is CollisionShape3D:
            collision_shapes.append(child)

    if collision_shapes.is_empty():
        return

    # Create debug meshes for ALL collision shapes in this body
    var debug_meshes: Array = []
    for collision_shape in collision_shapes:
        if not collision_shape.shape:
            continue

        var debug_mesh_inst = MeshInstance3D.new()
        var mesh = null

        if collision_shape.shape is BoxShape3D:
            var box_shape = collision_shape.shape as BoxShape3D
            mesh = BoxMesh.new()
            mesh.size = box_shape.size
        elif collision_shape.shape is SphereShape3D:
            var sphere_shape = collision_shape.shape as SphereShape3D
            mesh = SphereMesh.new()
            mesh.radius = sphere_shape.radius
            mesh.height = sphere_shape.radius * 2.0
        elif collision_shape.shape is CapsuleShape3D:
            var capsule_shape = collision_shape.shape as CapsuleShape3D
            mesh = CapsuleMesh.new()
            mesh.radius = capsule_shape.radius
            mesh.height = capsule_shape.height
        elif collision_shape.shape is CylinderShape3D:
            var cylinder_shape = collision_shape.shape as CylinderShape3D
            mesh = CylinderMesh.new()
            mesh.top_radius = cylinder_shape.radius
            mesh.bottom_radius = cylinder_shape.radius
            mesh.height = cylinder_shape.height
        else:
            continue

        debug_mesh_inst.mesh = mesh
        debug_mesh_inst.material_override = debug_material
        debug_mesh_inst.add_to_group("DebugVisualization")

        debug_mesh_inst.global_transform = collision_shape.global_transform
        debug_mesh_inst.scale = collision_shape.scale

        if collision_body.get_parent():
            collision_body.get_parent().add_child(debug_mesh_inst)
            debug_meshes.append(debug_mesh_inst)

    # Store all debug meshes for this collision (use array if multiple shapes)
    if debug_meshes.size() > 0:
        debug_visualization_meshes[collision_id] = debug_meshes if debug_meshes.size() > 1 else debug_meshes[0]

## Recursively find manually-created StaticBody3D collision objects
func _find_and_visualize_manual_collisions(node: Node) -> void:
    if node is StaticBody3D:
        var collision_body = node as StaticBody3D
        var instance_id = collision_body.get_instance_id()

        # Skip if already visualized (tracked in active_collisions)
        if not active_collisions.has(instance_id):
            # This is a manual collision body
            if not debug_visualization_meshes.has(instance_id):
                print("Found manual collision body: %s" % collision_body.name)
                _create_debug_mesh_for_collision(collision_body, instance_id)

    # Recurse to children
    for child in node.get_children():
        _find_and_visualize_manual_collisions(child)

## Hide and cleanup debug visualization
func _hide_debug_visualization() -> void:
    for instance_id in debug_visualization_meshes:
        var mesh_data = debug_visualization_meshes[instance_id]
        # Handle both single meshes and arrays (for compound collision like trees)
        if mesh_data is Array:
            for mesh_inst in mesh_data:
                if is_instance_valid(mesh_inst):
                    mesh_inst.queue_free()
        elif is_instance_valid(mesh_data):
            mesh_data.queue_free()
    debug_visualization_meshes.clear()