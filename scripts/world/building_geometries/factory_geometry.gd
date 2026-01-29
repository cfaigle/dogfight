class_name FactoryGeometry
extends RefCounted

## Creates a proper factory building geometry with industrial features

static func create(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Factory building specifications
    var width: float = max(plot.lot_width * 0.9, 8.0)  # Ensure minimum size for industrial feel
    var depth: float = max(plot.lot_depth * 0.8, 6.0)
    var height: float = rng.randf_range(10.0, 18.0)

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var top_y: float = height

    # Main factory building structure
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

    # Industrial flat roof
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[7])  # front-left-top
    st.add_vertex(corners[6])  # front-right-top

    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(corners[5])  # back-right-top

    # Add industrial features: smokestacks, vents, loading dock
    var stack_count: int = 2  # Multiple smokestacks for industrial look
    var stack_height: float = height * 1.5  # Taller than building
    var stack_width: float = 1.5

    for i in range(stack_count):
        var stack_x: float = -hw * 0.6 + (i * hw * 1.2)  # Space stacks across back
        var stack_z: float = -hd * 0.7  # Along back edge
        var stack_hw: float = stack_width * 0.5
        var stack_base_y: float = top_y
        var stack_top_y: float = stack_base_y + stack_height

        # Create rectangular smokestack
        var stack_corners := [
            Vector3(stack_x - stack_hw, stack_base_y, stack_z - stack_hw),  # 0: back-left-bottom
            Vector3(stack_x + stack_hw, stack_base_y, stack_z - stack_hw),  # 1: back-right-bottom
            Vector3(stack_x + stack_hw, stack_base_y, stack_z + stack_hw),  # 2: front-right-bottom
            Vector3(stack_x - stack_hw, stack_base_y, stack_z + stack_hw),  # 3: front-left-bottom
            Vector3(stack_x - stack_hw, stack_top_y, stack_z - stack_hw),  # 4: back-left-top
            Vector3(stack_x + stack_hw, stack_top_y, stack_z - stack_hw),  # 5: back-right-top
            Vector3(stack_x + stack_hw, stack_top_y, stack_z + stack_hw),  # 6: front-right-top
            Vector3(stack_x - stack_hw, stack_top_y, stack_z + stack_hw),  # 7: front-left-top
        ]

        var stack_faces := [
            [0, 1, 5, 4],  # back
            [1, 2, 6, 5],  # right
            [2, 3, 7, 6],  # front
            [3, 0, 4, 7],  # left
        ]

        for face in stack_faces:
            var v0 = stack_corners[face[0]]
            var v1 = stack_corners[face[1]]
            var v2 = stack_corners[face[2]]
            var v3 = stack_corners[face[3]]

            # Triangle 1: v0-v1-v2 (counter-clockwise for outward normals)
            st.add_vertex(v0)
            st.add_vertex(v1)
            st.add_vertex(v2)

            # Triangle 2: v0-v2-v3 (counter-clockwise for outward normals)
            st.add_vertex(v0)
            st.add_vertex(v2)
            st.add_vertex(v3)

        # Stack top (normal pointing up)
        st.add_vertex(stack_corners[4])  # back-left-top
        st.add_vertex(stack_corners[7])  # front-left-top
        st.add_vertex(stack_corners[6])  # front-right-top

        st.add_vertex(stack_corners[4])  # back-left-top
        st.add_vertex(stack_corners[6])  # front-right-top
        st.add_vertex(stack_corners[5])  # back-right-top

    # Add loading dock/warehouse extension
    var dock_width: float = width * 0.6
    var dock_depth: float = depth * 0.4
    var dock_height: float = height * 0.8  # Slightly shorter
    var dock_hw: float = dock_width * 0.5
    var dock_hd: float = dock_depth * 0.5
    var dock_x: float = 0.0  # Centered
    var dock_z: float = hd  # Attached to front
    var dock_base_y: float = base_y
    var dock_top_y: float = dock_base_y + dock_height

    # Dock structure
    var dock_corners := [
        Vector3(dock_x - dock_hw, dock_base_y, dock_z),      # 0: left-bottom
        Vector3(dock_x + dock_hw, dock_base_y, dock_z),      # 1: right-bottom
        Vector3(dock_x + dock_hw, dock_base_y, dock_z + dock_hd),  # 2: right-front-bottom
        Vector3(dock_x - dock_hw, dock_base_y, dock_z + dock_hd),  # 3: left-front-bottom
        Vector3(dock_x - dock_hw, dock_top_y, dock_z),       # 4: left-top
        Vector3(dock_x + dock_hw, dock_top_y, dock_z),       # 5: right-top
        Vector3(dock_x + dock_hw, dock_top_y, dock_z + dock_hd),   # 6: right-front-top
        Vector3(dock_x - dock_hw, dock_top_y, dock_z + dock_hd),   # 7: left-front-top
    ]

    # Dock faces (only 3 sides since attached to main building)
    var dock_faces := [
        [0, 1, 5, 4],  # back side (facing +Z, but this is the front of dock)
        [1, 2, 6, 5],  # right side
        [2, 3, 7, 6],  # front side
        [3, 0, 4, 7],  # left side
    ]

    for face in dock_faces:
        var v0 = dock_corners[face[0]]
        var v1 = dock_corners[face[1]]
        var v2 = dock_corners[face[2]]
        var v3 = dock_corners[face[3]]

        # Triangle 1: v0-v1-v2 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Dock roof
    st.add_vertex(dock_corners[4])  # back-left-top
    st.add_vertex(dock_corners[7])  # front-left-top
    st.add_vertex(dock_corners[6])  # front-right-top

    st.add_vertex(dock_corners[4])  # back-left-top
    st.add_vertex(dock_corners[6])  # front-right-top
    st.add_vertex(dock_corners[5])  # back-right-top

    st.generate_normals()
    var mesh := st.commit()

    # Apply factory-appropriate material (dark gray/industrial)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.3, 0.35)  # Dark gray industrial
    mat.roughness = 0.95
    mesh.surface_set_material(0, mat)

    return mesh