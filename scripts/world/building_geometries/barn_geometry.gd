class_name BarnGeometry
extends RefCounted

## Creates a proper barn geometry with gable roof and agricultural details

static func create(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Barn specifications
    var width: float = max(plot.lot_width * 0.9, 6.0)  # Ensure minimum size
    var depth: float = max(plot.lot_depth * 0.8, 5.0)  # Ensure minimum size
    var height: float = rng.randf_range(8.0, 15.0)
    var roof_height: float = height * 0.4  # Gable roof height

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var top_y: float = height

    # Create main barn structure (rectangular box)
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

    # Gable roof (triangular roof face on front and back)
    var roof_peak_y: float = top_y + roof_height

    # Front gable (triangular roof face)
    var front_center_top = Vector3(0, roof_peak_y, hd)
    var front_bottom_left = Vector3(-hw, top_y, hd)
    var front_bottom_right = Vector3(hw, top_y, hd)

    # Triangle pointing outward (counter-clockwise when viewed from front)
    st.add_vertex(front_bottom_left)
    st.add_vertex(front_bottom_right)
    st.add_vertex(front_center_top)

    # Back gable
    var back_center_top = Vector3(0, roof_peak_y, -hd)
    var back_bottom_left = Vector3(-hw, top_y, -hd)
    var back_bottom_right = Vector3(hw, top_y, -hd)

    # Triangle pointing outward (counter-clockwise when viewed from back)
    st.add_vertex(back_bottom_right)
    st.add_vertex(back_bottom_left)
    st.add_vertex(back_center_top)

    # Roof sides (connect roof peak to roof edges)
    # Left roof slope - normal should point up and left
    st.add_vertex(front_bottom_left)
    st.add_vertex(back_bottom_left)
    st.add_vertex(back_center_top)

    st.add_vertex(front_bottom_left)
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right roof slope - normal should point up and right
    st.add_vertex(front_bottom_right)
    st.add_vertex(front_center_top)
    st.add_vertex(back_center_top)

    st.add_vertex(front_bottom_right)
    st.add_vertex(back_center_top)
    st.add_vertex(back_bottom_right)

    # Add barn details: large doors and hayloft windows
    var door_width: float = width * 0.4
    var door_height: float = height * 0.6
    var door_x: float = 0.0
    var door_z: float = hd  # On front face
    var door_y: float = base_y  # At ground level

    # Create large barn door opening (negative space - not filled in)
    # We'll create a frame around the door instead
    var frame_thickness: float = 0.3
    var door_hw: float = door_width * 0.5
    var door_hh: float = door_height * 0.5

    # Door frame - left side
    var frame_left_x: float = door_x - door_hw - frame_thickness * 0.5
    var frame_right_x: float = door_x + door_hw + frame_thickness * 0.5
    var frame_bottom_y: float = door_y
    var frame_top_y: float = door_y + door_height
    var frame_front_z: float = door_z
    var frame_back_z: float = door_z - frame_thickness

    # Left frame post
    var flb := Vector3(frame_left_x, frame_bottom_y, frame_front_z)  # Left bottom front
    var flf := Vector3(frame_left_x, frame_bottom_y, frame_back_z)   # Left bottom back
    var flu := Vector3(frame_left_x, frame_top_y, frame_front_z)     # Left top front
    var flr := Vector3(frame_left_x, frame_top_y, frame_back_z)      # Left top back

    st.add_vertex(flb)
    st.add_vertex(flf)
    st.add_vertex(flr)

    st.add_vertex(flb)
    st.add_vertex(flr)
    st.add_vertex(flu)

    # Right frame post
    var frb := Vector3(frame_right_x, frame_bottom_y, frame_front_z)  # Right bottom front
    var frf := Vector3(frame_right_x, frame_bottom_y, frame_back_z)   # Right bottom back
    var fru := Vector3(frame_right_x, frame_top_y, frame_front_z)     # Right top front
    var frr := Vector3(frame_right_x, frame_top_y, frame_back_z)      # Right top back

    st.add_vertex(frb)
    st.add_vertex(frf)
    st.add_vertex(frr)

    st.add_vertex(frb)
    st.add_vertex(frr)
    st.add_vertex(fru)

    # Top frame beam
    st.add_vertex(flu)
    st.add_vertex(flr)
    st.add_vertex(frr)

    st.add_vertex(flu)
    st.add_vertex(frr)
    st.add_vertex(fru)

    # Bottom frame beam
    st.add_vertex(flb)
    st.add_vertex(frb)
    st.add_vertex(frf)

    st.add_vertex(flb)
    st.add_vertex(frf)
    st.add_vertex(flf)

    st.generate_normals()
    var mesh := st.commit()

    # Apply barn-appropriate material (red with white trim)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.7, 0.1, 0.1)  # Red barn color
    mat.roughness = 0.9
    mesh.surface_set_material(0, mat)

    return mesh