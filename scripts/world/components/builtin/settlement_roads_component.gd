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
        var ring_y: float = ctx.terrain_generator.get_height_at(ring_x, ring_z) + 0.08
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

        # Project to terrain
        if ctx != null and ctx.terrain_generator != null:
            p.y = ctx.terrain_generator.get_height_at(p.x, p.z) + 0.08

        path.append(p)

    return path


## Create a simple road mesh (no A*, no complex pathfinding)
func _create_simple_road_mesh(path: PackedVector3Array, width: float, material: Material) -> MeshInstance3D:
    if path.size() < 2:
        return null

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var dist_along: float = 0.0

    for i in range(path.size() - 1):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]

        # Use flattened XZ direction
        var dir_xz: Vector3 = Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
        var right: Vector3 = dir_xz.cross(Vector3.UP).normalized() * width * 0.5

        var v0: Vector3 = p0 - right
        var v1: Vector3 = p0 + right
        var v2: Vector3 = p1 + right
        var v3: Vector3 = p1 - right

        # Sample terrain height for each vertex
        if ctx != null and ctx.terrain_generator != null:
            v0.y = ctx.terrain_generator.get_height_at(v0.x, v0.z) + 0.08
            v1.y = ctx.terrain_generator.get_height_at(v1.x, v1.z) + 0.08
            v2.y = ctx.terrain_generator.get_height_at(v2.x, v2.z) + 0.08
            v3.y = ctx.terrain_generator.get_height_at(v3.x, v3.z) + 0.08

        # Distance-based UVs
        var segment_length: float = p0.distance_to(p1)
        var u_scale: float = 0.05
        var uv_start: float = dist_along * u_scale
        var uv_end: float = (dist_along + segment_length) * u_scale

        # Add triangles
        st.set_normal(Vector3.UP); st.set_uv(Vector2(0.0, uv_start)); st.add_vertex(v0)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(1.0, uv_end)); st.add_vertex(v2)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(1.0, uv_start)); st.add_vertex(v1)

        st.set_normal(Vector3.UP); st.set_uv(Vector2(0.0, uv_start)); st.add_vertex(v0)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(0.0, uv_end)); st.add_vertex(v3)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(1.0, uv_end)); st.add_vertex(v2)

        dist_along += segment_length

    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    if material != null:
        mi.material_override = material
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mi


## Store road path for collision/gameplay use
func _store_road_path(path: PackedVector3Array, width: float) -> void:
    if ctx == null:
        return

    var road_lines: Array = ctx.get_data("settlement_road_lines") if ctx.has_data("settlement_road_lines") else []
    road_lines.append({"path": path, "width": width})
    ctx.set_data("settlement_road_lines", road_lines)
