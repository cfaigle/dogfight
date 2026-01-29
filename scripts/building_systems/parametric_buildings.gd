@tool
class_name BuildingParametricSystem
extends Resource

# CORE PARAMETRIC BUILDING SYSTEM
# Creates infinite building variety from mathematical parameters and style rules
# Author: Claude AI Assistant
# Version: 2.0 - Component-based architecture

signal building_generated(building_type: String, mesh: Mesh, materials: Array[Material])

# Component registry
var _component_registry: ComponentRegistry = null

# Initialize component system
func _init():
    _component_registry = ComponentRegistry.new()
    _register_components()

# Core parametric component definitions
var wall_profiles = {
    "modern": {"thickness": 0.15, "height_variation": 0.05},
    "historic": {"thickness": 0.25, "height_variation": 0.08},
    "industrial": {"thickness": 0.20, "height_variation": 0.02}
}

var roof_systems = {
    "flat": {"pitch": 0.0, "overhang": 0.1},
    "gabled": {"pitch": 35.0, "overhang": 0.3},
    "hipped": {"pitch": 25.0, "overhang": 0.2},
    "mansard": {"pitch": 45.0, "overhang": 0.4},
    "thatched": {"pitch": 50.0, "overhang": 0.4}
}

var window_systems = {
    "punched": {"style": "square", "proportion": 0.25},
    "double_hung": {"style": "vertical", "proportion": 0.40},
    "casement": {"style": "crank_outward", "proportion": 0.35},
    "bay": {"style": "projecting", "proportion": 0.60}
}

var detail_systems = {
    "subtle": {"intensity": 0.3, "scale": 0.8},
    "ornate": {"intensity": 0.7, "scale": 1.2},
    "minimal": {"intensity": 0.1, "scale": 0.5}
}

# Style configuration rules
var style_rules = {
    "ww2_european": {
        "roof_systems": ["gabled", "hipped", "mansard"],
        "wall_profiles": ["historic"],
        "window_systems": ["double_hung", "casement", "bay"],
        "detail_system": ["ornate"],
        "color_schemes": ["brick_red", "stone_gray", "stucco_beige"]
    },
    "american_art_deco": {
        "roof_systems": ["flat", "mansard"],
        "wall_profiles": ["modern"],
        "window_systems": ["punched", "casement"],
        "detail_system": ["subtle"],
        "color_schemes": ["pastel_colors", "earth_tones"]
    },
    "industrial_modern": {
        "roof_systems": ["flat", "gabled"],
        "wall_profiles": ["industrial"],
        "window_systems": ["punched", "bay"],
        "detail_system": ["minimal"],
        "color_schemes": ["concrete_gray", "metal_gray", "brick_orange"]
    },
    "stone_cottage": {
        "roof_systems": ["gabled", "thatched"],
        "wall_profiles": ["historic"],
        "window_systems": ["double_hung", "casement"],
        "detail_system": ["ornate"],
        "color_schemes": ["stone_gray", "earth_tones"]
    },
    "thatched_cottage": {
        "roof_systems": ["thatched", "gabled"],
        "wall_profiles": ["historic"],
        "window_systems": ["casement", "double_hung"],
        "detail_system": ["ornate"],
        "color_schemes": ["earth_tones", "stone_gray"]
    },
    "industrial": {
        "roof_systems": ["flat", "gabled"],
        "wall_profiles": ["industrial"],
        "window_systems": ["punched", "bay"],
        "detail_system": ["minimal"],
        "color_schemes": ["concrete_gray", "metal_gray"]
    },
    "castle": {
        "roof_systems": ["flat"],
        "wall_profiles": ["historic"],
        "window_systems": ["punched"],
        "detail_system": ["ornate"],
        "color_schemes": ["stone_gray", "brick_red"]
    }
}

# Register component classes
func _register_components():
    _component_registry.register_component("wall", WallComponent)
    _component_registry.register_component("window", WindowComponent)
    _component_registry.register_component("roof", RoofComponent)
    _component_registry.register_component("detail", DetailComponent)

# Create materials for a building style
func _create_materials(style: String) -> Dictionary:
    var materials = {}
    var style_rule = style_rules.get(style, style_rules["ww2_european"])
    var color_schemes = style_rule["color_schemes"]

    # Wall material
    var wall_mat = StandardMaterial3D.new()
    wall_mat.albedo_color = _get_color_from_scheme(color_schemes[0])
    wall_mat.roughness = 0.8
    wall_mat.metallic = 0.0
    materials["wall"] = wall_mat

    # Roof material
    var roof_mat = StandardMaterial3D.new()
    roof_mat.albedo_color = Color(0.3, 0.2, 0.15)  # Dark brown
    roof_mat.roughness = 0.9
    roof_mat.metallic = 0.0
    materials["roof"] = roof_mat

    # Window material (glass)
    var window_mat = StandardMaterial3D.new()
    window_mat.albedo_color = Color(0.7, 0.8, 0.9, 0.6)  # Light blue tint
    window_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    window_mat.roughness = 0.1
    window_mat.metallic = 0.0
    materials["window"] = window_mat

    # Door material (wood)
    var door_mat = StandardMaterial3D.new()
    door_mat.albedo_color = Color(0.4, 0.25, 0.15)  # Dark wood
    door_mat.roughness = 0.7
    door_mat.metallic = 0.0
    materials["door"] = door_mat

    # Trim/detail material
    var trim_mat = StandardMaterial3D.new()
    trim_mat.albedo_color = _get_color_from_scheme(color_schemes[0]).lightened(0.3)
    trim_mat.roughness = 0.7
    trim_mat.metallic = 0.0
    materials["trim"] = trim_mat

    return materials

# Get color from scheme name
func _get_color_from_scheme(scheme: String) -> Color:
    match scheme:
        "brick_red":
            return Color(0.7, 0.25, 0.2)
        "stone_gray":
            return Color(0.6, 0.6, 0.55)
        "stucco_beige":
            return Color(0.85, 0.8, 0.7)
        "concrete_gray":
            return Color(0.5, 0.5, 0.5)
        "metal_gray":
            return Color(0.4, 0.4, 0.45)
        "brick_orange":
            return Color(0.8, 0.4, 0.2)
        "pastel_colors":
            return Color(0.9, 0.85, 0.75)
        "earth_tones":
            return Color(0.65, 0.55, 0.45)
        _:
            return Color(0.7, 0.7, 0.7)

func create_parametric_building(
    building_type: String,
    style: String = "ww2_european",
    width: float = 10.0,
    depth: float = 8.0,
    height: float = 12.0,
    floors: int = 1,
    quality_level: int = 2
) -> Mesh:

    # print("🏗 Creating parametric building: ", building_type, " in ", style, " style")

    # Create materials for this building
    var materials = _create_materials(style)

    # Generate footprint based on type
    var footprint: PackedVector2Array
    if building_type == "residential":
        footprint = _create_residential_footprint(width, depth, floors)
    elif building_type == "commercial":
        footprint = _create_commercial_footprint(width, depth, floors)
    elif building_type == "industrial":
        footprint = _create_industrial_footprint(width, depth, floors)
    else:
        footprint = _create_default_footprint(width, depth)

    # Calculate floor height
    var floor_height = height / float(floors)

    # Get style parameters
    var style_rule = style_rules.get(style, style_rules["ww2_european"])
    var wall_profile = wall_profiles[style_rule["wall_profiles"][0]]
    var roof_system_name = style_rule["roof_systems"][randi() % style_rule["roof_systems"].size()]
    var roof_system = roof_systems[roof_system_name]
    var window_system_name = style_rule["window_systems"][randi() % style_rule["window_systems"].size()]
    var window_system = window_systems[window_system_name]
    var detail_system = detail_systems[style_rule["detail_system"][0]]

    # Create mesh using ArrayMesh to support multiple surfaces with different materials
    var array_mesh = ArrayMesh.new()

    # WALLS SURFACE
    var st_walls = SurfaceTool.new()
    st_walls.begin(Mesh.PRIMITIVE_TRIANGLES)

    var wall_component = _component_registry.get_component("wall")
    if wall_component:
        var wall_params = {
            "footprint": footprint,
            "height": height,
            "floors": floors,
            "floor_height": floor_height,
            "wall_thickness": wall_profile["thickness"],
            "texture_scale": 2.0
        }
        if wall_component.validate_params(wall_params):
            wall_component.generate(st_walls, wall_params, materials)

    st_walls.generate_normals()
    array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st_walls.commit_to_arrays())
    array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, materials["wall"])

    # WINDOWS SURFACE
    var st_windows = SurfaceTool.new()
    st_windows.begin(Mesh.PRIMITIVE_TRIANGLES)

    var window_component = _component_registry.get_component("window")
    if window_component:
        var window_params = {
            "footprint": footprint,
            "height": height,
            "floors": floors,
            "floor_height": floor_height,
            "window_style": window_system["style"],
            "window_proportion": window_system["proportion"],
            "window_width": 1.2,
            "window_height": 1.6,
            "window_spacing": 2.5,
            "window_depth": 0.15,
            "skip_ground_floor": false,
            "add_shutters": quality_level > 1,
            "add_trim": quality_level > 0
        }
        if window_component.validate_params(window_params):
            window_component.generate(st_windows, window_params, materials)

    st_windows.generate_normals()
    var window_arrays = st_windows.commit_to_arrays()
    if window_arrays[Mesh.ARRAY_VERTEX] != null and window_arrays[Mesh.ARRAY_VERTEX].size() > 0:
        array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, window_arrays)
        array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, materials["window"])

    # ROOF SURFACE
    var st_roof = SurfaceTool.new()
    st_roof.begin(Mesh.PRIMITIVE_TRIANGLES)

    var roof_component = _component_registry.get_component("roof")
    if roof_component:
        var roof_params = {
            "footprint": footprint,
            "height": height,
            "roof_type": roof_system_name,
            "roof_pitch": roof_system["pitch"] / 45.0,  # Normalize to 0-1 range
            "overhang": roof_system["overhang"],
            "add_dormers": quality_level > 1 and randf() > 0.5,
            "dormer_count": 2,
            "add_cupola": quality_level > 1 and randf() > 0.7,
            "texture_scale": 2.0
        }
        if roof_component.validate_params(roof_params):
            roof_component.generate(st_roof, roof_params, materials)

    st_roof.generate_normals()
    var roof_arrays = st_roof.commit_to_arrays()
    if roof_arrays[Mesh.ARRAY_VERTEX] != null and roof_arrays[Mesh.ARRAY_VERTEX].size() > 0:
        array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, roof_arrays)
        array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, materials["roof"])

    # DETAILS SURFACE
    if quality_level > 0:
        var st_details = SurfaceTool.new()
        st_details.begin(Mesh.PRIMITIVE_TRIANGLES)

        var detail_component = _component_registry.get_component("detail")
        if detail_component:
            var detail_params = {
                "footprint": footprint,
                "height": height,
                "floors": floors,
                "floor_height": floor_height,
                "detail_intensity": detail_system["intensity"],
                "detail_scale": detail_system["scale"],
                "add_cornice": true,
                "add_string_courses": quality_level > 1,
                "add_quoins": quality_level > 1,
                "add_dentils": quality_level > 2,
                "add_brackets": quality_level > 1
            }
            if detail_component.validate_params(detail_params):
                detail_component.generate(st_details, detail_params, materials)

        st_details.generate_normals()
        var detail_arrays = st_details.commit_to_arrays()
        if detail_arrays[Mesh.ARRAY_VERTEX] != null and detail_arrays[Mesh.ARRAY_VERTEX].size() > 0:
            array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, detail_arrays)
            array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, materials["trim"])

    # Convert materials dictionary to array for signal
    var material_array: Array[Material] = []
    for mat in materials.values():
        material_array.append(mat)

    emit_signal("building_generated", building_type, array_mesh, material_array)

    return array_mesh

func _create_residential_footprint(width: float, depth: float, floors: int) -> PackedVector2Array:
    # Generate varied residential footprints
    var shape_type = randi() % 4  # 0=rect, 1=L, 2=T, 3=courtyard

    match shape_type:
        0:  # Rectangle
            return _create_rect_footprint(width, depth)
        1:  # L-shape
            return _create_l_footprint(width, depth)
        2:  # T-shape
            return _create_t_footprint(width, depth)
        3:  # Courtyard (U-shape)
            return _create_u_footprint(width, depth)
        _:
            return _create_rect_footprint(width, depth)

func _create_commercial_footprint(width: float, depth: float, floors: int) -> PackedVector2Array:
    # Commercial buildings often rectangular or L-shaped for corner lots
    var shape_type = randi() % 3  # 0=rect, 1=L, 2=wider rect

    match shape_type:
        0, 2:  # Rectangular (wider for storefronts)
            return _create_rect_footprint(width * 1.2, depth * 0.9)
        1:  # L-shape for corner lot
            return _create_l_footprint(width, depth)
        _:
            return _create_rect_footprint(width, depth)

func _create_industrial_footprint(width: float, depth: float, floors: int) -> PackedVector2Array:
    # Industrial buildings are usually large rectangles or T-shapes
    var shape_type = randi() % 2  # 0=rect, 1=T

    match shape_type:
        0:  # Large rectangle
            return _create_rect_footprint(width * 1.5, depth)
        1:  # T-shape with loading bay
            return _create_t_footprint(width * 1.3, depth)
        _:
            return _create_rect_footprint(width, depth)

func _create_default_footprint(width: float, depth: float) -> PackedVector2Array:
    return _create_rect_footprint(width, depth)

# Footprint shape helper functions
func _create_rect_footprint(width: float, depth: float) -> PackedVector2Array:
    var points = PackedVector2Array()
    points.push_back(Vector2(-width/2, -depth/2))
    points.push_back(Vector2(width/2, -depth/2))
    points.push_back(Vector2(width/2, depth/2))
    points.push_back(Vector2(-width/2, depth/2))
    return points

func _create_l_footprint(width: float, depth: float) -> PackedVector2Array:
    var w1 = width * 0.6
    var w2 = width * 0.4
    var d1 = depth * 0.6
    var d2 = depth * 0.4

    var points = PackedVector2Array()
    points.push_back(Vector2(-w1/2, -d1/2))
    points.push_back(Vector2(w1/2, -d1/2))
    points.push_back(Vector2(w1/2, -d1/2 + d2))
    points.push_back(Vector2(w1/2 - w2, -d1/2 + d2))
    points.push_back(Vector2(w1/2 - w2, d1/2))
    points.push_back(Vector2(-w1/2, d1/2))
    return points

func _create_t_footprint(width: float, depth: float) -> PackedVector2Array:
    var w_top = width * 0.8
    var w_stem = width * 0.4
    var d_top = depth * 0.3
    var d_stem = depth * 0.7

    var points = PackedVector2Array()
    # Top bar of T
    points.push_back(Vector2(-w_top/2, -depth/2))
    points.push_back(Vector2(w_top/2, -depth/2))
    points.push_back(Vector2(w_top/2, -depth/2 + d_top))
    # Right side of stem
    points.push_back(Vector2(w_stem/2, -depth/2 + d_top))
    points.push_back(Vector2(w_stem/2, depth/2))
    # Bottom of stem
    points.push_back(Vector2(-w_stem/2, depth/2))
    points.push_back(Vector2(-w_stem/2, -depth/2 + d_top))
    # Left side of top bar
    points.push_back(Vector2(-w_top/2, -depth/2 + d_top))
    return points

func _create_u_footprint(width: float, depth: float) -> PackedVector2Array:
    var outer_width = width
    var outer_depth = depth
    var inner_width = width * 0.5
    var inner_depth = depth * 0.5
    var wall_thickness = width * 0.15

    var points = PackedVector2Array()
    # Outer rectangle clockwise
    points.push_back(Vector2(-outer_width/2, -outer_depth/2))
    points.push_back(Vector2(outer_width/2, -outer_depth/2))
    points.push_back(Vector2(outer_width/2, outer_depth/2))
    points.push_back(Vector2(-outer_width/2, outer_depth/2))

    # Cut out inner courtyard (go counter-clockwise for hole)
    points.push_back(Vector2(-outer_width/2, outer_depth/2 - wall_thickness))
    points.push_back(Vector2(-outer_width/2 + wall_thickness, outer_depth/2 - wall_thickness))
    points.push_back(Vector2(-outer_width/2 + wall_thickness, -outer_depth/2 + inner_depth))
    points.push_back(Vector2(outer_width/2 - wall_thickness, -outer_depth/2 + inner_depth))
    points.push_back(Vector2(outer_width/2 - wall_thickness, outer_depth/2 - wall_thickness))
    points.push_back(Vector2(outer_width/2, outer_depth/2 - wall_thickness))

    return points