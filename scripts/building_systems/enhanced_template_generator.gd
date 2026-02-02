@tool
class_name EnhancedBuildingTemplateGenerator
extends RefCounted

# ENHANCED TEMPLATE-BASED BUILDING GENERATOR
# Generates high-quality buildings from architectural templates using component system
# Author: Claude AI Assistant
# Version: 1.0

# Template registry
var template_registry: BuildingTemplateRegistry

# Component registry for building components
var component_registry: ComponentRegistry

# Initialize with registries
func _init(template_reg: BuildingTemplateRegistry = null, component_reg: ComponentRegistry = null):
    template_registry = template_reg if template_reg else BuildingTemplateRegistry.new()
    component_registry = component_reg if component_reg else ComponentRegistry.new()
    
    # Register default components
    component_registry.register_component("wall", WallComponent)
    component_registry.register_component("window", WindowComponent)
    component_registry.register_component("roof", RoofComponent)
    component_registry.register_component("detail", DetailComponent)

# Generate building from template with high quality components
func generate_building_from_template(template_name: String, plot: Dictionary, seed_value: int = 0) -> MeshInstance3D:
    var template = template_registry.get_template(template_name)
    if template == null:
        push_error("Template not found: %s" % template_name)
        return null

    var rng = RandomNumberGenerator.new()
    rng.seed = seed_value

    # Calculate building dimensions with variation
    var dimensions = _calculate_building_dimensions(template, plot)

    # Generate building mesh using component system
    var mesh = _generate_template_mesh_with_components(template, dimensions)

    # Create building node
    var building_node = MeshInstance3D.new()
    building_node.name = "EnhancedTemplate_%s_%d" % [template.template_name if template.template_name else "unknown", seed_value]
    building_node.set_meta("building_type", template.template_name if template.template_name else "unknown")
    building_node.set_meta("building_category", "building")
    building_node.mesh = mesh

    # Apply materials from template
    _apply_template_materials(building_node, template)

    return building_node

# Generate mesh using component system for better quality
func _generate_template_mesh_with_components(template: BuildingTemplateDefinition, dimensions: Dictionary) -> Mesh:
    var array_mesh = ArrayMesh.new()
    
    # Create materials for this building
    var materials = _create_materials_from_template(template)

    # Generate building components with proper normals and UVs
    _generate_walls_with_components(array_mesh, template, dimensions, materials)
    _generate_roof_with_components(array_mesh, template, dimensions, materials)
    _generate_openings_with_components(array_mesh, template, dimensions, materials)
    _generate_details_with_components(array_mesh, template, dimensions, materials)
    
    # Generate specialized components based on building type
    match template.architectural_style:
        "industrial", "factory":
            _generate_industrial_features_with_components(array_mesh, template, dimensions, materials)
        "castle", "medieval":
            _generate_castle_features_with_components(array_mesh, template, dimensions, materials)
        _:
            # Standard features for other types
            if template.has_chimney:
                _generate_chimney_with_components(array_mesh, template, dimensions, materials)

    return array_mesh

# Generate walls using wall component
func _generate_walls_with_components(array_mesh: ArrayMesh, template: BuildingTemplateDefinition, dimensions: Dictionary, materials: Dictionary):
    var wall_config = template.wall_config
    var w = dimensions.width
    var d = dimensions.depth
    var h = wall_config.wall_height
    var hw = dimensions.half_width
    var hd = dimensions.half_depth

    # Create footprint for wall component
    var footprint = PackedVector2Array()
    footprint.push_back(Vector2(-hw, -hd))
    footprint.push_back(Vector2(hw, -hd))
    footprint.push_back(Vector2(hw, hd))
    footprint.push_back(Vector2(-hw, hd))

    # Use wall component for proper geometry
    var wall_component = component_registry.get_component("wall")
    if wall_component:
        var wall_params = {
            "footprint": footprint,
            "height": h,
            "floors": 1,
            "floor_height": h,
            "wall_thickness": wall_config.wall_thickness,
            "create_interior": false
        }
        
        if wall_component.validate_params(wall_params):
            var st = SurfaceTool.new()
            st.begin(Mesh.PRIMITIVE_TRIANGLES)
            
            wall_component.generate(st, wall_params, materials)
            st.generate_normals()
            
            var arrays = st.commit_to_arrays()
            if arrays[Mesh.ARRAY_VERTEX].size() > 0:
                array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
                
                # Apply wall material
                var wall_material = materials.get("wall", materials.values()[0] if materials.values().size() > 0 else null)
                if wall_material:
                    array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, wall_material)

# Generate roof using roof component
func _generate_roof_with_components(array_mesh: ArrayMesh, template: BuildingTemplateDefinition, dimensions: Dictionary, materials: Dictionary):
    var roof_config = template.roof_config
    var w = dimensions.width
    var d = dimensions.depth
    var hw = dimensions.half_width
    var hd = dimensions.half_depth
    var wall_height = template.wall_config.wall_height

    # Create footprint for roof component
    var footprint = PackedVector2Array()
    footprint.push_back(Vector2(-hw, -hd))
    footprint.push_back(Vector2(hw, -hd))
    footprint.push_back(Vector2(hw, hd))
    footprint.push_back(Vector2(-hw, hd))

    # Use roof component for proper geometry
    var roof_component = component_registry.get_component("roof")
    if roof_component:
        var roof_params = {
            "footprint": footprint,
            "height": wall_height,
            "roof_type": roof_config.roof_type,
            "roof_pitch": roof_config.roof_pitch / 45.0,  # Normalize to 0-1 range
            "overhang": roof_config.roof_overhang,
            "add_dormers": false,
            "dormer_count": 0,
            "add_cupola": false,
            "texture_scale": 2.0
        }
        
        if roof_component.validate_params(roof_params):
            var st = SurfaceTool.new()
            st.begin(Mesh.PRIMITIVE_TRIANGLES)
            
            roof_component.generate(st, roof_params, materials)
            st.generate_normals()
            
            var arrays = st.commit_to_arrays()
            if arrays[Mesh.ARRAY_VERTEX].size() > 0:
                array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
                
                # Apply roof material
                var roof_material = materials.get("roof", materials.values()[1] if materials.values().size() > 1 else null)
                if roof_material:
                    array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, roof_material)

# Generate windows and doors using components
func _generate_openings_with_components(array_mesh: ArrayMesh, template: BuildingTemplateDefinition, dimensions: Dictionary, materials: Dictionary):
    var window_config = template.window_config
    var door_config = template.door_config
    var w = dimensions.width
    var d = dimensions.depth
    var h = template.wall_config.wall_height
    var hw = dimensions.half_width
    var hd = dimensions.half_depth

    # Create footprint for window component
    var footprint = PackedVector2Array()
    footprint.push_back(Vector2(-hw, -hd))
    footprint.push_back(Vector2(hw, -hd))
    footprint.push_back(Vector2(hw, hd))
    footprint.push_back(Vector2(-hw, hd))

    # Generate windows using window component
    var window_component = component_registry.get_component("window")
    if window_component:
        var window_params = {
            "footprint": footprint,
            "height": h,
            "floors": 1,
            "floor_height": h,
            "window_style": window_config.window_style,
            "window_proportion": 0.4,
            "window_width": window_config.window_size.x,
            "window_height": window_config.window_size.y,
            "window_spacing": 2.5,
            "window_depth": 0.15,
            "skip_ground_floor": false,
            "add_shutters": true,
            "add_trim": true
        }
        
        if window_component.validate_params(window_params):
            var st = SurfaceTool.new()
            st.begin(Mesh.PRIMITIVE_TRIANGLES)
            
            window_component.generate(st, window_params, materials)
            st.generate_normals()
            
            var arrays = st.commit_to_arrays()
            if arrays[Mesh.ARRAY_VERTEX].size() > 0:
                array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
                
                # Apply window material
                var window_material = materials.get("window", materials.values()[2] if materials.values().size() > 2 else null)
                if window_material:
                    array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, window_material)

# Generate details using detail component
func _generate_details_with_components(array_mesh: ArrayMesh, template: BuildingTemplateDefinition, dimensions: Dictionary, materials: Dictionary):
    var detail_config = template.detail_config
    var w = dimensions.width
    var d = dimensions.depth
    var h = template.wall_config.wall_height
    var hw = dimensions.half_width
    var hd = dimensions.half_depth

    # Create footprint for detail component
    var footprint = PackedVector2Array()
    footprint.push_back(Vector2(-hw, -hd))
    footprint.push_back(Vector2(hw, -hd))
    footprint.push_back(Vector2(hw, hd))
    footprint.push_back(Vector2(-hw, hd))

    # Generate details using detail component
    var detail_component = component_registry.get_component("detail")
    if detail_component:
        var detail_params = {
            "footprint": footprint,
            "height": h,
            "floors": 1,
            "floor_height": h,
            "detail_intensity": detail_config.detail_intensity,
            "detail_scale": detail_config.detail_scale,
            "add_cornice": detail_config.has_wooden_beams,
            "add_string_courses": detail_config.has_stone_foundations,
            "add_quoins": true,
            "add_dentils": false,
            "add_brackets": false
        }
        
        if detail_component.validate_params(detail_params):
            var st = SurfaceTool.new()
            st.begin(Mesh.PRIMITIVE_TRIANGLES)
            
            detail_component.generate(st, detail_params, materials)
            st.generate_normals()
            
            var arrays = st.commit_to_arrays()
            if arrays[Mesh.ARRAY_VERTEX].size() > 0:
                array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
                
                # Apply detail material
                var detail_material = materials.get("trim", materials.values()[3] if materials.values().size() > 3 else null)
                if detail_material:
                    array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, detail_material)

# Generate chimney using components
func _generate_chimney_with_components(array_mesh: ArrayMesh, template: BuildingTemplateDefinition, dimensions: Dictionary, materials: Dictionary):
    # For now, use simple geometry for chimney
    # In a full implementation, we'd have a chimney component
    pass

# Generate industrial features using components
func _generate_industrial_features_with_components(array_mesh: ArrayMesh, template: BuildingTemplateDefinition, dimensions: Dictionary, materials: Dictionary):
    var industrial_config = template.industrial_config
    if industrial_config.has_smokestacks:
        _generate_smokestacks_with_components(array_mesh, template, dimensions, materials)

# Generate smokestacks
func _generate_smokestacks_with_components(array_mesh: ArrayMesh, template: BuildingTemplateDefinition, dimensions: Dictionary, materials: Dictionary):
    # For now, use simple geometry for smokestacks
    # In a full implementation, we'd have a chimney/smokestack component
    pass

# Generate castle features using components
func _generate_castle_features_with_components(array_mesh: ArrayMesh, template: BuildingTemplateDefinition, dimensions: Dictionary, materials: Dictionary):
    var castle_config = template.castle_config
    if castle_config.has_battlements:
        _generate_battlements_with_components(array_mesh, template, dimensions, materials)
    if castle_config.has_corner_towers:
        _generate_corner_towers_with_components(array_mesh, template, dimensions, materials)

# Generate battlements
func _generate_battlements_with_components(array_mesh: ArrayMesh, template: BuildingTemplateDefinition, dimensions: Dictionary, materials: Dictionary):
    # For now, use simple geometry for battlements
    # In a full implementation, we'd have a battlement component
    pass

# Generate corner towers
func _generate_corner_towers_with_components(array_mesh: ArrayMesh, template: BuildingTemplateDefinition, dimensions: Dictionary, materials: Dictionary):
    # For now, use simple geometry for towers
    # In a full implementation, we'd have a tower component
    pass

# Calculate building dimensions with variation
func _calculate_building_dimensions(template: BuildingTemplateDefinition, plot: Dictionary) -> Dictionary:
    var base_dims = template.base_dimensions
    var variation = template.dimension_variation

    # Apply random variation
    var width = base_dims.x + randf_range(-variation.x, variation.x)
    var height = base_dims.y + randf_range(-variation.y, variation.y)
    var depth = base_dims.z + randf_range(-variation.z, variation.z)

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

# Create materials from template
func _create_materials_from_template(template: BuildingTemplateDefinition) -> Dictionary:
    var materials = {}
    
    # Wall material
    var wall_mat = template.material_definitions.wall_material
    materials["wall"] = wall_mat

    # Roof material
    var roof_mat = template.material_definitions.roof_material
    materials["roof"] = roof_mat

    # Window material
    var window_mat = template.material_definitions.window_material
    materials["window"] = window_mat

    # Door material
    var door_mat = template.material_definitions.door_material
    materials["door"] = door_mat

    # Trim/detail material
    var trim_mat = template.material_definitions.detail_material
    materials["trim"] = trim_mat

    return materials

# Apply template materials to building
func _apply_template_materials(building: MeshInstance3D, template: BuildingTemplateDefinition):
    # Materials are applied during mesh generation in this enhanced version
    pass