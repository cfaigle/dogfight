class_name RoofComponent
extends BuildingComponentBase

## Generates various roof types with dormers and cupolas
## Supports gable, hip, gambrel, mansard, flat, shed, and cone roofs

func get_required_params() -> Array[String]:
    return ["footprint", "height", "roof_type"]

func get_optional_params() -> Dictionary:
    return {
        "roof_pitch": 0.8,  # Rise over run
        "overhang": 0.3,
        "add_dormers": false,
        "dormer_count": 2,
        "add_cupola": false,
        "texture_scale": 2.0
    }

func generate(st: SurfaceTool, params: Dictionary, materials: Dictionary) -> void:
    var footprint: PackedVector2Array = params["footprint"]
    var height: float = params["height"]
    var roof_type: String = params["roof_type"]
    var roof_pitch: float = params["roof_pitch"]
    var overhang: float = params["overhang"]

    # Expand footprint for overhang
    var roof_footprint = _expand_footprint(footprint, overhang)

    # Generate roof based on type
    match roof_type:
        "gable":
            _create_gable_roof(st, roof_footprint, height, roof_pitch)
        "hip":
            _create_hip_roof(st, roof_footprint, height, roof_pitch)
        "gambrel":
            _create_gambrel_roof(st, roof_footprint, height, roof_pitch)
        "mansard":
            _create_mansard_roof(st, roof_footprint, height, roof_pitch)
        "flat":
            _create_flat_roof(st, roof_footprint, height)
        "shed":
            _create_shed_roof(st, roof_footprint, height, roof_pitch)
        "cone":
            _create_cone_roof(st, roof_footprint, height, roof_pitch)
        _:
            _create_gable_roof(st, roof_footprint, height, roof_pitch)

    # Add optional features
    if params.get("add_dormers", false) and roof_type in ["gable", "hip", "gambrel", "mansard"]:
        _add_dormers(st, footprint, height, roof_pitch, params["dormer_count"])

    if params.get("add_cupola", false):
        _add_cupola(st, footprint, height, roof_pitch)

## Create a gable roof (two sloping sides meeting at a ridge)
func _create_gable_roof(st: SurfaceTool, footprint: PackedVector2Array,
                        height: float, pitch: float) -> void:
    # Find bounding box to determine ridge line
    var bounds = _get_footprint_bounds(footprint)
    var center = bounds["center"]
    var width = bounds["width"]
    var depth = bounds["depth"]

    # Ridge height: add half of shorter dimension times pitch to wall height
    var roof_dimension = min(width, depth)
    var ridge_height = height + roof_dimension * 0.5 * pitch

    # Ridge runs along longer dimension for proper gable roof
    var ridge_dir = Vector3(1, 0, 0) if width > depth else Vector3(0, 0, 1)
    var half_length = (width if width > depth else depth) * 0.5

    var ridge_start = Vector3(center.x, ridge_height, center.y) - ridge_dir * half_length
    var ridge_end = Vector3(center.x, ridge_height, center.y) + ridge_dir * half_length

    # Create two roof planes
    var perpendicular = Vector3(-ridge_dir.z, 0, ridge_dir.x)

    # Find front and back edges based on perpendicular distance from ridge
    var front_edge = []
    var back_edge = []

    for i in range(footprint.size()):
        var p = footprint[i]
        var p3d = Vector3(p.x, height, p.y)  # Top of walls, not floor

        # Calculate perpendicular distance from ridge line
        var to_ridge_start = p3d - ridge_start
        var side = to_ridge_start.cross(ridge_dir).y > 0

        if side:
            front_edge.append(p3d)
        else:
            back_edge.append(p3d)

    # Create front roof plane
    if front_edge.size() >= 2:
        for i in range(front_edge.size() - 1):
            add_quad(st, front_edge[i], front_edge[i + 1], ridge_end, ridge_start,
                     Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

    # Create back roof plane
    if back_edge.size() >= 2:
        for i in range(back_edge.size() - 1):
            add_quad(st, back_edge[i], back_edge[i + 1], ridge_end, ridge_start,
                     Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

    # Create gable ends (triangular walls)
    _create_gable_end(st, ridge_start, front_edge[0], back_edge[0])
    _create_gable_end(st, ridge_end, front_edge[-1], back_edge[-1])

## Create a hip roof (four sloping sides meeting at a peak or ridge)
func _create_hip_roof(st: SurfaceTool, footprint: PackedVector2Array,
                      height: float, pitch: float) -> void:
    var bounds = _get_footprint_bounds(footprint)
    var center = bounds["center"]
    var width = bounds["width"]
    var depth = bounds["depth"]

    # Peak height
    var peak_height = height + min(width, depth) * 0.25 * pitch
    var peak = Vector3(center.x, peak_height, center.y)

    # Create triangular faces from each edge to peak
    for i in range(footprint.size()):
        var p0 = footprint[i]
        var p1 = footprint[(i + 1) % footprint.size()]

        var v0 = Vector3(p0.x, height, p0.y)
        var v1 = Vector3(p1.x, height, p1.y)

        # Create triangular roof face (split into two triangles)
        var edge_length = v0.distance_to(v1)
        var mid_point = (v0 + v1) * 0.5
        
        # Two triangles to form the face
        add_quad(st, v0, v1, mid_point, peak,
                 Vector2(0, 0), Vector2(edge_length, 0),
                 Vector2(edge_length * 0.5, 0.5), Vector2(edge_length * 0.5, 1))

## Create a gambrel roof (barn-style with two slopes on each side)
func _create_gambrel_roof(st: SurfaceTool, footprint: PackedVector2Array,
                          height: float, pitch: float) -> void:
    var bounds = _get_footprint_bounds(footprint)
    var center = bounds["center"]
    var width = bounds["width"]
    var depth = bounds["depth"]

    # Gambrel has steep lower slope and gentle upper slope
    var roof_dim = max(width, depth)
    var lower_height = height + roof_dim * 0.2 * pitch * 1.5  # Steeper
    var ridge_height = height + roof_dim * 0.4 * pitch  # Gentler

    var ridge_dir = Vector3(1, 0, 0) if width > depth else Vector3(0, 0, 1)
    var perpendicular = Vector3(-ridge_dir.z, 0, ridge_dir.x)

    var half_length = (width if width > depth else depth) * 0.5
    var mid_offset = (width if width > depth else depth) * 0.25

    # Define roof profile points
    var ridge_start = Vector3(center.x, ridge_height, center.y) - ridge_dir * half_length
    var ridge_end = Vector3(center.x, ridge_height, center.y) + ridge_dir * half_length

    var mid_front_start = ridge_start + perpendicular * mid_offset
    mid_front_start.y = lower_height
    var mid_front_end = ridge_end + perpendicular * mid_offset
    mid_front_end.y = lower_height

    var mid_back_start = ridge_start - perpendicular * mid_offset
    mid_back_start.y = lower_height
    var mid_back_end = ridge_end - perpendicular * mid_offset
    mid_back_end.y = lower_height

    # Find edge points
    var front_edge = _get_edge_points(footprint, height, ridge_start, perpendicular, true)
    var back_edge = _get_edge_points(footprint, height, ridge_start, perpendicular, false)

    # Create four roof planes
    # Front lower
    for i in range(front_edge.size() - 1):
        add_quad(st, front_edge[i], front_edge[i + 1], mid_front_end, mid_front_start)

    # Front upper
    add_quad(st, mid_front_start, mid_front_end, ridge_end, ridge_start)

    # Back lower
    for i in range(back_edge.size() - 1):
        add_quad(st, mid_back_start, mid_back_end, back_edge[i + 1], back_edge[i])

    # Back upper
    add_quad(st, ridge_start, ridge_end, mid_back_end, mid_back_start)

## Create a mansard roof (French-style with steep lower slope, flat or gentle upper)
func _create_mansard_roof(st: SurfaceTool, footprint: PackedVector2Array,
                          height: float, pitch: float) -> void:
    # Similar to gambrel but with four sides
    var expanded = _expand_footprint(footprint, 0.0)
    var shrunken = _shrink_footprint(footprint, footprint[0].distance_to(footprint[1]) * 0.2)

    var lower_height = height + 1.5
    var upper_height = height + 2.5

    # Create steep lower mansard faces
    for i in range(expanded.size()):
        var p0_outer = expanded[i]
        var p1_outer = expanded[(i + 1) % expanded.size()]
        var p0_inner = shrunken[i]
        var p1_inner = shrunken[(i + 1) % shrunken.size()]

        var v0_bottom = Vector3(p0_outer.x, height, p0_outer.y)
        var v1_bottom = Vector3(p1_outer.x, height, p1_outer.y)
        var v0_top = Vector3(p0_inner.x, lower_height, p0_inner.y)
        var v1_top = Vector3(p1_inner.x, lower_height, p1_inner.y)

        add_quad(st, v0_bottom, v1_bottom, v1_top, v0_top)

    # Create flat or gentle upper roof
    _create_flat_roof(st, shrunken, lower_height)

## Create a flat roof
func _create_flat_roof(st: SurfaceTool, footprint: PackedVector2Array,
                       height: float) -> void:
    if footprint.size() < 3:
        return

    # Triangulate the footprint
    var center = Vector2.ZERO
    for p in footprint:
        center += p
    center /= footprint.size()

    var center_3d = Vector3(center.x, height, center.y)

    # Create triangles from center to edges
    for i in range(footprint.size()):
        var p0 = footprint[i]
        var p1 = footprint[(i + 1) % footprint.size()]

        var v0 = Vector3(p0.x, height, p0.y)
        var v1 = Vector3(p1.x, height, p1.y)

        # Create triangle
        var normal = (v1 - v0).cross(center_3d - v0).normalized()
        st.set_normal(normal)
        st.set_uv(Vector2(0, 0))
        st.add_vertex(v0)

        st.set_normal(normal)
        st.set_uv(Vector2(1, 0))
        st.add_vertex(v1)

        st.set_normal(normal)
        st.set_uv(Vector2(0.5, 1))
        st.add_vertex(center_3d)

## Create a shed roof (single sloping plane)
func _create_shed_roof(st: SurfaceTool, footprint: PackedVector2Array,
                       height: float, pitch: float) -> void:
    var bounds = _get_footprint_bounds(footprint)
    var center = bounds["center"]
    var depth = bounds["depth"]

    var rise = depth * pitch

    # Create sloped footprint
    var raised_footprint = PackedVector2Array()
    for i in range(footprint.size()):
        var p = footprint[i]
        # Determine if point is on high or low side
        var t = (p.y - (center.y - depth * 0.5)) / depth
        var point_height = height + t * rise

        raised_footprint.append(p)

    # Create roof surface (similar to flat but with height variation)
    for i in range(footprint.size()):
        var p0 = footprint[i]
        var p1 = footprint[(i + 1) % footprint.size()]

        var t0 = (p0.y - (center.y - depth * 0.5)) / depth
        var t1 = (p1.y - (center.y - depth * 0.5)) / depth

        var v0 = Vector3(p0.x, height + t0 * rise, p0.y)
        var v1 = Vector3(p1.x, height + t1 * rise, p1.y)

        var center_t = (center.y - (center.y - depth * 0.5)) / depth
        var v_center = Vector3(center.x, height + center_t * rise, center.y)

        # Triangle to center
        var normal = (v1 - v0).cross(v_center - v0).normalized()
        st.set_normal(normal)
        st.set_uv(Vector2(0, 0))
        st.add_vertex(v0)

        st.set_normal(normal)
        st.set_uv(Vector2(1, 0))
        st.add_vertex(v1)

        st.set_normal(normal)
        st.set_uv(Vector2(0.5, 1))
        st.add_vertex(v_center)

## Create a cone roof (for circular towers)
func _create_cone_roof(st: SurfaceTool, footprint: PackedVector2Array,
                       height: float, pitch: float) -> void:
    var bounds = _get_footprint_bounds(footprint)
    var center = bounds["center"]
    var radius = max(bounds["width"], bounds["depth"]) * 0.5

    var peak_height = height + radius * pitch
    var peak = Vector3(center.x, peak_height, center.y)

    # Create cone from footprint to peak
    for i in range(footprint.size()):
        var p0 = footprint[i]
        var p1 = footprint[(i + 1) % footprint.size()]

        var v0 = Vector3(p0.x, height, p0.y)
        var v1 = Vector3(p1.x, height, p1.y)

        # Create triangular face
        var edge_length = v0.distance_to(v1)
        add_quad(st, v0, v1, peak, peak,
                 Vector2(0, 0), Vector2(edge_length, 0),
                 Vector2(edge_length * 0.5, 1), Vector2(edge_length * 0.5, 1))

## Add dormers (small windows in roof)
func _add_dormers(st: SurfaceTool, footprint: PackedVector2Array,
                  height: float, pitch: float, count: int) -> void:
    var bounds = _get_footprint_bounds(footprint)
    var width = bounds["width"]

    for i in range(count):
        var t = (i + 1.0) / (count + 1.0)
        var x = bounds["min_x"] + width * t

        var dormer_width = 1.0
        var dormer_height = 1.5
        var dormer_depth = 0.8

        # Create simple dormer structure
        var base_y = height + pitch * 2.0
        var dormer_center = Vector3(x, base_y, bounds["center"].y)

        # Dormer front face
        var half_w = dormer_width * 0.5
        var tl = dormer_center + Vector3(-half_w, dormer_height, dormer_depth)
        var tr = dormer_center + Vector3(half_w, dormer_height, dormer_depth)
        var bl = dormer_center + Vector3(-half_w, 0, dormer_depth)
        var br = dormer_center + Vector3(half_w, 0, dormer_depth)

        add_quad(st, bl, br, tr, tl)

        # Dormer roof (simple gable)
        var peak = dormer_center + Vector3(0, dormer_height + 0.5, dormer_depth * 0.5)
        add_quad(st, tl, peak, peak, bl)
        add_quad(st, peak, tr, br, peak)

## Add cupola (small tower on roof peak)
func _add_cupola(st: SurfaceTool, footprint: PackedVector2Array,
                 height: float, pitch: float) -> void:
    var bounds = _get_footprint_bounds(footprint)
    var center = bounds["center"]
    var base_height = height + min(bounds["width"], bounds["depth"]) * 0.25 * pitch

    var cupola_size = 1.0
    var cupola_height = 2.0

    # Create simple cupola base
    var base_center = Vector3(center.x, base_height, center.y)

    var corners = [
        base_center + Vector3(-cupola_size, 0, -cupola_size),
        base_center + Vector3(cupola_size, 0, -cupola_size),
        base_center + Vector3(cupola_size, 0, cupola_size),
        base_center + Vector3(-cupola_size, 0, cupola_size)
    ]

    # Cupola walls
    for i in range(4):
        var p0 = corners[i]
        var p1 = corners[(i + 1) % 4]
        var p0_top = p0 + Vector3.UP * cupola_height
        var p1_top = p1 + Vector3.UP * cupola_height

        add_quad(st, p0, p1, p1_top, p0_top)

    # Cupola roof (small pyramid)
    var peak = base_center + Vector3.UP * (cupola_height + 0.5)
    for i in range(4):
        var p0 = corners[i] + Vector3.UP * cupola_height
        var p1 = corners[(i + 1) % 4] + Vector3.UP * cupola_height
        add_quad(st, p0, p1, peak, peak)

## Helper: Expand footprint outward
func _expand_footprint(footprint: PackedVector2Array, amount: float) -> PackedVector2Array:
    if amount == 0:
        return footprint

    var expanded = PackedVector2Array()
    var point_count = footprint.size()

    for i in range(point_count):
        var prev = footprint[(i - 1 + point_count) % point_count]
        var curr = footprint[i]
        var next = footprint[(i + 1) % point_count]

        var edge1 = curr - prev
        var edge2 = next - curr

        var normal1 = Vector2(-edge1.y, edge1.x).normalized()
        var normal2 = Vector2(-edge2.y, edge2.x).normalized()

        var offset_dir = (normal1 + normal2).normalized()
        expanded.append(curr + offset_dir * amount)

    return expanded

## Helper: Shrink footprint inward
func _shrink_footprint(footprint: PackedVector2Array, amount: float) -> PackedVector2Array:
    return _expand_footprint(footprint, -amount)

## Helper: Get bounding box of footprint
func _get_footprint_bounds(footprint: PackedVector2Array) -> Dictionary:
    var min_x = INF
    var max_x = -INF
    var min_y = INF
    var max_y = -INF

    for p in footprint:
        min_x = min(min_x, p.x)
        max_x = max(max_x, p.x)
        min_y = min(min_y, p.y)
        max_y = max(max_y, p.y)

    return {
        "min_x": min_x,
        "max_x": max_x,
        "min_y": min_y,
        "max_y": max_y,
        "width": max_x - min_x,
        "depth": max_y - min_y,
        "center": Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
    }

## Helper: Get edge points on one side of a line
func _get_edge_points(footprint: PackedVector2Array, height: float,
                      line_start: Vector3, perpendicular: Vector3,
                      front_side: bool) -> Array:
    var edge_points = []

    for p in footprint:
        var p3d = Vector3(p.x, height, p.y)
        var to_point = p3d - line_start
        var side = to_point.dot(perpendicular)

        if (front_side and side > 0) or (not front_side and side <= 0):
            edge_points.append(p3d)

    return edge_points

## Helper: Create gable end (triangular wall)
func _create_gable_end(st: SurfaceTool, peak: Vector3, front: Vector3, back: Vector3) -> void:
    # Triangle from front edge to peak
    var normal = (front - back).cross(peak - back).normalized()

    st.set_normal(normal)
    st.set_uv(Vector2(0, 0))
    st.add_vertex(back)

    st.set_normal(normal)
    st.set_uv(Vector2(1, 0))
    st.add_vertex(front)

    st.set_normal(normal)
    st.set_uv(Vector2(0.5, 1))
    st.add_vertex(peak)
