class_name ChurchGeometry
extends RefCounted

## Creates a proper church building geometry with steeple and religious features

static func create(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Church building specifications
    var width: float = max(plot.lot_width * 0.7, 6.0)  # Narrower than typical building
    var depth: float = max(plot.lot_depth * 0.8, 8.0)  # Longer depth for church layout
    var height: float = rng.randf_range(12.0, 20.0)
    var roof_height: float = height * 0.4  # Pointed roof for church

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var top_y: float = height

    # Main church building structure
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
        [3, 2, 6, 7],  # front - facing +Z
        [1, 0, 4, 5],  # back - facing -Z
        [0, 3, 7, 4],  # left - facing -X
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

    # Pointed roof (gable roof for church)
    var roof_peak_y: float = top_y + roof_height
    var front_center_top = Vector3(0, roof_peak_y, hd)
    var back_center_top = Vector3(0, roof_peak_y, -hd)

    # Front gable (triangular roof face)
    st.add_vertex(corners[3])  # front-bottom-left
    st.add_vertex(corners[2])  # front-bottom-right
    st.add_vertex(front_center_top)

    # Back gable
    st.add_vertex(corners[1])  # back-bottom-right
    st.add_vertex(corners[0])  # back-bottom-left
    st.add_vertex(back_center_top)

    # Roof slopes
    # Left slope
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(back_center_top)

    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right slope
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(front_center_top)
    st.add_vertex(back_center_top)

    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(corners[1])  # back-right-bottom

    # Church steeple
    var steeple_width: float = width * 0.2  # Narrow steeple
    var steeple_height: float = height * 0.8  # Tall steeple
    var steeple_hw: float = steeple_width * 0.5
    var steeple_x: float = 0.0  # Centered
    var steeple_z: float = hd * 0.7  # At front of church
    var steeple_base_y: float = roof_peak_y
    var steeple_top_y: float = steeple_base_y + steeple_height

    # Create rectangular steeple base
    var steeple_corners := [
        Vector3(steeple_x - steeple_hw, steeple_base_y, steeple_z - steeple_hw),  # 0: back-left-bottom
        Vector3(steeple_x + steeple_hw, steeple_base_y, steeple_z - steeple_hw),  # 1: back-right-bottom
        Vector3(steeple_x + steeple_hw, steeple_base_y, steeple_z + steeple_hw),  # 2: front-right-bottom
        Vector3(steeple_x - steeple_hw, steeple_base_y, steeple_z + steeple_hw),  # 3: front-left-bottom
        Vector3(steeple_x - steeple_hw, steeple_top_y, steeple_z - steeple_hw),  # 4: back-left-top
        Vector3(steeple_x + steeple_hw, steeple_top_y, steeple_z - steeple_hw),  # 5: back-right-top
        Vector3(steeple_x + steeple_hw, steeple_top_y, steeple_z + steeple_hw),  # 6: front-right-top
        Vector3(steeple_x - steeple_hw, steeple_top_y, steeple_z + steeple_hw),  # 7: front-left-top
    ]

    var steeple_faces := [
        [0, 1, 5, 4],  # back
        [1, 2, 6, 5],  # right
        [2, 3, 7, 6],  # front
        [3, 0, 4, 7],  # left
    ]

    for face in steeple_faces:
        var v0 = steeple_corners[face[0]]
        var v1 = steeple_corners[face[1]]
        var v2 = steeple_corners[face[2]]
        var v3 = steeple_corners[face[3]]

        # Triangle 1: v0-v1-v2 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Steeple top (pyramidal point)
    var steeple_peak = Vector3(steeple_x, steeple_top_y + height * 0.3, steeple_z)
    for i in range(4):
        var corner1 = steeple_corners[4 + i]  # Top corners
        var corner2 = steeple_corners[4 + ((i + 1) % 4)]  # Next top corner
        st.add_vertex(corner1)
        st.add_vertex(corner2)
        st.add_vertex(steeple_peak)

    # Cross on top of steeple
    var cross_height: float = height * 0.2
    var cross_width: float = steeple_width * 0.5
    var cross_hw: float = cross_width * 0.5
    var cross_base_y: float = steeple_top_y + height * 0.1

    # Vertical part of cross
    var cross_v_corners := [
        Vector3(steeple_x - cross_hw * 0.3, cross_base_y, steeple_z - cross_hw * 0.3),  # 0: back-left-bottom
        Vector3(steeple_x + cross_hw * 0.3, cross_base_y, steeple_z - cross_hw * 0.3),  # 1: back-right-bottom
        Vector3(steeple_x + cross_hw * 0.3, cross_base_y, steeple_z + cross_hw * 0.3),  # 2: front-right-bottom
        Vector3(steeple_x - cross_hw * 0.3, cross_base_y, steeple_z + cross_hw * 0.3),  # 3: front-left-bottom
        Vector3(steeple_x - cross_hw * 0.3, cross_base_y + cross_height, steeple_z - cross_hw * 0.3),  # 4: back-left-top
        Vector3(steeple_x + cross_hw * 0.3, cross_base_y + cross_height, steeple_z - cross_hw * 0.3),  # 5: back-right-top
        Vector3(steeple_x + cross_hw * 0.3, cross_base_y + cross_height, steeple_z + cross_hw * 0.3),  # 6: front-right-top
        Vector3(steeple_x - cross_hw * 0.3, cross_base_y + cross_height, steeple_z + cross_hw * 0.3),  # 7: front-left-top
    ]

    var cross_v_faces := [
        [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]
    ]

    for face in cross_v_faces:
        var v0 = cross_v_corners[face[0]]
        var v1 = cross_v_corners[face[1]]
        var v2 = cross_v_corners[face[2]]
        var v3 = cross_v_corners[face[3]]

        # Triangle 1: v0-v1-v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Horizontal part of cross
    var cross_h_width: float = steeple_width * 0.8
    var cross_h_hw: float = cross_h_width * 0.5
    var cross_h_base_y: float = cross_base_y + cross_height * 0.7
    var cross_h_top_y: float = cross_base_y + cross_height * 0.9

    var cross_h_corners := [
        Vector3(steeple_x - cross_h_hw, cross_h_base_y, steeple_z - cross_hw * 0.3),  # 0: left-bottom
        Vector3(steeple_x + cross_h_hw, cross_h_base_y, steeple_z - cross_hw * 0.3),  # 1: right-bottom
        Vector3(steeple_x + cross_h_hw, cross_h_base_y, steeple_z + cross_hw * 0.3),  # 2: right-top
        Vector3(steeple_x - cross_h_hw, cross_h_base_y, steeple_z + cross_hw * 0.3),  # 3: left-top
        Vector3(steeple_x - cross_h_hw, cross_h_top_y, steeple_z - cross_hw * 0.3),  # 4: left-top
        Vector3(steeple_x + cross_h_hw, cross_h_top_y, steeple_z - cross_hw * 0.3),  # 5: right-top
        Vector3(steeple_x + cross_h_hw, cross_h_top_y, steeple_z + cross_hw * 0.3),  # 6: right-top
        Vector3(steeple_x - cross_h_hw, cross_h_top_y, steeple_z + cross_hw * 0.3),  # 7: left-top
    ]

    var cross_h_faces := [
        [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]
    ]

    for face in cross_h_faces:
        var v0 = cross_h_corners[face[0]]
        var v1 = cross_h_corners[face[1]]
        var v2 = cross_h_corners[face[2]]
        var v3 = cross_h_corners[face[3]]

        # Triangle 1: v0-v1-v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    st.generate_normals()
    var mesh := st.commit()

    # Apply church-appropriate material (light gray/white with some brown accents)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.85, 0.85, 0.8)  # Light gray/white
    mat.roughness = 0.85
    mesh.surface_set_material(0, mat)

    return mesh