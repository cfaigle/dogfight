class_name RadioTowerGeometry
extends RefCounted

## Creates a radio tower geometry with a tall mast and antenna elements

static func create(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Radio tower specifications
    var base_radius: float = max(plot.lot_width * 0.2, 2.0)  # Narrower base for tower
    var tower_height: float = rng.randf_range(30.0, 60.0)  # Much taller than windmill
    var tower_top_y: float = tower_height
    
    # Create main tower mast (tall cylindrical structure)
    var sides: int = 8  # Fewer sides for more angular tower look
    var base_y: float = 0.0

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

    # Create antenna array at the top of the tower
    var antenna_radius: float = base_radius * 2.0  # Wider antenna spread
    var antenna_height: float = 5.0  # Antenna extension height
    var antenna_base_y: float = tower_top_y
    var antenna_top_y: float = antenna_base_y + antenna_height

    # Create radial antenna elements extending from the top
    var num_antennas: int = 6  # Number of antenna elements
    for i in range(num_antennas):
        var angle: float = (float(i) / float(num_antennas)) * TAU
        
        # Calculate antenna direction
        var ant_x: float = cos(angle) * antenna_radius
        var ant_z: float = sin(angle) * antenna_radius
        
        # Create a thin antenna beam
        var beam_width: float = 0.3
        var beam_depth: float = 0.1
        
        # Calculate perpendicular direction for the beam
        var perp_x: float = -sin(angle) * beam_width * 0.5
        var perp_z: float = cos(angle) * beam_width * 0.5
        
        # Create antenna beam as a thin rectangular prism
        var start_pos := Vector3(0, antenna_base_y, 0)  # Start from center top of tower
        var end_pos := Vector3(ant_x, antenna_top_y, ant_z)  # End at outer position
        
        # Create four corners at start position
        var start_tl := Vector3(start_pos.x + perp_x, start_pos.y, start_pos.z + perp_z)  # Top-left
        var start_tr := Vector3(start_pos.x - perp_x, start_pos.y, start_pos.z - perp_z)  # Top-right
        var start_bl := Vector3(start_pos.x + perp_x, start_pos.y - beam_depth, start_pos.z + perp_z)  # Bottom-left
        var start_br := Vector3(start_pos.x - perp_x, start_pos.y - beam_depth, start_pos.z - perp_z)  # Bottom-right

        # Create four corners at end position
        var end_tl := Vector3(end_pos.x + perp_x, end_pos.y, end_pos.z + perp_z)  # Top-left
        var end_tr := Vector3(end_pos.x - perp_x, end_pos.y, end_pos.z - perp_z)  # Top-right
        var end_bl := Vector3(end_pos.x + perp_x, end_pos.y - beam_depth, end_pos.z + perp_z)  # Bottom-left
        var end_br := Vector3(end_pos.x - perp_x, end_pos.y - beam_depth, end_pos.z - perp_z)  # Bottom-right

        # Create antenna beam faces with proper normals
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
        # Side 1 (facing in direction of antenna)
        st.add_vertex(start_bl)
        st.add_vertex(end_bl)
        st.add_vertex(end_tl)

        st.add_vertex(start_bl)
        st.add_vertex(end_tl)
        st.add_vertex(start_tl)

        # Side 2 (opposite side of antenna)
        st.add_vertex(start_br)
        st.add_vertex(start_tr)
        st.add_vertex(end_tr)

        st.add_vertex(start_br)
        st.add_vertex(end_tr)
        st.add_vertex(end_br)

    # Create a small platform/structure at the top of the tower
    var platform_radius: float = base_radius * 1.5
    var platform_height: float = 0.3  # Thickness of platform
    var platform_y: float = tower_top_y - 2.0  # Position slightly below antenna base
    
    # Platform structure around the tower top
    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        var px1: float = cos(angle1) * platform_radius
        var pz1: float = sin(angle1) * platform_radius
        var px2: float = cos(angle2) * platform_radius
        var pz2: float = sin(angle2) * platform_radius

        var inner_x1: float = cos(angle1) * base_radius * 1.2
        var inner_z1: float = sin(angle1) * base_radius * 1.2
        var inner_x2: float = cos(angle2) * base_radius * 1.2
        var inner_z2: float = sin(angle2) * base_radius * 1.2

        # Outer edge of platform
        var outer_v1 := Vector3(px1, platform_y, pz1)
        var outer_v2 := Vector3(px2, platform_y, pz2)
        
        # Inner edge of platform (around tower)
        var inner_v1 := Vector3(inner_x1, platform_y, inner_z1)
        var inner_v2 := Vector3(inner_x2, platform_y, inner_z2)
        
        # Top face of platform (facing up)
        st.add_vertex(outer_v1)
        st.add_vertex(outer_v2)
        st.add_vertex(inner_v2)
        
        st.add_vertex(outer_v1)
        st.add_vertex(inner_v2)
        st.add_vertex(inner_v1)

        # Bottom face of platform (facing down)
        st.add_vertex(outer_v1)
        st.add_vertex(inner_v1)
        st.add_vertex(inner_v2)
        
        st.add_vertex(outer_v1)
        st.add_vertex(inner_v2)
        st.add_vertex(outer_v2)

    # Generate normals automatically and finalize mesh
    st.generate_normals()
    var mesh := st.commit()

    # Apply radio tower-appropriate material (metallic gray)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.4, 0.45)  # Dark metallic gray
    mat.roughness = 0.6
    mat.metallic = 0.8
    mesh.surface_set_material(0, mat)

    return mesh