## System for modifying object geometry during destruction
## Handles removing parts, adding holes, collapsing sections, and breaking into pieces

class_name GeometryModificationSystem
extends RefCounted

## Apply geometry changes to an object based on its destruction stage and set
func apply_geometry_changes(object, stage: int, object_set: String, geometry_config: Dictionary) -> void:
    # Apply changes based on the configuration
    if geometry_config.get("remove_parts", false):
        _remove_parts(object, stage)
    
    if geometry_config.get("add_holes", false):
        _add_holes(object, stage)
    
    if geometry_config.get("collapse_sections", false):
        _collapse_sections(object, stage)
    
    if geometry_config.get("break_into_pieces", false):
        _break_into_pieces(object, stage, geometry_config)

## Remove parts of the object's geometry
func _remove_parts(object, stage: int) -> void:
    # This function would remove parts of the object's mesh
    # depending on the destruction stage
    var mesh_instance = _get_mesh_instance(object)
    if mesh_instance:
        # In a full implementation, this would:
        # - Identify parts to remove based on the mesh structure
        # - Remove specific sub-meshes or sections
        # - Update the mesh to reflect the changes
        
        # For now, we'll simulate this with material changes to hide parts
        _hide_parts_by_material(mesh_instance, stage)

## Add holes to the object's geometry
func _add_holes(object, stage: int) -> void:
    # This function would add holes to the object's mesh
    # depending on the destruction stage
    var mesh_instance = _get_mesh_instance(object)
    if mesh_instance:
        # In a full implementation, this would:
        # - Use boolean operations or mesh manipulation to create holes
        # - Place holes at strategic locations based on damage
        # - Update UVs and normals appropriately
        
        # For now, we'll simulate this with texture changes
        _add_damage_textures(mesh_instance, stage)

## Collapse sections of the object
func _collapse_sections(object, stage: int) -> void:
    # This function would collapse structural sections of the object
    # depending on the destruction stage
    var mesh_instance = _get_mesh_instance(object)
    if mesh_instance:
        # In a full implementation, this would:
        # - Manipulate vertex positions to simulate structural failure
        # - Apply transformations to specific parts of the mesh
        # - Potentially split the mesh into separate pieces
        
        # For now, we'll simulate this with transformations
        _apply_collapse_transformations(mesh_instance, stage)

## Break the object into pieces
func _break_into_pieces(object, stage: int, geometry_config: Dictionary) -> void:
    if stage < 2:  # Only break into pieces at ruined or destroyed stage
        return
    
    # Get debris configuration
    var debris_enabled = geometry_config.get("debris_enabled", true)
    if not debris_enabled:
        return
    
    var count_range = geometry_config.get("debris_count_range", {"min": 1, "max": 5})
    var size_range = geometry_config.get("debris_size_range", {"min": 0.5, "max": 2.0})
    
    # Create debris pieces
    var debris_count = randi() % (int(count_range.get("max", 5)) - int(count_range.get("min", 1)) + 1) + int(count_range.get("min", 1))
    _create_debris_pieces(object, debris_count, size_range)

## Hide parts of the mesh by changing materials
func _hide_parts_by_material(mesh_instance: MeshInstance3D, stage: int) -> void:
    # Simulate removing parts by making them transparent
    var material = mesh_instance.material_override
    if not material:
        material = mesh_instance.mesh.surface_get_material(0) if mesh_instance.mesh else null
    
    if material and material is BaseMaterial3D:
        # Adjust transparency based on destruction stage
        var transparency = 0.0
        match stage:
            1:  # Damaged
                transparency = 0.2
            2:  # Ruined
                transparency = 0.5
            3:  # Destroyed
                transparency = 0.8
        
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.albedo_color = Color(material.albedo_color.r, material.albedo_color.g, material.albedo_color.b, 1.0 - transparency)

## Add damage textures to simulate holes
func _add_damage_textures(mesh_instance: MeshInstance3D, stage: int) -> void:
    # In a full implementation, this would add textures with hole patterns
    # For now, we'll just change the material to indicate damage
    var material = mesh_instance.material_override
    if not material:
        material = mesh_instance.mesh.surface_get_material(0) if mesh_instance.mesh else null
    
    if material and material is BaseMaterial3D:
        # Add a damage overlay texture or modify the material
        # This would typically involve using a texture with transparency
        # or a shader that simulates holes
        pass

## Apply collapse transformations to the mesh
func _apply_collapse_transformations(mesh_instance: MeshInstance3D, stage: int) -> void:
    # Apply transformations to simulate structural collapse
    # This would manipulate vertices or apply transforms to parts of the object
    match stage:
        2:  # Ruined
            # Apply slight deformation
            mesh_instance.scale = Vector3(0.98, 0.95, 0.98)
        3:  # Destroyed
            # Apply more significant deformation
            mesh_instance.scale = Vector3(0.9, 0.85, 0.9)
            mesh_instance.rotation = Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1))

## Create debris pieces from the object
func _create_debris_pieces(object, count: int, size_range: Dictionary) -> void:
    var original_mesh = _get_mesh_instance(object)
    if not original_mesh:
        return
    
    # Get the original object's transform
    var original_transform = object.global_transform
    
    # Create debris pieces
    for i in range(count):
        # Create a new mesh instance for the debris
        var debris_mesh = MeshInstance3D.new()
        debris_mesh.mesh = original_mesh.mesh.duplicate() if original_mesh.mesh else null
        
        # Apply a random scale within the range
        var min_size = size_range.get("min", 0.5)
        var max_size = size_range.get("max", 2.0)
        var scale_factor = randf_range(min_size, max_size)
        debris_mesh.scale = Vector3.ONE * scale_factor * 0.3  # Make pieces smaller than original
        
        # Position debris randomly around the original location
        var position_offset = Vector3(
            randf_range(-2.0, 2.0),
            randf_range(0.0, 3.0),
            randf_range(-2.0, 2.0)
        )
        debris_mesh.global_position = object.global_position + position_offset
        
        # Add physics to the debris
        _add_physics_to_debris(debris_mesh)
        
        # Add to the scene
        var parent = object.get_parent()
        if parent:
            parent.add_child(debris_mesh)
        else:
            var root = object.get_tree().root
            root.add_child(debris_mesh)
        
        # Apply random rotation
        debris_mesh.rotation = Vector3(
            randf_range(0, TAU),
            randf_range(0, TAU),
            randf_range(0, TAU)
        )
        
        # Apply physics impulse to make debris fly
        _apply_initial_impulse(debris_mesh)

## Add physics to debris object
func _add_physics_to_debris(debris_mesh: MeshInstance3D) -> void:
    # Add a RigidBody3D as parent to handle physics for the debris
    var rigid_body = RigidBody3D.new()
    rigid_body.mass = 1.0
    rigid_body.linear_damp = 0.1
    rigid_body.angular_damp = 0.1
    
    # Add collision shape
    var collision_shape = CollisionShape3D.new()
    var box_shape = BoxShape3D.new()
    box_shape.size = debris_mesh.mesh.get_aabb().size
    collision_shape.shape = box_shape
    
    rigid_body.add_child(collision_shape)
    rigid_body.global_position = debris_mesh.global_position
    
    # Replace the mesh instance with the rigid body in the scene
    var parent = debris_mesh.get_parent()
    if parent:
        parent.remove_child(debris_mesh)
        parent.remove_child(rigid_body)
        parent.add_child(rigid_body)
        rigid_body.add_child(debris_mesh)
    
    # Add auto-removal after some time
    var timer = Timer.new()
    timer.wait_time = 3.0
    timer.one_shot = true
    timer.timeout.connect(func(): 
        if is_instance_valid(rigid_body):
            rigid_body.queue_free()
    )
    rigid_body.add_child(timer)
    timer.start()

## Apply initial impulse to debris
func _apply_initial_impulse(debris_mesh: MeshInstance3D) -> void:
    # Find the rigid body parent
    var parent = debris_mesh.get_parent()
    if parent and parent is RigidBody3D:
        # Apply a random impulse to make debris fly outward
        var impulse_direction = Vector3(
            randf_range(-1.0, 1.0),
            randf_range(0.5, 1.5),
            randf_range(-1.0, 1.0)
        ).normalized()
        
        var impulse_strength = randf_range(5.0, 20.0)
        var impulse = impulse_direction * impulse_strength
        
        # Apply the impulse
        parent.apply_impulse(impulse, debris_mesh.position)

## Get the mesh instance from an object if it exists
func _get_mesh_instance(object) -> MeshInstance3D:
    # Try to find a MeshInstance3D in the object or its children
    if object is MeshInstance3D:
        return object
    
    # Search in children
    for child in object.get_children():
        if child is MeshInstance3D:
            return child
        # Recursively search deeper
        var result = _get_mesh_instance(child)
        if result:
            return result
    
    return null

## Create a simplified version of the object for debris
func _create_simplified_mesh(original_mesh: Mesh, complexity: float = 0.5) -> Mesh:
    # In a full implementation, this would simplify the mesh
    # based on the complexity parameter
    # For now, return the original mesh
    return original_mesh