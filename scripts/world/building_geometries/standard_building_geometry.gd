class_name StandardBuildingGeometry
extends RefCounted

## Creates standard building geometry with proper normals and architectural details

static func create(plot: Dictionary, building_type: String, style: String, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Building specifications based on type and plot
    var width: float = max(plot.lot_width * 0.8, 4.0)
    var depth: float = max(plot.lot_depth * 0.8, 4.0)
    var height: float = _calculate_building_height(building_type, rng)
    var floors: int = max(1, int(height / 4.0))

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var top_y: float = height

    # Main building structure
    var corners := [
        Vector3(-hw, base_y, -hd),  # 0: back-left-bottom
        Vector3(hw, base_y, -hd),   # 1: back-right-bottom
        Vector3(hw, base_y, hd),    # 2: front-right-bottom
        Vector3(-hw, base_y, hd),   # 3: front-left-bottom
        Vector3(-hw, top_y, -hd),   # 4: back-left-top
        Vector3(hw, top_y, -hd),    # 5: back-right-top
        Vector3(hw, top_y, hd),     # 6: front-right-top
        Vector3(-hw, top_y, hd),    # 7: front-left-top
    ]

    # Define faces with proper winding order for outward normals (counter-clockwise when viewed from outside)
    var faces := [
        # Front face: 3(bottom-left), 2(bottom-right), 6(top-right), 7(top-left)
        [3, 2, 6, 7],  # front - facing +Z
        # Back face: 1(bottom-right), 0(bottom-left), 4(top-left), 5(top-right)
        [1, 0, 4, 5],  # back - facing -Z
        # Left face: 0(bottom-back), 3(bottom-front), 7(top-front), 4(top-back)
        [0, 3, 7, 4],  # left - facing -X
        # Right face: 2(bottom-front), 1(bottom-back), 5(top-back), 6(top-front)
        [2, 1, 5, 6],  # right - facing +X
    ]

    for face in faces:
        var v0 = corners[face[0]]
        var v1 = corners[face[1]]
        var v2 = corners[face[2]]
        var v3 = corners[face[3]]

        # Triangle 1: v0-v1-v2 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Bottom face (normal pointing down)
    st.add_vertex(corners[1])  # back-right-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(corners[3])  # front-left-bottom

    st.add_vertex(corners[1])  # back-right-bottom
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[2])  # front-right-bottom

    # Roof based on building style
    var roof_mesh: ArrayMesh = _create_roof_for_style(corners, building_type, style, rng)
    if roof_mesh != null:
        # We need to manually add the roof geometry to our surface tool
        _add_roof_geometry(st, corners, building_type, style, rng)
    else:
        # Flat roof as default
        st.add_vertex(corners[4])  # back-left-top
        st.add_vertex(corners[7])  # front-left-top
        st.add_vertex(corners[6])  # front-right-top

        st.add_vertex(corners[4])  # back-left-top
        st.add_vertex(corners[6])  # front-right-top
        st.add_vertex(corners[5])  # back-right-top

    # Add architectural details based on style
    _add_architectural_details(st, corners, building_type, style, rng)

    st.generate_normals()
    var mesh := st.commit()

    # Apply material based on building style
    var mat := _create_material_for_style(style)
    mesh.surface_set_material(0, mat)

    return mesh

# Calculate building height based on type
static func _calculate_building_height(building_type: String, rng: RandomNumberGenerator) -> float:
    match building_type:
        "city", "urban":
            return rng.randf_range(18.0, 36.0)  # Tall buildings
        "town", "suburban":
            return rng.randf_range(9.0, 15.0)   # Medium buildings
        "hamlet", "rural":
            return rng.randf_range(3.0, 6.0)    # Low buildings
        "industrial":
            return rng.randf_range(12.0, 20.0)  # Industrial buildings
        _:
            return rng.randf_range(6.0, 12.0)   # Default

# Create roof based on architectural style
static func _create_roof_for_style(corners: Array, building_type: String, style: String, rng: RandomNumberGenerator) -> ArrayMesh:
    # This is a placeholder - in a real implementation, this would return a specific roof mesh
    # For now, we'll handle roof creation directly in the main function
    return null

# Add roof geometry based on style
static func _add_roof_geometry(st: SurfaceTool, corners: Array, building_type: String, style: String, rng: RandomNumberGenerator) -> void:
    var hw: float = abs(corners[0].x)  # half-width
    var hd: float = abs(corners[0].z)  # half-depth
    var top_y: float = corners[4].y  # top height

    match style:
        "gable", "gabled", "traditional", "medieval", "cottage", "house", "hamlet":
            # Gable roof (triangular front/back faces)
            var roof_peak_y: float = top_y + max(hw, hd) * 0.3  # Peak height based on building size

            # Front gable
            var front_center_top = Vector3(0, roof_peak_y, hd)
            var front_bottom_left = Vector3(-hw, top_y, hd)
            var front_bottom_right = Vector3(hw, top_y, hd)

            st.add_vertex(front_bottom_left)
            st.add_vertex(front_bottom_right)
            st.add_vertex(front_center_top)

            # Back gable
            var back_center_top = Vector3(0, roof_peak_y, -hd)
            var back_bottom_left = Vector3(-hw, top_y, -hd)
            var back_bottom_right = Vector3(hw, top_y, -hd)

            st.add_vertex(back_bottom_right)
            st.add_vertex(back_bottom_left)
            st.add_vertex(back_center_top)

            # Roof slopes
            # Left slope - ensure counter-clockwise winding for outward normals
            st.add_vertex(front_bottom_left)
            st.add_vertex(back_bottom_left)
            st.add_vertex(back_center_top)

            st.add_vertex(front_bottom_left)
            st.add_vertex(back_center_top)
            st.add_vertex(front_center_top)

            # Right slope - ensure counter-clockwise winding for outward normals
            st.add_vertex(front_bottom_right)
            st.add_vertex(front_center_top)
            st.add_vertex(back_center_top)

            st.add_vertex(front_bottom_right)
            st.add_vertex(back_center_top)
            st.add_vertex(back_bottom_right)

        "hip", "hipped", "modern", "city", "urban":
            # Hip roof (all sides slope to a point)
            var roof_peak_y: float = top_y + min(hw, hd) * 0.4  # Peak height

            var peak = Vector3(0, roof_peak_y, 0)

            # Four roof faces
            st.add_vertex(corners[4])  # back-left
            st.add_vertex(corners[5])  # back-right
            st.add_vertex(peak)

            st.add_vertex(corners[5])  # back-right
            st.add_vertex(corners[6])  # front-right
            st.add_vertex(peak)

            st.add_vertex(corners[6])  # front-right
            st.add_vertex(corners[7])  # front-left
            st.add_vertex(peak)

            st.add_vertex(corners[7])  # front-left
            st.add_vertex(corners[4])  # back-left
            st.add_vertex(peak)

        "flat", "industrial", "commercial":
            # Already handled with flat roof in main function
            pass
        _:
            # Default to flat roof
            st.add_vertex(corners[4])  # back-left-top
            st.add_vertex(corners[7])  # front-left-top
            st.add_vertex(corners[6])  # front-right-top

            st.add_vertex(corners[4])  # back-left-top
            st.add_vertex(corners[6])  # front-right-top
            st.add_vertex(corners[5])  # back-right-top

# Add architectural details based on style
static func _add_architectural_details(st: SurfaceTool, corners: Array, building_type: String, style: String, rng: RandomNumberGenerator) -> void:
    # Add windows, doors, and other details based on style
    var hw: float = abs(corners[0].x)
    var hd: float = abs(corners[0].z)
    var height: float = corners[4].y - corners[0].y
    var base_y: float = corners[0].y
    var top_y: float = corners[4].y

    # Add windows based on building type and style
    var window_spacing: float = 3.0
    var window_width: float = 1.2
    var window_height: float = 1.6
    var window_depth: float = 0.15

    # Add windows to front and back walls
    var floor_height: float = height / max(1, int(height / 3.0))
    var floors: int = int(height / floor_height)

    for floor in range(floors):
        var floor_y: float = base_y + floor_height * floor + floor_height * 0.3

        # Front wall windows
        for wx in range(int(hw * 2.0 / window_spacing)):
            var x_pos: float = -hw + (float(wx) + 0.5) * window_spacing
            if abs(x_pos) < hw * 0.9:  # Don't place windows too close to edges
                _add_window(st, Vector3(x_pos, floor_y, hd), Vector3(window_width, window_height, window_depth), true)

        # Back wall windows
        for wx in range(int(hw * 2.0 / window_spacing)):
            var x_pos: float = -hw + (float(wx) + 0.5) * window_spacing
            if abs(x_pos) < hw * 0.9:
                _add_window(st, Vector3(x_pos, floor_y, -hd), Vector3(window_width, window_height, window_depth), false)

    # Add door to front
    var door_width: float = 1.8
    var door_height: float = 2.2
    _add_door(st, Vector3(0, base_y, hd), Vector3(door_width, door_height, 0.2))

# Add a window to the building
static func _add_window(st: SurfaceTool, center: Vector3, size: Vector3, facing_front: bool) -> void:
    var hw: float = size.x * 0.5
    var hh: float = size.y * 0.5
    var hd: float = size.z * 0.5

    # Calculate orientation based on which wall
    var right: Vector3
    var up: Vector3 = Vector3.UP
    var normal: Vector3

    if facing_front:
        right = Vector3.RIGHT
        normal = Vector3.FORWARD  # Facing +Z
    else:  # back
        right = Vector3.LEFT  # Actually still right in terms of X
        normal = Vector3.BACK  # Facing -Z

    # Calculate corner positions
    var tl := center + up * hh - right * hw + normal * hd  # Top-left
    var tr := center + up * hh + right * hw + normal * hd  # Top-right
    var bl := center - up * hh - right * hw + normal * hd  # Bottom-left
    var br := center - up * hh + right * hw + normal * hd  # Bottom-right

    # Add window frame (recessed into wall)
    # Front face of frame
    st.add_vertex(bl)
    st.add_vertex(br)
    st.add_vertex(tr)

    st.add_vertex(bl)
    st.add_vertex(tr)
    st.add_vertex(tl)

    # Add glass pane (slightly recessed)
    var glass_tl := tl - normal * hd * 0.8
    var glass_tr := tr - normal * hd * 0.8
    var glass_bl := bl - normal * hd * 0.8
    var glass_br := br - normal * hd * 0.8

    # Glass facing outward
    st.add_vertex(glass_bl)
    st.add_vertex(glass_br)
    st.add_vertex(glass_tr)

    st.add_vertex(glass_bl)
    st.add_vertex(glass_tr)
    st.add_vertex(glass_tl)

# Add a door to the building
static func _add_door(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
    var hw: float = size.x * 0.5
    var hh: float = size.y * 0.5
    var hd: float = size.z * 0.5

    var right: Vector3 = Vector3.RIGHT
    var up: Vector3 = Vector3.UP
    var normal: Vector3 = Vector3.FORWARD  # Facing +Z

    # Calculate corner positions
    var tl := center + up * hh - right * hw + normal * hd  # Top-left
    var tr := center + up * hh + right * hw + normal * hd  # Top-right
    var bl := center - up * hh - right * hw + normal * hd  # Bottom-left
    var br := center - up * hh + right * hw + normal * hd  # Bottom-right

    # Door facing outward (counter-clockwise when viewed from outside)
    st.add_vertex(bl)
    st.add_vertex(br)
    st.add_vertex(tr)

    st.add_vertex(bl)
    st.add_vertex(tr)
    st.add_vertex(tl)

# Create material based on architectural style
static func _create_material_for_style(style: String) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    
    match style:
        "industrial", "factory", "warehouse":
            mat.albedo_color = Color(0.4, 0.4, 0.45)  # Industrial gray
            mat.roughness = 0.9
        "modern", "contemporary", "city":
            mat.albedo_color = Color(0.7, 0.75, 0.8)  # Light blue-gray
            mat.roughness = 0.7
        "traditional", "cottage", "rural", "hamlet":
            mat.albedo_color = Color(0.85, 0.75, 0.6)  # Warm earth tones
            mat.roughness = 0.85
        "medieval", "stone", "castle":
            mat.albedo_color = Color(0.5, 0.5, 0.55)  # Stone gray
            mat.roughness = 0.95
        "victorian", "art_deco", "urban":
            mat.albedo_color = Color(0.8, 0.7, 0.65)  # Victorian colors
            mat.roughness = 0.8
        _:
            mat.albedo_color = Color(0.7, 0.7, 0.75)  # Default neutral
            mat.roughness = 0.85

    return mat