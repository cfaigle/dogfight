@tool
class_name BuildingParametricSystem
extends Resource

# CORE PARAMETRIC BUILDING SYSTEM
# Creates infinite building variety from mathematical parameters and style rules
# Author: Claude AI Assistant
# Version: 1.0

signal building_generated(building_type: String, mesh: Mesh, materials: Array[Material])

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
    "mansard": {"pitch": 45.0, "overhang": 0.4}
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
    }
}

func create_parametric_building(
    building_type: String,
    style: String = "ww2_european",
    width: float = 10.0,
    depth: float = 8.0,
    height: float = 12.0,
    floors: int = 1,
    quality_level: int = 2
) -> Mesh:
    
    print("🏗 Creating parametric building: ", building_type, " in ", style, " style")
    
    # Create building surface mesh
    var st := SurfaceTool.new()
    
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
    
    # Extrude to create walls
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    var wall_profile = wall_profiles[style_rules[style]["wall_profiles"][0]]
    var wall_height = height * wall_profile["height_variation"]
    var wall_thickness = wall_profile["thickness"]
    
    # Create walls by extruding footprint
    for i in range(footprint.size()):
        var current = footprint[i]
        var next = footprint[(i + 1) % footprint.size()]
        
        # Create wall segment
        var wall_normal = Vector3.UP.cross(Vector3(next.x - current.x, 0.0, next.y - current.y))
        
        st.add_vertex(Vector3(current.x, 0.0, current.y))
        st.add_vertex(Vector3(next.x, 0.0, next.y))
        st.add_vertex(Vector3(current.x, wall_height, current.y))
        st.add_vertex(Vector3(next.x, wall_height, next.y))
        
        # Add normal for lighting
        st.set_normal(wall_normal)
    
    # Create roof
    var roof_system = roof_systems[style_rules[style]["roof_systems"][0]]
    _create_roof(st, width, depth, height, roof_system)
    
    # Generate windows based on style
    var window_system = window_systems[style_rules[style]["window_systems"][0]]
    _create_windows(st, width, height, floors, window_system)
    
    # Generate doors
    _create_doors(st, width, height, floors)
    
    # Apply details based on quality level
    var detail_system = detail_systems[["minimal", "subtle", "ornate"][clamp(quality_level, 0, 2)]]
    _apply_details(st, detail_system)
    
    st.end()
    
    var mesh = st.commit()
    emit_signal("building_generated", building_type, mesh, [])
    
    return mesh

func _create_residential_footprint(width: float, depth: float, floors: int) -> PackedVector2Array:
    # Generate L-shaped or rectangular residential footprint
    var points = PackedVector2Array()
    
    # Simple rectangular footprint for now
    points.push_back(Vector2(-width/2, -depth/2))
    points.push_back(Vector2(width/2, -depth/2))
    points.push_back(Vector2(width/2, depth/2))
    points.push_back(Vector2(-width/2, depth/2))
    
    return points

func _create_commercial_footprint(width: float, depth: float, floors: int) -> PackedVector2Array:
    # Generate commercial footprint with storefront potential
    var points = PackedVector2Array()
    
    # Commercial building with potential display windows
    points.push_back(Vector2(-width/2, -depth/2))
    points.push_back(Vector2(width/2, -depth/2))
    points.push_back(Vector2(width/2, depth/2))
    points.push_back(Vector2(-width/2, depth/2))
    
    return points

func _create_industrial_footprint(width: float, depth: float, floors: int) -> PackedVector2Array:
    # Generate industrial footprint with loading considerations
    var points = PackedVector2Array()
    
    # Industrial building - often rectangular for efficiency
    points.push_back(Vector2(-width/2, -depth/2))
    points.push_back(Vector2(width/2, -depth/2))
    points.push_back(Vector2(width/2, depth/2))
    points.push_back(Vector2(-width/2, depth/2))
    
    return points

func _create_default_footprint(width: float, depth: float) -> PackedVector2Array:
    # Simple rectangular footprint fallback
    var points = PackedVector2Array()
    
    points.push_back(Vector2(-width/2, -depth/2))
    points.push_back(Vector2(width/2, -depth/2))
    points.push_back(Vector2(width/2, depth/2))
    points.push_back(Vector2(-width/2, depth/2))
    
    return points

func _create_roof(st: SurfaceTool, width: float, depth: float, height: float, roof_system: Dictionary):
    # Create roof geometry based on roof system
    var pitch = roof_system["pitch"]
    var overhang = roof_system["overhang"]
    
    if pitch == 0.0:
        # Flat roof
        _create_flat_roof(st, width, depth, height, overhang)
    else:
        # Pitched roof
        _create_pitched_roof(st, width, depth, height, pitch, overhang)

func _create_flat_roof(st: SurfaceTool, width: float, depth: float, height: float, overhang: float):
    # Create flat roof with optional overhang
    var roof_height = height + overhang
    
    # Roof corners
    var corners = [
        Vector3(-width/2 - overhang, roof_height, -depth/2 - overhang),
        Vector3(width/2 + overhang, roof_height, -depth/2 - overhang),
        Vector3(width/2 + overhang, roof_height, depth/2 + overhang),
        Vector3(-width/2 - overhang, roof_height, depth/2 + overhang)
    ]
    
    # Create roof mesh
    st.add_triangle_fan(corners[0], corners[2], corners[1])
    st.add_triangle_fan(corners[1], corners[3], corners[2])
    st.add_triangle_fan(corners[2], corners[0], corners[3])
    st.add_triangle_fan(corners[3], corners[0], corners[1])

func _create_pitched_roof(st: SurfaceTool, width: float, depth: float, height: float, pitch: float, overhang: float):
    # Create pitched roof with ridge beam
    var roof_height = height + overhang
    var ridge_height = roof_height + (width / 2) * sin(deg_to_rad(pitch))
    
    # Roof vertices
    var front_left = Vector3(-width/2, ridge_height, -depth/2 - overhang)
    var front_right = Vector3(width/2, ridge_height, -depth/2 - overhang)
    var back_left = Vector3(-width/2, ridge_height, depth/2 + overhang)
    var back_right = Vector3(width/2, ridge_height, depth/2 + overhang)
    var top_center = Vector3(0.0, ridge_height + 2.0, 0.0)
    
    # Create roof surface
    st.add_quad(front_left, front_right, back_right, back_left)
    st.add_quad(back_left, back_right, top_center, front_left)
    st.add_quad(front_right, top_center, back_left, back_right)

func _create_windows(st: SurfaceTool, width: float, height: float, floors: int, window_system: Dictionary):
    # Generate windows based on building parameters
    var window_style = window_system["style"]
    var window_proportion = window_system["proportion"]
    var window_count = int(width * window_proportion / 2.0)  # Windows per side
    
func _create_square_window(st: SurfaceTool, width: float, y: float, height: float, window_width: float, side: String):
    # Create square window opening
    var depth = 0.1
    
    # Calculate window position based on side
    var x_pos = 0.0
    if side == "left":
        x_pos = -width/2 + depth
    elif side == "right":
        x_pos = width/2 - depth
    
    # Create window frame
    var window_bottom = Vector3(x_pos, y, -depth/2)
    var window_top = Vector3(x_pos, y + height, -depth/2)
    
    # Window vertices
    if side == "left" or side == "right":
        var left = Vector3(x_pos - depth, y, -height/2)
        var right = Vector3(x_pos, y + height/2, -height/2)
        st.add_quad(left, right, right, left)
    else:
        var left = Vector3(x_pos, y - height/2, -depth/2)
        var right = Vector3(x_pos, y - height/2, -depth/2)
        st.add_quad(left, right, right, left)

func _create_arched_window(st: SurfaceTool, width: float, y: float, height: float, window_width: float, side: String):
    # Create arched window opening
    var depth = 0.15
    var arch_height = height * 0.4
    
    # Calculate window position
    var x_pos = 0.0
    if side == "left":
        x_pos = -width/2 + depth
    elif side == "right":
        x_pos = width/2 - depth
    
    # Create arch frame
    var window_bottom = Vector3(x_pos - depth, y + height * 0.3, -depth/2)
    var arch_top = Vector3(x_pos, y + height * 0.7, -depth/2)
    
    # Arch vertices
    if side == "left" or side == "right":
        var left = Vector3(x_pos - depth - 0.2, y - height/2, -depth/2)
        var right = Vector3(x_pos, y + height * 0.9, -depth/2)
        st.add_quad(left, right, right, left)
    else:
        var left = Vector3(x_pos - depth - 0.2, y - height/2, -depth/2)
        var right = Vector3(x_pos - depth - 0.2, y + height * 0.9, -depth/2)
        st.add_quad(left, right, right, left)

func _create_doors(st: SurfaceTool, width: float, height: float, floors: int):
    # Generate doorways for buildings
    var door_width = width * 0.3
    var door_height = height * 0.7
    
    # Create doors on different floors
    for floor in range(floors):
        var door_y = floor * height + 0.1
        
        # Main entrance door
        var door_x = 0.0
        st.add_quad(
            Vector3(door_x - door_width/2, door_y, -0.15),
            Vector3(door_x + door_width/2, door_y, -0.15),
            Vector3(door_x + door_width/2, door_y + door_height, -0.15),
            Vector3(door_x - door_width/2, door_y + door_height, -0.15)
        )



func _apply_details(st: SurfaceTool, detail_system: Dictionary):
    # Apply architectural details based on quality level
    var intensity = detail_system["intensity"]
    var scale = detail_system["scale"]
    
    # Generate decorative details
    for i in range(int(intensity * 5)):
        # Add cornices, brackets, or other details
        pass