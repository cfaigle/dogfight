extends WorldComponentBase
class_name RegionalRoadsComponent

## Creates an ORGANIC road network connecting all interesting destinations.
## NO GRIDS - roads grow naturally to connect towns, farms, coastlines, landmarks.
## Hierarchy: trunk highways → arterial branches → country lanes

func get_priority() -> int:
    return 55  # After settlement planning, before road_network

func get_dependencies() -> Array[String]:
    return ["settlements"]  # Need to know where towns are

func get_optional_params() -> Dictionary:
    return {
        "enable_regional_roads": true,
        "trunk_highway_width": 24.0,
        "arterial_road_width": 16.0,
        "country_lane_width": 10.0,
        "coastline_access_points": 8,  # Number of beach/port access roads
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if not bool(params.get("enable_regional_roads", true)):
        return

    if ctx == null or ctx.terrain_generator == null:
        push_error("RegionalRoadsComponent: missing ctx or terrain_generator")
        return

    if ctx.settlements.is_empty():
        push_warning("RegionalRoadsComponent: no settlements to connect")
        return

    var roads_root := Node3D.new()
    roads_root.name = "RegionalRoads"
    ctx.get_layer("Infrastructure").add_child(roads_root)

    var highway_width: float = float(params.get("trunk_highway_width", 24.0))
    var arterial_width: float = float(params.get("arterial_road_width", 16.0))
    var lane_width: float = float(params.get("country_lane_width", 10.0))

    var highway_mat := StandardMaterial3D.new()
    highway_mat.albedo_color = Color(0.12, 0.12, 0.13)
    highway_mat.roughness = 0.92
    highway_mat.metallic = 0.05

    var arterial_mat := StandardMaterial3D.new()
    arterial_mat.albedo_color = Color(0.10, 0.10, 0.11)
    arterial_mat.roughness = 0.94

    var lane_mat := StandardMaterial3D.new()
    lane_mat.albedo_color = Color(0.09, 0.09, 0.10)
    lane_mat.roughness = 0.96

    # PHASE 1: Identify all destinations
    var destinations: Array = _gather_destinations(params, rng)
    print("🗺️ Found %d destinations to connect" % destinations.size())

    # PHASE 2: Build trunk highways (MST + loops)
    var trunk_roads: Array = _build_trunk_highways(destinations, roads_root, highway_width, highway_mat, rng)
    print("🛣️ Built %d trunk highways" % trunk_roads.size())

    # PHASE 3: Branch arterial roads to secondary destinations
    var arterial_roads: Array = _build_arterial_branches(destinations, trunk_roads, roads_root, arterial_width, arterial_mat, rng)
    print("🛤️ Added %d arterial branches" % arterial_roads.size())

    # PHASE 4: Country lanes to rural areas (if farms exist)
    var lane_roads: Array = _build_country_lanes(destinations, trunk_roads + arterial_roads, roads_root, lane_width, lane_mat, rng)
    print("🌾 Added %d country lanes" % lane_roads.size())

    # Store all roads for building placement
    var all_roads: Array = trunk_roads + arterial_roads + lane_roads
    ctx.set_data("regional_roads", all_roads)
    print("✅ Regional road network complete: %d total roads" % all_roads.size())


## Gather all interesting destinations that need road access
func _gather_destinations(params: Dictionary, rng: RandomNumberGenerator) -> Array:
    var dests: Array = []

    # 1. Major settlements (priority 1)
    for settlement in ctx.settlements:
        if settlement is Dictionary:
            var s_type: String = settlement.get("type", "")
            var priority: int = 1 if s_type == "city" else 2 if s_type == "town" else 3
            dests.append({
                "type": "settlement",
                "subtype": s_type,
                "position": settlement.get("center", Vector3.ZERO),
                "priority": priority
            })

    # 2. Coastline access points
    var coast_count: int = int(params.get("coastline_access_points", 8))
    var terrain_size: float = float(Game.settings.get("terrain_size", 12000.0))
    var half_size: float = terrain_size * 0.5

    for i in range(coast_count):
        var angle: float = float(i) * TAU / float(coast_count) + rng.randf_range(-0.2, 0.2)
        var dist: float = half_size * 0.9
        var x: float = cos(angle) * dist
        var z: float = sin(angle) * dist
        var h: float = ctx.terrain_generator.get_height_at(x, z)

        # Only add if near water
        if h < float(Game.sea_level) + 5.0:
            dests.append({
                "type": "coastline",
                "position": Vector3(x, h, z),
                "priority": 4
            })

    # 3. Landmarks (if available)
    if ctx.has_data("landmarks"):
        var landmarks: Array = ctx.get_data("landmarks")
        for landmark in landmarks:
            if landmark is Dictionary:
                dests.append({
                    "type": "landmark",
                    "position": landmark.get("position", Vector3.ZERO),
                    "priority": 3
                })

    return dests


## Build trunk highways connecting major destinations (MST + loops)
func _build_trunk_highways(destinations: Array, parent: Node3D, width: float, mat: Material, rng: RandomNumberGenerator) -> Array:
    var roads: Array = []

    # Filter to high-priority destinations (cities, towns, major landmarks)
    var major_dests: Array = []
    for dest in destinations:
        if dest is Dictionary and dest.get("priority", 999) <= 2:
            major_dests.append(dest)

    if major_dests.size() < 2:
        return roads

    # Build MST
    var mst_edges: Array = _build_destination_mst(major_dests)

    # Add loop edges (1.5x MST for redundancy)
    var target_count: int = int(float(mst_edges.size()) * 2.5)
    var all_edges: Array = _build_all_edges(major_dests)
    var final_edges: Array = _add_best_edges(mst_edges, all_edges, target_count)

    # Build road meshes
    for edge in final_edges:
        var path: PackedVector3Array = _create_organic_road_path(edge.from, edge.to, width)
        if path.size() > 1:
            var mi: MeshInstance3D = _create_road_mesh(path, width, mat)
            mi.name = "Highway_%d" % roads.size()
            parent.add_child(mi)
            roads.append({
                "path": path,
                "width": width,
                "type": "highway",
                "from": edge.from,
                "to": edge.to
            })

    return roads


## Build arterial roads branching from highways to secondary destinations
func _build_arterial_branches(destinations: Array, trunk_roads: Array, parent: Node3D, width: float, mat: Material, rng: RandomNumberGenerator) -> Array:
    var roads: Array = []

    # Filter to medium-priority destinations (hamlets, minor landmarks)
    var secondary_dests: Array = []
    for dest in destinations:
        if dest is Dictionary and dest.get("priority", 999) == 3:
            secondary_dests.append(dest)

    # For each secondary destination, connect to nearest highway point
    for dest in secondary_dests:
        if not dest is Dictionary:
            continue

        var pos: Vector3 = dest.get("position", Vector3.ZERO)
        if pos == Vector3.ZERO:
            continue

        # Find nearest point on any trunk road
        var nearest_point: Vector3 = _find_nearest_road_point(pos, trunk_roads)
        if nearest_point != Vector3.ZERO:
            var path: PackedVector3Array = _create_organic_road_path(nearest_point, pos, width)
            if path.size() > 1:
                var mi: MeshInstance3D = _create_road_mesh(path, width, mat)
                mi.name = "Arterial_%d" % roads.size()
                parent.add_child(mi)
                roads.append({
                    "path": path,
                    "width": width,
                    "type": "arterial",
                    "from": nearest_point,
                    "to": pos
                })

    return roads


## Build country lanes to low-priority rural destinations
func _build_country_lanes(destinations: Array, existing_roads: Array, parent: Node3D, width: float, mat: Material, rng: RandomNumberGenerator) -> Array:
    var roads: Array = []

    # Filter to low-priority destinations (coastline access, rural)
    var rural_dests: Array = []
    for dest in destinations:
        if dest is Dictionary and dest.get("priority", 999) >= 4:
            rural_dests.append(dest)

    # Connect to nearest road
    for dest in rural_dests:
        if not dest is Dictionary:
            continue

        var pos: Vector3 = dest.get("position", Vector3.ZERO)
        if pos == Vector3.ZERO:
            continue

        var nearest_point: Vector3 = _find_nearest_road_point(pos, existing_roads)
        if nearest_point != Vector3.ZERO and nearest_point.distance_to(pos) > 100.0:  # Don't add very short lanes
            var path: PackedVector3Array = _create_organic_road_path(nearest_point, pos, width)
            if path.size() > 1:
                var mi: MeshInstance3D = _create_road_mesh(path, width, mat)
                mi.name = "Lane_%d" % roads.size()
                parent.add_child(mi)
                roads.append({
                    "path": path,
                    "width": width,
                    "type": "lane",
                    "from": nearest_point,
                    "to": pos
                })

    return roads


## Find nearest point on any road to a target position
func _find_nearest_road_point(target: Vector3, roads: Array) -> Vector3:
    var nearest: Vector3 = Vector3.ZERO
    var min_dist: float = INF

    for road in roads:
        if not road is Dictionary:
            continue

        var path: PackedVector3Array = road.get("path", PackedVector3Array())
        for point in path:
            var dist: float = target.distance_to(point)
            if dist < min_dist:
                min_dist = dist
                nearest = point

    return nearest


## Build MST from destinations
func _build_destination_mst(destinations: Array) -> Array:
    var all_edges: Array = _build_all_edges(destinations)
    all_edges.sort_custom(func(a, b): return a.weight < b.weight)

    var parent: Array = []
    parent.resize(destinations.size())
    for i in range(destinations.size()):
        parent[i] = i

    var find_root = func(x: int) -> int:
        while parent[x] != x:
            x = parent[x]
        return x

    var mst: Array = []
    for edge in all_edges:
        var rx: int = find_root.call(edge.from_idx)
        var ry: int = find_root.call(edge.to_idx)
        if rx != ry:
            mst.append(edge)
            parent[rx] = ry
            if mst.size() >= destinations.size() - 1:
                break

    return mst


## Build all possible edges between destinations
func _build_all_edges(destinations: Array) -> Array:
    var edges: Array = []
    for i in range(destinations.size()):
        var di: Dictionary = destinations[i] as Dictionary
        var pi: Vector3 = di.get("position", Vector3.ZERO)
        for j in range(i + 1, destinations.size()):
            var dj: Dictionary = destinations[j] as Dictionary
            var pj: Vector3 = dj.get("position", Vector3.ZERO)
            var dist: float = pi.distance_to(pj)
            edges.append({
                "from": pi,
                "to": pj,
                "weight": dist,
                "from_idx": i,
                "to_idx": j
            })
    return edges


## Add best remaining edges for loops
func _add_best_edges(mst: Array, all_edges: Array, target: int) -> Array:
    var final: Array = mst.duplicate()
    var existing: Dictionary = {}

    for e in final:
        var key: String = "%d_%d" % [e.from_idx, e.to_idx]
        existing[key] = true

    var remaining: Array = []
    for e in all_edges:
        var key: String = "%d_%d" % [e.from_idx, e.to_idx]
        if not existing.has(key):
            remaining.append(e)

    remaining.sort_custom(func(a, b): return a.weight < b.weight)

    for e in remaining:
        if final.size() >= target:
            break
        final.append(e)

    return final


## Create organic road path (curved, follows terrain)
func _create_organic_road_path(start: Vector3, end: Vector3, width: float) -> PackedVector3Array:
    var path := PackedVector3Array()
    var dist: float = start.distance_to(end)
    var segments: int = maxi(20, int(dist / 50.0))

    for i in range(segments + 1):
        var t: float = float(i) / float(segments)
        var p: Vector3 = start.lerp(end, t)

        # Add slight curve for organic feel (wider roads = gentler curves)
        var curve_amount: float = 20.0 / (width / 10.0)
        var curve_offset: float = sin(t * PI) * curve_amount
        var perp: Vector3 = Vector3(-(end.z - start.z), 0, end.x - start.x).normalized()
        p += perp * curve_offset

        # Project to terrain
        if ctx.terrain_generator != null:
            p.y = ctx.terrain_generator.get_height_at(p.x, p.z) + 0.15

        path.append(p)

    return path


## Create road mesh
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

        if ctx.terrain_generator != null:
            v0.y = ctx.terrain_generator.get_height_at(v0.x, v0.z) + 0.15
            v1.y = ctx.terrain_generator.get_height_at(v1.x, v1.z) + 0.15
            v2.y = ctx.terrain_generator.get_height_at(v2.x, v2.z) + 0.15
            v3.y = ctx.terrain_generator.get_height_at(v3.x, v3.z) + 0.15

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
