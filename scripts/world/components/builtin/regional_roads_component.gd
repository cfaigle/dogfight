extends WorldComponentBase
class_name RegionalRoadsComponent

## Creates a regional road grid across the entire map.
## These highways/main roads provide vehicle connectivity before settlements exist.
## Priority 55 (before settlements at 60)

func get_priority() -> int:
    return 55  # Before settlements

func get_dependencies() -> Array[String]:
    return ["terrain_mesh"]  # Only needs terrain

func get_optional_params() -> Dictionary:
    return {
        "enable_regional_roads": true,
        "regional_road_spacing": 1500.0,  # 1.5km grid
        "regional_road_width": 18.0,
        "regional_highway_spacing": 4000.0,  # 4km for major highways
        "regional_highway_width": 24.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if not bool(params.get("enable_regional_roads", true)):
        return

    if ctx == null or ctx.terrain_generator == null:
        push_error("RegionalRoadsComponent: missing ctx or terrain_generator")
        return

    var terrain_size: float = float(Game.settings.get("terrain_size", 12000.0))
    var half_size: float = terrain_size * 0.5

    var road_spacing: float = float(params.get("regional_road_spacing", 1500.0))
    var road_width: float = float(params.get("regional_road_width", 18.0))
    var highway_spacing: float = float(params.get("regional_highway_spacing", 4000.0))
    var highway_width: float = float(params.get("regional_highway_width", 24.0))

    var roads_root := Node3D.new()
    roads_root.name = "RegionalRoads"
    ctx.get_layer("Infrastructure").add_child(roads_root)

    var road_mat := StandardMaterial3D.new()
    road_mat.albedo_color = Color(0.10, 0.10, 0.11)  # Slightly lighter for highways
    road_mat.roughness = 0.95
    road_mat.metallic = 0.0

    var highway_mat := StandardMaterial3D.new()
    highway_mat.albedo_color = Color(0.12, 0.12, 0.13)
    highway_mat.roughness = 0.92
    highway_mat.metallic = 0.05

    # Store regional roads for building placement
    var regional_road_lines: Array = []

    # Create primary highway grid (sparse, major routes)
    var highway_count: int = int(terrain_size / highway_spacing)
    for i in range(-highway_count, highway_count + 1):
        var offset: float = float(i) * highway_spacing

        # North-South highway
        if abs(offset) < half_size:
            var start := Vector3(offset, 0, -half_size)
            var end := Vector3(offset, 0, half_size)
            var path := _create_regional_road_path(start, end)
            if path.size() > 1:
                var mi := _create_road_mesh(path, highway_width, highway_mat)
                mi.name = "Highway_NS_%d" % i
                roads_root.add_child(mi)
                regional_road_lines.append({"path": path, "width": highway_width, "type": "highway"})

        # East-West highway
        if abs(offset) < half_size:
            var start := Vector3(-half_size, 0, offset)
            var end := Vector3(half_size, 0, offset)
            var path := _create_regional_road_path(start, end)
            if path.size() > 1:
                var mi := _create_road_mesh(path, highway_width, highway_mat)
                mi.name = "Highway_EW_%d" % i
                roads_root.add_child(mi)
                regional_road_lines.append({"path": path, "width": highway_width, "type": "highway"})

    # Create secondary road grid (denser, between highways)
    var road_count: int = int(terrain_size / road_spacing)
    for i in range(-road_count, road_count + 1):
        var offset: float = float(i) * road_spacing

        # Skip if too close to highway
        var near_highway: bool = false
        for h in range(-highway_count, highway_count + 1):
            if abs(offset - float(h) * highway_spacing) < highway_spacing * 0.3:
                near_highway = true
                break

        if near_highway:
            continue

        # North-South road
        if abs(offset) < half_size * 0.9:  # Slightly inside terrain bounds
            var start := Vector3(offset, 0, -half_size * 0.9)
            var end := Vector3(offset, 0, half_size * 0.9)
            var path := _create_regional_road_path(start, end)
            if path.size() > 1:
                var mi := _create_road_mesh(path, road_width, road_mat)
                mi.name = "Road_NS_%d" % i
                roads_root.add_child(mi)
                regional_road_lines.append({"path": path, "width": road_width, "type": "road"})

        # East-West road
        if abs(offset) < half_size * 0.9:
            var start := Vector3(-half_size * 0.9, 0, offset)
            var end := Vector3(half_size * 0.9, 0, offset)
            var path := _create_regional_road_path(start, end)
            if path.size() > 1:
                var mi := _create_road_mesh(path, road_width, road_mat)
                mi.name = "Road_EW_%d" % i
                roads_root.add_child(mi)
                regional_road_lines.append({"path": path, "width": road_width, "type": "road"})

    # Store regional roads in context for settlement/building placement
    ctx.set_data("regional_roads", regional_road_lines)
    print("🛣️ Regional roads: %d highways, %d total roads" % [
        highway_count * 2, regional_road_lines.size()
    ])


func _create_regional_road_path(start: Vector3, end: Vector3) -> PackedVector3Array:
    var path := PackedVector3Array()
    var dist: float = start.distance_to(end)
    var segments: int = maxi(20, int(dist / 50.0))  # Dense sampling every 50m

    for i in range(segments + 1):
        var t: float = float(i) / float(segments)
        var p: Vector3 = start.lerp(end, t)

        # Project to terrain
        if ctx.terrain_generator != null:
            p.y = ctx.terrain_generator.get_height_at(p.x, p.z) + 0.12  # Slight elevation

        path.append(p)

    return path


func _create_road_mesh(path: PackedVector3Array, width: float, material: Material) -> MeshInstance3D:
    if path.size() < 2:
        return MeshInstance3D.new()

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var dist_along: float = 0.0

    for i in range(path.size() - 1):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]

        var dir_xz: Vector3 = Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
        var right: Vector3 = dir_xz.cross(Vector3.UP).normalized() * width * 0.5

        var v0: Vector3 = p0 - right
        var v1: Vector3 = p0 + right
        var v2: Vector3 = p1 + right
        var v3: Vector3 = p1 - right

        # Sample terrain height for each vertex
        if ctx.terrain_generator != null:
            v0.y = ctx.terrain_generator.get_height_at(v0.x, v0.z) + 0.12
            v1.y = ctx.terrain_generator.get_height_at(v1.x, v1.z) + 0.12
            v2.y = ctx.terrain_generator.get_height_at(v2.x, v2.z) + 0.12
            v3.y = ctx.terrain_generator.get_height_at(v3.x, v3.z) + 0.12

        var segment_length: float = p0.distance_to(p1)
        var u_scale: float = 0.05
        var uv_start: float = dist_along * u_scale
        var uv_end: float = (dist_along + segment_length) * u_scale

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
