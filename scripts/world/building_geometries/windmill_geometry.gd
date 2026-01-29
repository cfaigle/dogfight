class_name WindmillGeometry
extends RefCounted

## Creates a proper windmill geometry with cylindrical base and rotating blades

static func create(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Windmill specifications
    var base_radius: float = max(plot.lot_width * 0.35, 4.0)  # Wider base for stability
    var top_radius: float = base_radius * 0.8  # Slightly smaller at top
    var tower_height: float = rng.randf_range(15.0, 25.0)
    var shaft_height: float = 3.0  # Height of the bearing shaft
    var cap_height: float = 2.5  # Conical cap height
    
    var sides: int = 16  # More sides for smoother appearance
    var base_y: float = 0.0
    var tower_top_y: float = tower_height
    
    # Create cylindrical base/tower
    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU
        
        var x1: float = cos(angle1) * base_radius
        var z1: float = sin(angle1) * base_radius
        var x2: float = cos(angle2) * base_radius
        var z2: float = sin(angle2) * base_radius
        
        # Define vertices for this wall segment
        var v0 := Vector3(x1, base_y, z1)  # Bottom left
        var v1 := Vector3(x2, base_y, z2)  # Bottom right
        var v2 := Vector3(x2, tower_top_y, z2)  # Top right
        var v3 := Vector3(x1, tower_top_y, z1)  # Top left
        
        # Add two triangles to form the quad (counter-clockwise for outside-facing normals)
        # Triangle 1: v0-v1-v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)
        
        # Triangle 2: v0-v2-v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Create conical cap/roof on top of base
    var cap_radius: float = base_radius * 0.7  # Slightly smaller than base
    var cap_base_y: float = tower_top_y
    var cap_top_y: float = cap_base_y + cap_height

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU
        
        var x1: float = cos(angle1) * base_radius
        var z1: float = sin(angle1) * base_radius
        var x2: float = cos(angle2) * base_radius
        var z2: float = sin(angle2) * base_radius
        
        # Define vertices for the conical roof (from base edge to peak)
        var base_v1 := Vector3(x1, cap_base_y, z1)
        var base_v2 := Vector3(x2, cap_base_y, z2)
        var peak := Vector3(0, cap_top_y, 0)

        # Triangle forming the roof face
        st.add_vertex(peak)  # Pointing up from base to peak
        st.add_vertex(base_v2)
        st.add_vertex(base_v1)

    # Create windmill shaft (the rotating part that holds the sails)
    var shaft_radius: float = base_radius * 0.3
    var shaft_y: float = cap_top_y
    var shaft_top_y: float = shaft_y + shaft_height

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU
        
        var x1: float = cos(angle1) * shaft_radius
        var z1: float = sin(angle1) * shaft_radius
        var x2: float = cos(angle2) * shaft_radius
        var z2: float = sin(angle2) * shaft_radius
        
        var v0 := Vector3(x1, shaft_y, z1)
        var v1 := Vector3(x2, shaft_y, z2)
        var v2 := Vector3(x2, shaft_top_y, z2)
        var v3 := Vector3(x1, shaft_top_y, z1)
        
        # Add shaft wall
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)
        
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Create windmill sails (blades that catch the wind)
    # Real windmills have 4 sails arranged in a cross pattern, perpendicular to the ground
    var sail_length: float = base_radius * 2.0  # Long enough to be visible
    var sail_width: float = 0.6  # Thickness of the sail
    var sail_height: float = 0.3  # Height of the sail cross-section
    var sail_center_y: float = shaft_top_y + shaft_height * 0.5  # Center of the shaft

    # Create 4 sails in a cross pattern (perpendicular to ground, radiating from center)
    for sail_idx in range(4):
        var sail_angle: float = (float(sail_idx) / 4.0) * TAU  # 0°, 90°, 180°, 270°

        # Calculate perpendicular direction for sail thickness
        var perp_angle: float = sail_angle + PI/2
        var half_width: float = sail_width * 0.5
        var half_height: float = sail_height * 0.5

        # Create a rectangular sail volume
        # Center of the sail
        var center_x: float = 0.0
        var center_y: float = sail_center_y
        var center_z: float = 0.0

        # End points of the sail (extending from center in the sail_angle direction)
        var end_x: float = cos(sail_angle) * sail_length * 0.5
        var end_z: float = sin(sail_angle) * sail_length * 0.5

        # Start point (opposite end of the sail)
        var start_x: float = -end_x
        var start_z: float = -end_z

        # Create sail as a rectangular prism
        # Four corners at start position
        var start_tl := Vector3(center_x + start_x + cos(perp_angle) * half_width, center_y + half_height, center_z + start_z + sin(perp_angle) * half_width)  # Top-left
        var start_tr := Vector3(center_x + start_x - cos(perp_angle) * half_width, center_y + half_height, center_z + start_z - sin(perp_angle) * half_width)  # Top-right
        var start_bl := Vector3(center_x + start_x + cos(perp_angle) * half_width, center_y - half_height, center_z + start_z + sin(perp_angle) * half_width)  # Bottom-left
        var start_br := Vector3(center_x + start_x - cos(perp_angle) * half_width, center_y - half_height, center_z + start_z - sin(perp_angle) * half_width)  # Bottom-right

        # Four corners at end position
        var end_tl := Vector3(center_x + end_x + cos(perp_angle) * half_width, center_y + half_height, center_z + end_z + sin(perp_angle) * half_width)  # Top-left
        var end_tr := Vector3(center_x + end_x - cos(perp_angle) * half_width, center_y + half_height, center_z + end_z - sin(perp_angle) * half_width)  # Top-right
        var end_bl := Vector3(center_x + end_x + cos(perp_angle) * half_width, center_y - half_height, center_z + end_z + sin(perp_angle) * half_width)  # Bottom-left
        var end_br := Vector3(center_x + end_x - cos(perp_angle) * half_width, center_y - half_height, center_z + end_z - sin(perp_angle) * half_width)  # Bottom-right

        # Create sail faces with proper normals (outward-facing)
        # Start face (facing inward toward center) - counter-clockwise for outward normals
        st.add_vertex(start_tl)
        st.add_vertex(start_br)  # Swapped to reverse normal
        st.add_vertex(start_bl)

        st.add_vertex(start_tl)
        st.add_vertex(start_tr)  # Swapped to reverse normal
        st.add_vertex(start_br)

        # End face (facing outward from center) - counter-clockwise for outward normals
        st.add_vertex(end_tr)
        st.add_vertex(end_bl)  # Swapped to reverse normal
        st.add_vertex(end_br)

        st.add_vertex(end_tr)
        st.add_vertex(end_tl)  # Swapped to reverse normal
        st.add_vertex(end_bl)

        # Top face - counter-clockwise for upward normals
        st.add_vertex(start_tl)
        st.add_vertex(start_tr)
        st.add_vertex(end_tr)

        st.add_vertex(start_tl)
        st.add_vertex(end_tr)
        st.add_vertex(end_tl)

        # Bottom face - counter-clockwise for downward normals
        st.add_vertex(start_bl)
        st.add_vertex(end_bl)
        st.add_vertex(end_br)

        st.add_vertex(start_bl)
        st.add_vertex(end_br)
        st.add_vertex(start_br)

        # Side faces - making sure normals face outward
        # Side 1 (facing in direction of sail)
        st.add_vertex(start_bl)
        st.add_vertex(end_bl)
        st.add_vertex(end_tl)

        st.add_vertex(start_bl)
        st.add_vertex(end_tl)
        st.add_vertex(start_tl)

        # Side 2 (opposite side of sail)
        st.add_vertex(start_br)
        st.add_vertex(start_tr)
        st.add_vertex(end_tr)

        st.add_vertex(start_br)
        st.add_vertex(end_tr)
        st.add_vertex(end_br)

    # Generate normals automatically and finalize mesh
    st.generate_normals()
    var mesh := st.commit()

    # Apply windmill-appropriate material (traditional pale colors)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.9, 0.85, 0.75)  # Light beige/white for traditional windmill
    mat.roughness = 0.85
    mat.metallic = 0.05
    mesh.surface_set_material(0, mat)

    return mesh