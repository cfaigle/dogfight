extends WorldComponentBase
class_name SettlementRoadsComponent

## Generates internal road networks within settlements (cities and towns).
## Cities get grid-pattern roads, towns get radial spoke roads with ring.

func get_priority() -> int:
    return 57  # After inter-settlement roads (56), before buildings (65)

func get_dependencies() -> Array[String]:
    return ["settlements"]

func get_optional_params() -> Dictionary:
    return {
        "enable_settlement_roads": true,
        "city_road_spacing": 60.0,  # Dense grid for buildings (was 75)
        "town_spoke_count": 8,  # Moderate spokes (was 10)
        "settlement_road_width": 10.0,  # Narrower settlement roads
        "town_ring_radius_ratio": 0.70,  # Ring road at 70% of town radius
        "city_ring_count": 2,  # Number of ring roads for cities
        "city_inner_ring_ratio": 0.4,  # Inner downtown ring at 40%
        "city_outer_ring_ratio": 0.75,  # Outer beltway at 75%
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if not bool(params.get("enable_settlement_roads", true)):
        return

    if ctx == null or ctx.terrain_generator == null:
        push_error("SettlementRoadsComponent: missing ctx or terrain_generator")
        return

    if ctx.settlements.is_empty():
        return

    var roads_root := Node3D.new()
    roads_root.name = "SettlementRoads"
    ctx.get_layer("Infrastructure").add_child(roads_root)

    var road_mat := StandardMaterial3D.new()
    road_mat.albedo_color = Color(0.08, 0.08, 0.09)  # Dark for contrast
    road_mat.roughness = 0.98
    road_mat.metallic = 0.0

    var road_width: float = float(params.get("settlement_road_width", 12.0))
    var city_spacing: float = float(params.get("city_road_spacing", 75.0))
    var town_spokes: int = int(params.get("town_spoke_count", 10))
    var ring_ratio: float = float(params.get("town_ring_radius_ratio", 0.65))
    var city_ring_count: int = int(params.get("city_ring_count", 2))  # Number of ring roads for cities
    var city_inner_ring_ratio: float = float(params.get("city_inner_ring_ratio", 0.4))  # Inner ring at 40%
    var city_outer_ring_ratio: float = float(params.get("city_outer_ring_ratio", 0.75))  # Outer ring at 75%

    # Generate roads for each settlement
    for settlement in ctx.settlements:
        if not (settlement is Dictionary):
            continue

        var s_type: String = str(settlement.get("type", ""))
        var center: Vector3 = settlement.get("center", Vector3.ZERO)
        var radius: float = settlement.get("radius", 200.0)

        # Skip hamlets and industry (too small for internal roads)
        if s_type == "hamlet" or s_type == "industry":
            continue

        if s_type == "city":
            _create_city_road_grid(roads_root, center, radius, city_spacing, road_mat, road_width)
            # Add ring roads for cities (beltways)
            _create_city_ring_roads(roads_root, center, radius, city_inner_ring_ratio, city_outer_ring_ratio, road_mat, road_width * 1.2)
        elif s_type == "town":
            _create_town_radial_roads(roads_root, center, radius, town_spokes, ring_ratio, road_mat, road_width)


func _create_city_road_grid(
    parent: Node3D,
    center: Vector3,
    radius: float,
    spacing: float,
    road_mat: Material,
    road_width: float
) -> void:
    # Create straight grid roads (no A* needed!)
    # Use 0.85 factor to keep roads inside settlement boundary
    var road_extent: float = radius * 0.85
    var count: int = int(road_extent * 2.0 / spacing)

    # North-south roads
    for i in range(-count/2, count/2 + 1):
        var x: float = center.x + float(i) * spacing

        # Clip road length to circular boundary
        var start := Vector3(x, 0, center.z - road_extent)
        var end := Vector3(x, 0, center.z + road_extent)

        # Further clip if road is near edge of circle
        var road_offset: float = abs(float(i) * spacing)
        if road_offset > road_extent:
            continue

        var max_z: float = sqrt(road_extent * road_extent - road_offset * road_offset)
        start.z = center.z - max_z
        end.z = center.z + max_z

        var path: PackedVector3Array = _create_straight_road_path(start, end, 15.0)
        if path.size() > 1:
            var mesh_inst: MeshInstance3D = _create_simple_road_mesh(path, road_width, road_mat)
            if mesh_inst != null:
                mesh_inst.name = "GridRoad_NS_%d" % i
                parent.add_child(mesh_inst)
                _store_road_path(path, road_width)

    # East-west roads
    for j in range(-count/2, count/2 + 1):
        var z: float = center.z + float(j) * spacing

        # Clip road length to circular boundary
        var start := Vector3(center.x - road_extent, 0, z)
        var end := Vector3(center.x + road_extent, 0, z)

        # Further clip if road is near edge of circle
        var road_offset: float = abs(float(j) * spacing)
        if road_offset > road_extent:
            continue

        var max_x: float = sqrt(road_extent * road_extent - road_offset * road_offset)
        start.x = center.x - max_x
        end.x = center.x + max_x

        var path: PackedVector3Array = _create_straight_road_path(start, end, 15.0)
        if path.size() > 1:
            var mesh_inst: MeshInstance3D = _create_simple_road_mesh(path, road_width, road_mat)
            if mesh_inst != null:
                mesh_inst.name = "GridRoad_EW_%d" % j
                parent.add_child(mesh_inst)
                _store_road_path(path, road_width)


func _create_city_ring_roads(
    parent: Node3D,
    center: Vector3,
    radius: float,
    inner_ratio: float,
    outer_ratio: float,
    road_mat: Material,
    road_width: float
) -> void:
    # Create inner ring road (downtown loop)
    var inner_radius: float = radius * inner_ratio
    var inner_segments: int = 32  # Smooth circle
    var inner_points: Array[Vector3] = []

    for i in range(inner_segments):
        var angle: float = float(i) * TAU / float(inner_segments)
        var x: float = center.x + cos(angle) * inner_radius
        var z: float = center.z + sin(angle) * inner_radius
        var y: float = ctx.terrain_generator.get_height_at(x, z) + 0.8
        inner_points.append(Vector3(x, y, z))

    if inner_points.size() >= 3:
        _create_ring_road(parent, inner_points, road_width, road_mat)

    # Create outer ring road (beltway)
    var outer_radius: float = radius * outer_ratio
    var outer_segments: int = 48  # Larger, smoother circle
    var outer_points: Array[Vector3] = []

    for i in range(outer_segments):
        var angle: float = float(i) * TAU / float(outer_segments)
        var x: float = center.x + cos(angle) * outer_radius
        var z: float = center.z + sin(angle) * outer_radius
        var y: float = ctx.terrain_generator.get_height_at(x, z) + 0.8
        outer_points.append(Vector3(x, y, z))

    if outer_points.size() >= 3:
        _create_ring_road(parent, outer_points, road_width * 1.1, road_mat)


func _create_town_radial_roads(
    parent: Node3D,
    center: Vector3,
    radius: float,
    spoke_count: int,
    ring_ratio: float,
    road_mat: Material,
    road_width: float
) -> void:
    # Create radial spokes from center (stay within 0.9 of radius)
    var spoke_extent: float = radius * 0.9
    var ring_points: Array[Vector3] = []
    var ring_radius: float = radius * ring_ratio

    for i in range(spoke_count):
        var angle: float = float(i) * TAU / float(spoke_count)
        var end_x: float = center.x + cos(angle) * spoke_extent
        var end_z: float = center.z + sin(angle) * spoke_extent

        var start := center
        var end := Vector3(end_x, 0, end_z)

        # Create spoke road
        var path: PackedVector3Array = _create_straight_road_path(start, end, 15.0)
        if path.size() > 1:
            var mesh_inst: MeshInstance3D = _create_simple_road_mesh(path, road_width * 0.85, road_mat)
            if mesh_inst != null:
                mesh_inst.name = "Spoke_%d" % i
                parent.add_child(mesh_inst)
                _store_road_path(path, road_width * 0.85)

        # Store ring intersection point
        var ring_x: float = center.x + cos(angle) * ring_radius
        var ring_z: float = center.z + sin(angle) * ring_radius
        var ring_y: float = ctx.terrain_generator.get_height_at(ring_x, ring_z) + 0.8  # 80cm above terrain
        ring_points.append(Vector3(ring_x, ring_y, ring_z))

    # Create ring road connecting all spokes
    if ring_points.size() >= 3:
        _create_ring_road(parent, ring_points, road_width * 0.75, road_mat)


## Create a ring road from a set of points
func _create_ring_road(parent: Node3D, ring_points: Array[Vector3], road_width: float, road_mat: Material) -> void:
    for i in range(ring_points.size()):
        var start: Vector3 = ring_points[i]
        var end: Vector3 = ring_points[(i + 1) % ring_points.size()]

        var path: PackedVector3Array = _create_straight_road_path(start, end, 10.0)
        if path.size() > 1:
            var mesh_inst: MeshInstance3D = _create_simple_road_mesh(path, road_width, road_mat)
            if mesh_inst != null:
                mesh_inst.name = "Ring_%d" % i
                parent.add_child(mesh_inst)
                _store_road_path(path, road_width)


## Create a straight road path between two points, densified and projected to terrain
func _create_straight_road_path(start: Vector3, end: Vector3, density: float) -> PackedVector3Array:
    var path := PackedVector3Array()
    var dist: float = start.distance_to(end)
    var segments: int = maxi(2, int(dist / density))

    for i in range(segments + 1):
        var t: float = float(i) / float(segments)
        var p: Vector3 = start.lerp(end, t)

        # Project to terrain with substantial offset
        if ctx != null and ctx.terrain_generator != null:
            p.y = ctx.terrain_generator.get_height_at(p.x, p.z) + 0.5  # Consistent offset with other roads

        path.append(p)

    return path


## Create a simple road mesh with thickness
func _create_simple_road_mesh(path: PackedVector3Array, width: float, material: Material) -> MeshInstance3D:
    if path.size() < 2:
        return null

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var dist_along: float = 0.0
    var thickness: float = 0.3  # 30cm thick roads

    for i in range(path.size() - 1):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]

        # Use flattened XZ direction to avoid vertical twist
        var dir_xz: Vector3 = Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
        var right: Vector3 = dir_xz.cross(Vector3.UP).normalized() * width * 0.5

        # Top surface vertices - use path Y values (already correct)
        var v0_top: Vector3 = p0 - right
        var v1_top: Vector3 = p0 + right
        var v2_top: Vector3 = p1 + right
        var v3_top: Vector3 = p1 - right

        # Use path Y values directly (already calculated correctly in path generation)
        v0_top.y = p0.y
        v1_top.y = p0.y
        v2_top.y = p1.y
        v3_top.y = p1.y

        # Bottom surface vertices (for thickness)
        var v0_bot: Vector3 = v0_top - Vector3.UP * thickness
        var v1_bot: Vector3 = v1_top - Vector3.UP * thickness
        var v2_bot: Vector3 = v2_top - Vector3.UP * thickness
        var v3_bot: Vector3 = v3_top - Vector3.UP * thickness

        var segment_length: float = p0.distance_to(p1)
        var u_scale: float = 0.05
        var uv_start: float = dist_along * u_scale
        var uv_end: float = (dist_along + segment_length) * u_scale

        # Get terrain normals for better lighting
        var n0: Vector3 = _get_terrain_normal(v0_top.x, v0_top.z)
        var n1: Vector3 = _get_terrain_normal(v1_top.x, v1_top.z)
        var n2: Vector3 = _get_terrain_normal(v2_top.x, v2_top.z)
        var n3: Vector3 = _get_terrain_normal(v3_top.x, v3_top.z)

        # TOP SURFACE
        st.set_normal(n0); st.set_uv(Vector2(0.0, uv_start)); st.add_vertex(v0_top)
        st.set_normal(n2); st.set_uv(Vector2(1.0, uv_end)); st.add_vertex(v2_top)
        st.set_normal(n1); st.set_uv(Vector2(1.0, uv_start)); st.add_vertex(v1_top)

        st.set_normal(n0); st.set_uv(Vector2(0.0, uv_start)); st.add_vertex(v0_top)
        st.set_normal(n3); st.set_uv(Vector2(0.0, uv_end)); st.add_vertex(v3_top)
        st.set_normal(n2); st.set_uv(Vector2(1.0, uv_end)); st.add_vertex(v2_top)

        # LEFT SIDE
        var side_normal: Vector3 = -right.normalized()
        st.set_normal(side_normal); st.set_uv(Vector2(0.0, uv_start)); st.add_vertex(v0_top)
        st.set_normal(side_normal); st.set_uv(Vector2(0.0, uv_end)); st.add_vertex(v3_top)
        st.set_normal(side_normal); st.set_uv(Vector2(0.1, uv_start)); st.add_vertex(v0_bot)

        st.set_normal(side_normal); st.set_uv(Vector2(0.1, uv_start)); st.add_vertex(v0_bot)
        st.set_normal(side_normal); st.set_uv(Vector2(0.0, uv_end)); st.add_vertex(v3_top)
        st.set_normal(side_normal); st.set_uv(Vector2(0.1, uv_end)); st.add_vertex(v3_bot)

        # RIGHT SIDE
        side_normal = right.normalized()
        st.set_normal(side_normal); st.set_uv(Vector2(0.0, uv_start)); st.add_vertex(v1_top)
        st.set_normal(side_normal); st.set_uv(Vector2(0.1, uv_start)); st.add_vertex(v1_bot)
        st.set_normal(side_normal); st.set_uv(Vector2(0.0, uv_end)); st.add_vertex(v2_top)

        st.set_normal(side_normal); st.set_uv(Vector2(0.1, uv_start)); st.add_vertex(v1_bot)
        st.set_normal(side_normal); st.set_uv(Vector2(0.1, uv_end)); st.add_vertex(v2_bot)
        st.set_normal(side_normal); st.set_uv(Vector2(0.0, uv_end)); st.add_vertex(v2_top)

        dist_along += segment_length

    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    if material != null:
        mi.material_override = material
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mi


## Get terrain normal for better lighting
func _get_terrain_normal(x: float, z: float) -> Vector3:
    if ctx == null or ctx.terrain_generator == null:
        return Vector3.UP
    return ctx.terrain_generator.get_normal_at(x, z)


## Store road path for collision/gameplay use
func _store_road_path(path: PackedVector3Array, width: float) -> void:
    if ctx == null:
        return

    var road_lines: Array = ctx.get_data("settlement_road_lines") if ctx.has_data("settlement_road_lines") else []
    road_lines.append({"path": path, "width": width})
    ctx.set_data("settlement_road_lines", road_lines)
