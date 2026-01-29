class_name LighthouseGeometry
extends RefCounted

## Creates a proper lighthouse geometry with tapered tower, lantern room, and gallery

static func create(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Lighthouse specifications
    var base_radius: float = max(plot.lot_width * 0.25, 3.0)  # Base radius
    var top_radius: float = base_radius * 0.6  # Tapered but not too much
    var tower_height: float = rng.randf_range(25.0, 45.0)  # Tall enough to be distinctive
    var lamp_house_height: float = 4.0  # Lantern room height
    var gallery_overhang: float = 0.8  # How far gallery extends from tower
    
    var sides: int = 16  # More sides for smoother appearance
    var base_y: float = 0.0
    var tower_top_y: float = tower_height
    var lamp_house_top_y: float = tower_top_y + lamp_house_height

    # Create main tapered tower with proper normals
    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        # Calculate radii at bottom and top of this segment
        var x1_bot: float = cos(angle1) * base_radius
        var z1_bot: float = sin(angle1) * base_radius
        var x2_bot: float = cos(angle2) * base_radius
        var z2_bot: float = sin(angle2) * base_radius
        
        var x1_top: float = cos(angle1) * top_radius
        var z1_top: float = sin(angle1) * top_radius
        var x2_top: float = cos(angle2) * top_radius
        var z2_top: float = sin(angle2) * top_radius

        # Define vertices
        var v0 := Vector3(x1_bot, base_y, z1_bot)  # Bottom left
        var v1 := Vector3(x2_bot, base_y, z2_bot)  # Bottom right
        var v2 := Vector3(x2_top, tower_top_y, z2_top)  # Top right
        var v3 := Vector3(x1_top, tower_top_y, z1_top)  # Top left

        # Add face with proper winding (counter-clockwise for outward normals)
        # Triangle 1: v0-v1-v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Create lantern room (the glass-enclosed light chamber at the top)
    var lamp_house_radius: float = top_radius * 0.9  # Slightly smaller than tower top

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        # Lantern room walls
        var x1: float = cos(angle1) * lamp_house_radius
        var z1: float = sin(angle1) * lamp_house_radius
        var x2: float = cos(angle2) * lamp_house_radius
        var z2: float = sin(angle2) * lamp_house_radius

        var v0 := Vector3(x1, tower_top_y, z1)
        var v1 := Vector3(x2, tower_top_y, z2)
        var v2 := Vector3(x2, lamp_house_top_y, z2)
        var v3 := Vector3(x1, lamp_house_top_y, z1)

        # Add lantern room walls with proper winding
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Create domed top of lantern room
    var dome_segments: int = 6
    var dome_radius: float = lamp_house_radius * 0.95

    for seg in range(dome_segments):
        var y1: float = tower_top_y + (float(seg) / float(dome_segments)) * lamp_house_height * 0.8
        var y2: float = tower_top_y + (float(seg + 1) / float(dome_segments)) * lamp_house_height * 0.8
        
        var r1: float = lerp(dome_radius, 0.0, float(seg) / float(dome_segments))
        var r2: float = lerp(dome_radius, 0.0, float(seg + 1) / float(dome_segments))

        for i in range(sides):
            var angle1: float = (float(i) / float(sides)) * TAU
            var angle2: float = (float(i + 1) / float(sides)) * TAU

            var x1_1: float = cos(angle1) * r1
            var z1_1: float = sin(angle1) * r1
            var x1_2: float = cos(angle1) * r2
            var z1_2: float = sin(angle1) * r2
            var x2_1: float = cos(angle2) * r1
            var z2_1: float = sin(angle2) * r1
            var x2_2: float = cos(angle2) * r2
            var z2_2: float = sin(angle2) * r2

            var v1 := Vector3(x1_1, y1, z1_1)
            var v2 := Vector3(x2_1, y1, z2_1)
            var v3 := Vector3(x2_2, y2, z2_2)
            var v4 := Vector3(x1_2, y2, z1_2)

            # Add dome segment face with proper winding
            st.add_vertex(v1)
            st.add_vertex(v2)
            st.add_vertex(v3)

            st.add_vertex(v1)
            st.add_vertex(v3)
            st.add_vertex(v4)

    # Create observation gallery (the walkway around the lantern room)
    var gallery_start_y: float = tower_top_y + lamp_house_height * 0.3  # Positioned partway up lantern room
    var inner_radius: float = top_radius * 1.05  # Slightly larger than tower
    var outer_radius: float = inner_radius + gallery_overhang
    var gallery_height: float = 0.1  # Thin platform
    var rail_height: float = 1.1  # Standard railing height

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        # Inner circle points
        var ix1: float = cos(angle1) * inner_radius
        var iz1: float = sin(angle1) * inner_radius
        var ix2: float = cos(angle2) * inner_radius
        var iz2: float = sin(angle2) * inner_radius

        # Outer circle points
        var ox1: float = cos(angle1) * outer_radius
        var oz1: float = sin(angle1) * outer_radius
        var ox2: float = cos(angle2) * outer_radius
        var oz2: float = sin(angle2) * outer_radius

        # Gallery floor (at gallery_start_y)
        var floor_y: float = gallery_start_y
        var railing_y: float = floor_y + rail_height

        var iv0 := Vector3(ix1, floor_y, iz1)
        var iv1 := Vector3(ix2, floor_y, iz2)
        var ov0 := Vector3(ox1, floor_y, oz1)
        var ov1 := Vector3(ox2, floor_y, oz2)

        # Gallery floor surface (normal pointing down)
        st.add_vertex(iv0)
        st.add_vertex(ov1)
        st.add_vertex(ov0)

        st.add_vertex(iv0)
        st.add_vertex(iv1)
        st.add_vertex(ov1)

        # Gallery railing posts (simple vertical cylinders)
        var post_height: float = rail_height
        var post_radius: float = 0.08

        # Create small post at corner
        for j in range(8):  # 8-sided post
            var p_angle1: float = (float(j) / 8.0) * TAU
            var p_angle2: float = (float(j + 1) / 8.0) * TAU

            var px1: float = cos(p_angle1) * post_radius
            var pz1: float = sin(p_angle1) * post_radius
            var px2: float = cos(p_angle2) * post_radius
            var pz2: float = sin(p_angle2) * post_radius

            var post_v0 := Vector3(ox1 + px1, floor_y, oz1 + pz1)
            var post_v1 := Vector3(ox1 + px2, floor_y, oz1 + pz2)
            var post_v2 := Vector3(ox1 + px2, railing_y, oz1 + pz2)
            var post_v3 := Vector3(ox1 + px1, railing_y, oz1 + pz1)

            # Post face with proper winding
            st.add_vertex(post_v0)
            st.add_vertex(post_v1)
            st.add_vertex(post_v2)

            st.add_vertex(post_v0)
            st.add_vertex(post_v2)
            st.add_vertex(post_v3)

    st.generate_normals()
    var mesh := st.commit()

    # Apply lighthouse-appropriate material (white with some gray accents)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.98, 0.98, 0.95)  # Bright white
    mat.roughness = 0.85
    mesh.surface_set_material(0, mat)

    return mesh