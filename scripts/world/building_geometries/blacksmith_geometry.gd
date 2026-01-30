class_name BlacksmithGeometry
extends RefCounted

## Creates a proper blacksmith shop geometry with forge, anvil area, and chimney

static func create(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Blacksmith shop specifications
    var width: float = max(plot.lot_width * 0.8, 4.0)
    var depth: float = max(plot.lot_depth * 0.7, 4.0)
    var height: float = rng.randf_range(8.0, 12.0)

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

    # Flat roof
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[7])  # front-left-top
    st.add_vertex(corners[6])  # front-right-top

    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(corners[5])  # back-right-top

    # Add blacksmith-specific features: chimney and forge area
    var chimney_width: float = 1.0
    var chimney_height: float = 6.0  # Taller than building for smoke
    var chimney_hw: float = chimney_width * 0.5
    var chimney_x: float = -hw * 0.6  # Offset from center toward back
    var chimney_z: float = -hd * 0.6  # Offset from center toward back
    var chimney_base_y: float = top_y
    var chimney_top_y: float = chimney_base_y + chimney_height

    # Chimney structure
    var chimney_corners := [
        Vector3(chimney_x - chimney_hw, chimney_base_y, chimney_z - chimney_hw),  # 0: back-left-bottom
        Vector3(chimney_x + chimney_hw, chimney_base_y, chimney_z - chimney_hw),  # 1: back-right-bottom
        Vector3(chimney_x + chimney_hw, chimney_base_y, chimney_z + chimney_hw),  # 2: front-right-bottom
        Vector3(chimney_x - chimney_hw, chimney_base_y, chimney_z + chimney_hw),  # 3: front-left-bottom
        Vector3(chimney_x - chimney_hw, chimney_top_y, chimney_z - chimney_hw),  # 4: back-left-top
        Vector3(chimney_x + chimney_hw, chimney_top_y, chimney_z - chimney_hw),  # 5: back-right-top
        Vector3(chimney_x + chimney_hw, chimney_top_y, chimney_z + chimney_hw),  # 6: front-right-top
        Vector3(chimney_x - chimney_hw, chimney_top_y, chimney_z + chimney_hw),  # 7: front-left-top
    ]

    var chimney_faces := [
        [0, 1, 5, 4],  # back
        [1, 2, 6, 5],  # right
        [2, 3, 7, 6],  # front
        [3, 0, 4, 7],  # left
    ]

    for face in chimney_faces:
        var v0 = chimney_corners[face[0]]
        var v1 = chimney_corners[face[1]]
        var v2 = chimney_corners[face[2]]
        var v3 = chimney_corners[face[3]]

        # Triangle 1: v0-v1-v2 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Chimney top (normal pointing up)
    st.add_vertex(chimney_corners[4])  # back-left-top
    st.add_vertex(chimney_corners[7])  # front-left-top
    st.add_vertex(chimney_corners[6])  # front-right-top

    st.add_vertex(chimney_corners[4])  # back-left-top
    st.add_vertex(chimney_corners[6])  # front-right-top
    st.add_vertex(chimney_corners[5])  # back-right-top

    # Forge area (slightly raised platform inside)
    var forge_width: float = width * 0.3
    var forge_depth: float = depth * 0.25
    var forge_height: float = 0.3  # Low platform
    var forge_hw: float = forge_width * 0.5
    var forge_hd: float = forge_depth * 0.5
    var forge_x: float = -hw * 0.3  # Toward front-left
    var forge_z: float = hd * 0.4  # Toward front
    var forge_y: float = base_y + 0.1  # Slightly above ground

    var forge_corners := [
        Vector3(forge_x - forge_hw, forge_y, forge_z - forge_hd),  # 0: back-left
        Vector3(forge_x + forge_hw, forge_y, forge_z - forge_hd),  # 1: back-right
        Vector3(forge_x + forge_hw, forge_y, forge_z + forge_hd),  # 2: front-right
        Vector3(forge_x - forge_hw, forge_y, forge_z + forge_hd),  # 3: front-left
        Vector3(forge_x - forge_hw, forge_y + forge_height, forge_z - forge_hd),  # 4: top back-left
        Vector3(forge_x + forge_hw, forge_y + forge_height, forge_z - forge_hd),  # 5: top back-right
        Vector3(forge_x + forge_hw, forge_y + forge_height, forge_z + forge_hd),  # 6: top front-right
        Vector3(forge_x - forge_hw, forge_y + forge_height, forge_z + forge_hd),  # 7: top front-left
    ]

    # Forge platform top (normal pointing up) - counter-clockwise for outward normals
    st.add_vertex(forge_corners[4])  # top back-left
    st.add_vertex(forge_corners[5])  # top back-right
    st.add_vertex(forge_corners[6])  # top front-right

    st.add_vertex(forge_corners[4])  # top back-left
    st.add_vertex(forge_corners[6])  # top front-right
    st.add_vertex(forge_corners[7])  # top front-left

    # Forge sides
    var forge_faces := [
        [0, 1, 5, 4],  # back
        [1, 2, 6, 5],  # right
        [2, 3, 7, 6],  # front
        [3, 0, 4, 7],  # left
        [0, 3, 7, 4],  # bottom
    ]

    for face in forge_faces:
        var v0 = forge_corners[face[0]]
        var v1 = forge_corners[face[1]]
        var v2 = forge_corners[face[2]]
        var v3 = forge_corners[face[3]]

        # Triangle 1: v0-v1-v2 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    st.generate_normals()
    var mesh := st.commit()

    # Apply blacksmith-appropriate material (dark brown/gray with metal accents)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.3, 0.25)  # Dark brown/wood
    mat.roughness = 0.9
    mesh.surface_set_material(0, mat)

    return mesh