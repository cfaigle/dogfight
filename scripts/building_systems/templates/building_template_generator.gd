@tool
class_name BuildingTemplateGenerator
extends Node

# TEMPLATE-BASED BUILDING GENERATOR
# Generates buildings from architectural templates
# Author: Claude AI Assistant  
# Version: 1.0

signal building_generated(mesh: Mesh, materials: Array[Material])

# Template registry
var template_registry: BuildingTemplateRegistry

# Random number generator for building generation
var rng: RandomNumberGenerator

# Initialize with template registry
func _init(registry: BuildingTemplateRegistry = null):
    template_registry = registry if registry else BuildingTemplateRegistry.new()
    rng = RandomNumberGenerator.new()

# Generate building from template
func generate_building(template_name: String, plot: Dictionary, seed_value: int = 0) -> MeshInstance3D:
    var template = template_registry.get_template(template_name)
    if template == null:
        push_error("Template not found: %s" % template_name)
        return null
    
    rng.seed = seed_value
    
    # Calculate building dimensions with variation
    var dimensions = _calculate_building_dimensions(template, plot)
    
    # Generate building mesh
    var mesh = _generate_template_mesh(template, dimensions)
    
    # Create building node
    var building_node = MeshInstance3D.new()
    building_node.name = "TemplateBuilding_%s_%d" % [template.template_name if template.template_name else "unknown", seed_value]
    building_node.set_meta("building_type", template.template_name if template.template_name else "unknown")
    building_node.set_meta("building_category", "building")
    building_node.mesh = mesh
    
    # Apply materials
    _apply_template_materials(building_node, template)
    
    return building_node

# Generate random building based on criteria
func generate_random_building(category: String = "", biome: String = "", settlement_type: String = "", plot: Dictionary = {}, seed_value: int = 0) -> MeshInstance3D:
    var template = template_registry.get_weighted_random_template(category, biome, settlement_type)
    if template == null:
        push_error("No suitable template found for criteria: cat=%s, biome=%s, settlement=%s" % [category, biome, settlement_type])
        return null
    
    return generate_building(template.template_name, plot, seed_value)

# Calculate building dimensions with variation
func _calculate_building_dimensions(template: BuildingTemplateDefinition, plot: Dictionary) -> Dictionary:
    var base_dims = template.base_dimensions
    var variation = template.dimension_variation
    
    # Apply random variation
    var width = base_dims.x + rng.randf_range(-variation.x, variation.x)
    var height = base_dims.y + rng.randf_range(-variation.y, variation.y)  
    var depth = base_dims.z + rng.randf_range(-variation.z, variation.z)
    
    # Clamp to plot size if available
    if plot.has("lot_width"):
        width = min(width, plot.lot_width * 0.8)
    if plot.has("lot_depth"):
        depth = min(depth, plot.lot_depth * 0.8)
    
    # Ensure minimum size
    width = max(width, 3.0)
    height = max(height, 2.5)
    depth = max(depth, 3.0)
    
    return {
        "width": width,
        "height": height,
        "depth": depth,
        "half_width": width * 0.5,
        "half_depth": depth * 0.5
    }

# Generate mesh from template
func _generate_template_mesh(template: BuildingTemplateDefinition, dimensions: Dictionary) -> Mesh:
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    # Generate building components
    _generate_walls(st, template, dimensions)
    _generate_roof(st, template, dimensions)
    
    # Generate specialized components based on building type
    match template.architectural_style:
        "industrial", "factory":
            _generate_industrial_features(st, template, dimensions)
        "castle", "medieval":
            _generate_castle_features(st, template, dimensions)
        _:
            # Standard features for other types
            if template.has_chimney:
                _generate_chimney(st, template, dimensions)
    
    _generate_openings(st, template, dimensions)
    
    st.generate_normals()
    st.generate_tangents()
    return st.commit()

# Generate walls from template configuration
func _generate_walls(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var wall_config = template.wall_config
    var w = dimensions.width
    var d = dimensions.depth
    var h = wall_config.wall_height
    var hw = dimensions.half_width
    var hd = dimensions.half_depth
    
    # Base wall corners
    var corners = [
        Vector3(-hw, 0, -hd),   # 0: back-left-bottom
        Vector3(hw, 0, -hd),    # 1: back-right-bottom
        Vector3(hw, 0, hd),     # 2: front-right-bottom
        Vector3(-hw, 0, hd),    # 3: front-left-bottom
        Vector3(-hw, h, -hd),   # 4: back-left-top
        Vector3(hw, h, -hd),    # 5: back-right-top
        Vector3(hw, h, hd),     # 6: front-right-top
        Vector3(-hw, h, hd),    # 7: front-left-top
    ]
    
    # Apply rustic variation if enabled
    if wall_config.has_rustic_variation:
        var offset_range = wall_config.rustic_offset_range
        for i in range(4, 8):  # Only affect top corners
            corners[i].x += rng.randf_range(-offset_range, offset_range)
            corners[i].z += rng.randf_range(-offset_range * 0.5, offset_range * 0.5)
    
    # Create wall faces with proper normals and UVs
    _create_wall_face(st, corners[3], corners[2], corners[6], corners[7], Vector3(0, 0, 1))  # Front
    _create_wall_face(st, corners[1], corners[0], corners[4], corners[5], Vector3(0, 0, -1))  # Back
    _create_wall_face(st, corners[0], corners[3], corners[7], corners[4], Vector3(-1, 0, 0))  # Left
    _create_wall_face(st, corners[2], corners[1], corners[5], corners[6], Vector3(1, 0, 0))   # Right

# Create individual wall face with proper UVs
func _create_wall_face(st: SurfaceTool, bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3, normal: Vector3):
    st.set_normal(normal)
    
    # Calculate UV coordinates
    var width = bl.distance_to(br)
    var height = bl.distance_to(tl)
    
    # Triangle 1
    st.set_uv(Vector2(0, 1))
    st.add_vertex(bl)
    st.set_uv(Vector2(width / 2.0, 1))  # Scale UVs reasonably
    st.add_vertex(br)
    st.set_uv(Vector2(width / 2.0, 0))
    st.add_vertex(tr)
    
    # Triangle 2
    st.set_uv(Vector2(0, 1))
    st.add_vertex(bl)
    st.set_uv(Vector2(width / 2.0, 0))
    st.add_vertex(tr)
    st.set_uv(Vector2(0, 0))
    st.add_vertex(tl)

# Generate roof from template configuration
func _generate_roof(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var roof_config = template.roof_config
    var w = dimensions.width
    var d = dimensions.depth
    var hw = dimensions.half_width
    var hd = dimensions.half_depth
    var wall_height = template.wall_config.wall_height
    
    var roof_height = wall_height + (w * 0.5 * tan(deg_to_rad(roof_config.roof_pitch)))
    
    # Wall top corners for roof base
    var front_left = Vector3(-hw, wall_height, hd)
    var front_right = Vector3(hw, wall_height, hd)
    var back_left = Vector3(-hw, wall_height, -hd)
    var back_right = Vector3(hw, wall_height, -hd)
    
    # Roof peak centers
    var front_peak = Vector3(0, roof_height, hd)
    var back_peak = Vector3(0, roof_height, -hd)
    
    match roof_config.roof_type:
        "gabled":
            # Front gable
            _create_roof_triangle(st, front_left, front_right, front_peak, Vector3(0, 0.7, 0.7))
            # Back gable
            _create_roof_triangle(st, back_right, back_left, back_peak, Vector3(0, 0.7, -0.7))
            # Left roof slope
            _create_roof_quad(st, front_left, back_peak, back_left, front_peak, Vector3(-0.7, 0.7, 0))
            # Right roof slope
            _create_roof_quad(st, front_right, front_peak, back_peak, back_right, Vector3(0.7, 0.7, 0))
        "thatched":
            # Thatched roof - same geometry as gabled but with overhang
            var overhang = roof_config.roof_overhang
            # Expand roof footprint
            front_left.x -= overhang
            front_right.x += overhang
            back_left.x -= overhang
            back_right.x += overhang
            front_left.z += overhang
            front_right.z += overhang
            back_left.z -= overhang
            back_right.z -= overhang
            
            # Recreate roof with overhang
            front_peak = Vector3(0, roof_height, hd + overhang)
            back_peak = Vector3(0, roof_height, -hd - overhang)
            
            _create_roof_triangle(st, front_left, front_right, front_peak, Vector3(0, 0.7, 0.7))
            _create_roof_triangle(st, back_right, back_left, back_peak, Vector3(0, 0.7, -0.7))
            _create_roof_quad(st, front_left, back_peak, back_left, front_peak, Vector3(-0.7, 0.7, 0))
            _create_roof_quad(st, front_right, front_peak, back_peak, back_right, Vector3(0.7, 0.7, 0))

# Create roof triangle (for gables)
func _create_roof_triangle(st: SurfaceTool, left: Vector3, right: Vector3, peak: Vector3, normal: Vector3):
    st.set_normal(normal)
    
    # Triangle vertices
    st.set_uv(Vector2(0.25, 1))
    st.add_vertex(left)
    st.set_uv(Vector2(0.75, 1))
    st.add_vertex(right)
    st.set_uv(Vector2(0.5, 0))
    st.add_vertex(peak)

# Create roof quad (for roof slopes)
func _create_roof_quad(st: SurfaceTool, v1: Vector3, v2: Vector3, v3: Vector3, v4: Vector3, normal: Vector3):
    st.set_normal(normal)
    
    # Triangle 1
    st.set_uv(Vector2(0, 1))
    st.add_vertex(v1)
    st.set_uv(Vector2(1, 0))
    st.add_vertex(v2)
    st.set_uv(Vector2(0, 0))
    st.add_vertex(v3)
    
    # Triangle 2
    st.set_uv(Vector2(0, 1))
    st.add_vertex(v1)
    st.set_uv(Vector2(0, 0))
    st.add_vertex(v3)
    st.set_uv(Vector2(1, 1))
    st.add_vertex(v4)

# Generate chimney from template configuration
func _generate_chimney(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var chimney_pos = template.roof_config.chimney_position
    var wall_height = template.wall_config.wall_height
    var roof_height = wall_height + (dimensions.width * 0.5 * tan(deg_to_rad(template.roof_config.roof_pitch)))
    
    # Chimney dimensions
    var chimney_width = 0.8
    var chimney_depth = 0.8
    var chimney_height = roof_height + rng.randf_range(1.5, 2.5)
    
    # Position chimney on roof
    var chimney_x = dimensions.width * chimney_pos.x
    var chimney_z = dimensions.depth * chimney_pos.y
    
    var chw = chimney_width * 0.5
    var chd = chimney_depth * 0.5
    
    # Chimney corners
    var chimney_base = wall_height
    var chimney_corners = [
        Vector3(chimney_x - chw, chimney_base, chimney_z - chd),
        Vector3(chimney_x + chw, chimney_base, chimney_z - chd),
        Vector3(chimney_x + chw, chimney_base, chimney_z + chd),
        Vector3(chimney_x - chw, chimney_base, chimney_z + chd),
        Vector3(chimney_x - chw, chimney_height, chimney_z - chd),
        Vector3(chimney_x + chw, chimney_height, chimney_z - chd),
        Vector3(chimney_x + chw, chimney_height, chimney_z + chd),
        Vector3(chimney_x - chw, chimney_height, chimney_z + chd),
    ]
    
    # Create chimney sides
    for i in range(4):
        var next = (i + 1) % 4
        # Bottom face
        var normal1 = (chimney_corners[next] - chimney_corners[i]).cross(Vector3.UP).normalized()
        st.set_normal(normal1)
        
        st.add_vertex(chimney_corners[i])
        st.add_vertex(chimney_corners[next])
        st.add_vertex(chimney_corners[next + 4])
        
        # Top face
        st.add_vertex(chimney_corners[i])
        st.add_vertex(chimney_corners[next + 4])
        st.add_vertex(chimney_corners[i + 4])

# Generate openings (doors and windows)
func _generate_openings(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var window_config = template.window_config
    var door_config = template.door_config
    
    # Generate windows
    _generate_windows(st, template, dimensions)
    
    # Generate doors
    _generate_doors(st, template, dimensions)

# Generate window geometry
func _generate_windows(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var window_config = template.window_config
    var w = dimensions.width
    var d = dimensions.depth
    var h = template.wall_config.wall_height
    var hw = dimensions.half_width
    var hd = dimensions.half_depth
    
    var window_size = window_config.window_size
    var window_count = window_config.window_count
    
    match window_config.window_distribution:
        "symmetric":
            # Distribute windows symmetrically on front and back walls
            var windows_per_wall = window_count / 2
            var spacing = w / (windows_per_wall + 1)
            
            for i in range(windows_per_wall):
                var x_pos = -hw + spacing * (i + 1)
                var window_height = h * 0.6 + rng.randf_range(-0.2, 0.3)
                
                # Front wall windows
                _create_window_geometry(st, Vector3(x_pos, window_height, hd), window_size, Vector3(0, 0, 1))
                # Back wall windows
                _create_window_geometry(st, Vector3(x_pos, window_height, -hd), window_size, Vector3(0, 0, -1))
        "random":
            # Random window placement
            for i in range(window_count):
                var wall_side = rng.randi() % 4
                var x_pos = rng.randf_range(-hw + 0.5, hw - 0.5)
                var z_pos = rng.randf_range(-hd + 0.5, hd - 0.5)
                var window_height = h * 0.6 + rng.randf_range(-0.2, 0.3)
                
                match wall_side:
                    0: # Front
                        _create_window_geometry(st, Vector3(x_pos, window_height, hd), window_size, Vector3(0, 0, 1))
                    1: # Back
                        _create_window_geometry(st, Vector3(x_pos, window_height, -hd), window_size, Vector3(0, 0, -1))
                    2: # Left
                        _create_window_geometry(st, Vector3(-hw, window_height, z_pos), window_size, Vector3(-1, 0, 0))
                    3: # Right
                        _create_window_geometry(st, Vector3(hw, window_height, z_pos), window_size, Vector3(1, 0, 0))

# Generate door geometry
func _generate_doors(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var door_config = template.door_config
    var door_size = door_config.door_size
    var door_pos = door_config.door_position
    
    var w = dimensions.width
    var d = dimensions.depth
    var h = template.wall_config.wall_height
    var hw = dimensions.half_width
    var hd = dimensions.half_depth
    
    # Place door on front wall centered by default
    var door_x = door_pos.x
    var door_z = hd  # Front wall
    var door_y = 0.0  # Ground level
    
    _create_door_geometry(st, Vector3(door_x, door_y, door_z), door_size, Vector3(0, 0, 1), template)

# Create individual window geometry
func _create_window_geometry(st: SurfaceTool, position: Vector3, size: Vector2, normal: Vector3):
    var half_width = size.x * 0.5
    var half_height = size.y * 0.5
    
    # Calculate window corners based on normal
    var corners = []
    var right = Vector3.UP.cross(normal).normalized()
    var up = Vector3.UP
    
    corners.append(position - right * half_width - up * half_height)  # bottom-left
    corners.append(position + right * half_width - up * half_height)  # bottom-right
    corners.append(position + right * half_width + up * half_height)  # top-right
    corners.append(position - right * half_width + up * half_height)  # top-left
    
    # Create window frame (simple rectangular opening)
    # In a full implementation, this would carve an actual hole in the wall
    # For now, we'll create a recessed window surface
    st.set_normal(normal)
    
    # Window frame depth
    var frame_depth = 0.05
    
    # Front face (glass)
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[0] - normal * frame_depth)
    st.set_uv(Vector2(1, 0))
    st.add_vertex(corners[1] - normal * frame_depth)
    st.set_uv(Vector2(1, 1))
    st.add_vertex(corners[2] - normal * frame_depth)
    
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[0] - normal * frame_depth)
    st.set_uv(Vector2(1, 1))
    st.add_vertex(corners[2] - normal * frame_depth)
    st.set_uv(Vector2(0, 1))
    st.add_vertex(corners[3] - normal * frame_depth)

# Create individual door geometry
func _create_door_geometry(st: SurfaceTool, position: Vector3, size: Vector2, normal: Vector3, template: BuildingTemplateDefinition):
    var half_width = size.x * 0.5
    var height = size.y
    
    # Calculate door corners based on normal
    var right = Vector3.UP.cross(normal).normalized()
    var up = Vector3.UP
    
    var bottom_left = position - right * half_width
    var bottom_right = position + right * half_width
    var top_right = position + right * half_width + up * height
    var top_left = position - right * half_width + up * height
    
    # Create door surface
    st.set_normal(normal)
    
    # Door depth
    var door_depth = 0.08
    
    # Door face
    st.set_uv(Vector2(0, 0))
    st.add_vertex(bottom_left - normal * door_depth)
    st.set_uv(Vector2(1, 0))
    st.add_vertex(bottom_right - normal * door_depth)
    st.set_uv(Vector2(1, 1))
    st.add_vertex(top_right - normal * door_depth)
    
    st.set_uv(Vector2(0, 0))
    st.add_vertex(bottom_left - normal * door_depth)
    st.set_uv(Vector2(1, 1))
    st.add_vertex(top_right - normal * door_depth)
    st.set_uv(Vector2(0, 1))
    st.add_vertex(top_left - normal * door_depth)
    
    # Add door frame if enabled
    if template.door_config.has_door_frame:
        _create_door_frame(st, bottom_left, bottom_right, top_right, top_left, normal, template.door_config.door_frame_width)

# Create door frame
func _create_door_frame(st: SurfaceTool, bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3, normal: Vector3, frame_width: float):
    var frame_depth = 0.12
    
    # Top frame
    st.set_normal(Vector3.UP)
    st.add_vertex(tl - normal * frame_depth)
    st.add_vertex(tr - normal * frame_depth)
    st.add_vertex(tr - normal * (frame_depth - frame_width))
    
    st.add_vertex(tl - normal * frame_depth)
    st.add_vertex(tr - normal * (frame_depth - frame_width))
    st.add_vertex(tl - normal * (frame_depth - frame_width))
    
    # Left frame
    var left_normal = Vector3.UP.cross(normal).normalized()
    st.set_normal(left_normal)
    st.add_vertex(bl)
    st.add_vertex(tl)
    st.add_vertex(tl - normal * (frame_depth - frame_width))
    
    st.add_vertex(bl)
    st.add_vertex(tl - normal * (frame_depth - frame_width))
    st.add_vertex(bl - normal * (frame_depth - frame_width))
    
    # Right frame
    var right_normal = -left_normal
    st.set_normal(right_normal)
    st.add_vertex(br)
    st.add_vertex(br - normal * (frame_depth - frame_width))
    st.add_vertex(tr - normal * (frame_depth - frame_width))
    
    st.add_vertex(br)
    st.add_vertex(tr - normal * (frame_depth - frame_width))
    st.add_vertex(tr)

# Apply template materials to building
func _apply_template_materials(building: MeshInstance3D, template: BuildingTemplateDefinition):
    var materials = template.material_definitions
    
    # Apply materials based on surface indices (this would be more sophisticated in a full implementation)
    var mat_array = []
    mat_array.append(materials.wall_material)
    mat_array.append(materials.roof_material)
    
    building.material_override = mat_array[0]  # Simplified for now

# Generate industrial building features (smokestacks, etc.)
func _generate_industrial_features(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var industrial_config = template.industrial_config
    
    if industrial_config.has_smokestacks:
        _generate_smokestacks(st, template, dimensions)
    
    if industrial_config.has_metal_siding:
        # Metal siding would be handled through materials
        pass

# Generate smokestacks for factory buildings
func _generate_smokestacks(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var industrial_config = template.industrial_config
    var w = dimensions.width
    var d = dimensions.depth
    var h = template.wall_config.wall_height
    var hw = dimensions.half_width
    var hd = dimensions.half_depth
    var roof_height = h + (w * 0.5 * tan(deg_to_rad(template.roof_config.roof_pitch)))
    
    var stack_count = industrial_config.smokestack_count
    var stack_width = industrial_config.smokestack_width
    var stack_height = roof_height * industrial_config.smokestack_height_multiplier
    
    for i in range(stack_count):
        var stack_x = -hw * 0.6 + (i * hw * 1.2 / float(max(1, stack_count - 1)))
        var stack_z = -hd * 0.7
        var stack_hw = stack_width * 0.5
        
        # Stack corners
        var stack_corners = [
            Vector3(stack_x - stack_hw, roof_height, stack_z - stack_hw),
            Vector3(stack_x + stack_hw, roof_height, stack_z - stack_hw),
            Vector3(stack_x + stack_hw, roof_height, stack_z + stack_hw),
            Vector3(stack_x - stack_hw, roof_height, stack_z + stack_hw),
            Vector3(stack_x - stack_hw, stack_height, stack_z - stack_hw),
            Vector3(stack_x + stack_hw, stack_height, stack_z - stack_hw),
            Vector3(stack_x + stack_hw, stack_height, stack_z + stack_hw),
            Vector3(stack_x - stack_hw, stack_height, stack_z + stack_hw),
        ]
        
        # Create stack sides
        for j in range(4):
            var next = (j + 1) % 4
            var normal = (stack_corners[next] - stack_corners[j]).cross(Vector3.UP).normalized()
            st.set_normal(normal)
            
            st.add_vertex(stack_corners[j])
            st.add_vertex(stack_corners[next])
            st.add_vertex(stack_corners[next + 4])
            st.add_vertex(stack_corners[j])
            st.add_vertex(stack_corners[next + 4])
            st.add_vertex(stack_corners[j + 4])

# Generate castle features (battlements, towers, etc.)
func _generate_castle_features(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var castle_config = template.castle_config
    var w = dimensions.width
    var d = dimensions.depth
    var h = template.wall_config.wall_height
    var hw = dimensions.half_width
    var hd = dimensions.half_depth
    
    if castle_config.has_battlements:
        _generate_battlements(st, template, dimensions)
    
    if castle_config.has_corner_towers:
        _generate_corner_towers(st, template, dimensions)
    
    if castle_config.has_main_gate:
        _generate_castle_gate(st, template, dimensions)

# Generate castle battlements (crenellations)
func _generate_battlements(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var castle_config = template.castle_config
    var w = dimensions.width
    var d = dimensions.depth
    var h = template.wall_config.wall_height
    var hw = dimensions.half_width
    var hd = dimensions.half_depth
    
    var battlement_height = castle_config.battlement_height
    var battlement_width = castle_config.battlement_width
    var battlement_spacing = castle_config.battlement_spacing
    
    # Front battlements
    var front_segments = int(d / battlement_spacing)
    for i in range(front_segments):
        var t = float(i) / float(max(1, front_segments - 1))
        var x_pos = -hw + (hw * 2.0) * t
        var z_pos = hd
        var base_y = template.wall_config.wall_height

        _create_single_battlement(st, x_pos, z_pos, battlement_height, battlement_width, base_y)

    # Back battlements
    var back_segments = int(d / battlement_spacing)
    for i in range(back_segments):
        var t = float(i) / float(max(1, back_segments - 1))
        var x_pos = -hw + (hw * 2.0) * t
        var z_pos = -hd
        var base_y = template.wall_config.wall_height

        _create_single_battlement(st, x_pos, z_pos, battlement_height, battlement_width, base_y)

    # Side battlements
    var left_segments = int(w / battlement_spacing)
    for i in range(left_segments):
        var t = float(i) / float(max(1, left_segments - 1))
        var x_pos = -hw
        var z_pos = -hd + (hd * 2.0) * t
        var base_y = template.wall_config.wall_height

        _create_single_battlement(st, x_pos, z_pos, battlement_height, battlement_width, base_y, true)

# Create individual battlement
func _create_single_battlement(st: SurfaceTool, x: float, z: float, height: float, width: float, base_y: float, is_side: bool = false):
    var bw = width * 0.5
    var bd = width * 0.5 if is_side else width * 0.5

    # Front face
    st.set_normal(Vector3(0, 0, 1) if not is_side else Vector3(-1, 0, 0))
    st.add_vertex(Vector3(x - bw, base_y, z - bd))
    st.add_vertex(Vector3(x + bw, base_y, z - bd))
    st.add_vertex(Vector3(x + bw, base_y + height, z - bd))
    st.add_vertex(Vector3(x - bw, base_y, z - bd))
    st.add_vertex(Vector3(x + bw, base_y + height, z - bd))
    st.add_vertex(Vector3(x - bw, base_y + height, z - bd))

# Generate corner towers for castle
func _generate_corner_towers(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var castle_config = template.castle_config
    var w = dimensions.width
    var d = dimensions.depth
    var h = template.wall_config.wall_height
    var hw = dimensions.half_width
    var hd = dimensions.half_depth
    
    var tower_radius = castle_config.tower_diameter * 0.5
    var tower_height = h * castle_config.tower_height_multiplier
    var sides = 8
    
    # Corner positions
    var corners = [
        Vector3(-hw + tower_radius, 0, hd - tower_radius),  # Front-left
        Vector3(hw - tower_radius, 0, hd - tower_radius),   # Front-right
        Vector3(hw - tower_radius, 0, -hd + tower_radius),  # Back-right
        Vector3(-hw + tower_radius, 0, -hd + tower_radius)  # Back-left
    ]
    
    for corner_pos in corners:
        _generate_circular_tower(st, corner_pos, tower_radius, h, tower_height, sides)

# Generate circular tower
func _generate_circular_tower(st: SurfaceTool, position: Vector3, radius: float, base_height: float, top_height: float, sides: int):
    for i in range(sides):
        var angle1 = (float(i) / float(sides)) * TAU
        var angle2 = (float(i + 1) / float(sides)) * TAU
        
        var x1 = position.x + cos(angle1) * radius
        var z1 = position.z + sin(angle1) * radius
        var x2 = position.x + cos(angle2) * radius
        var z2 = position.z + sin(angle2) * radius
        
        # Tower wall vertices
        var v0 = Vector3(x1, base_height, z1)
        var v1 = Vector3(x2, base_height, z2)
        var v2 = Vector3(x2, top_height, z2)
        var v3 = Vector3(x1, top_height, z1)
        
        var normal = (v1 - v0).cross(v3 - v0).normalized()
        st.set_normal(normal)
        
        # Tower wall triangles
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

# Generate castle gate
func _generate_castle_gate(st: SurfaceTool, template: BuildingTemplateDefinition, dimensions: Dictionary):
    var castle_config = template.castle_config
    var w = dimensions.width
    var d = dimensions.depth
    var h = template.wall_config.wall_height
    var hd = dimensions.half_depth
    
    var gate_width = castle_config.gate_width
    var gate_height = castle_config.gate_height
    var gate_half_width = gate_width * 0.5
    
    # Gate archway would be carved into the front wall
    # For now, we'll just mark the gate position in the wall
    # Full implementation would create an arched opening
    pass

# Get template registry
func get_template_registry() -> BuildingTemplateRegistry:
    return template_registry