extends WorldComponentBase
class_name OrganicRoadNetworkComponent

## Connects waypoints with terrain-aware organic road network
## Uses MST + loop edges similar to RoadNetworkGenerator but for waypoints
## Priority: 55 (after waypoints, before density analysis)

const RoadModule = preload("res://scripts/world/modules/road_module.gd")

func get_priority() -> int:
    return 55

func get_dependencies() -> Array[String]:
    return ["waypoints", "heightmap"]

func get_optional_params() -> Dictionary:
    return {
        "road_density_multiplier": 2.5,
        "road_highway_threshold": 5000.0,
        "road_arterial_threshold": 1000.0,
        "road_k_neighbors": 4,  # Connect each waypoint to k nearest neighbors
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("OrganicRoadNetworkComponent: missing ctx/terrain_generator")
        return

    if not ctx.has_data("waypoints"):
        push_warning("OrganicRoadNetworkComponent: no waypoints available")
        ctx.set_data("organic_roads", [])
        return

    var waypoints: Array = ctx.get_data("waypoints")

    if waypoints.size() < 2:
        push_warning("OrganicRoadNetwork: Need at least 2 waypoints")
        ctx.set_data("organic_roads", [])
        return

    # Build candidate edges between waypoints
    var k_neighbors: int = int(params.get("road_k_neighbors", 4))
    var candidate_edges := _build_candidate_edges(waypoints, k_neighbors)

    # Build MST using Kruskal's algorithm
    var mst_edges := _build_mst(candidate_edges, waypoints)

    # Add loop edges for redundancy
    var density_multiplier: float = float(params.get("road_density_multiplier", 2.5))
    var final_edges := _add_loop_edges(mst_edges, candidate_edges, density_multiplier, rng)

    print("🛣️ OrganicRoadNetwork: %d waypoints, %d candidate edges, %d MST edges, %d final edges" % [
        waypoints.size(), candidate_edges.size(), mst_edges.size(), final_edges.size()
    ])

    # Build roads from final edges using RoadModule for A* pathfinding
    var roads := _build_roads_from_edges(final_edges, params)

    # Classify road hierarchy based on length
    _classify_road_hierarchy(roads, params)

    ctx.set_data("organic_roads", roads)
    print("OrganicRoadNetwork: Generated ", roads.size(), " roads connecting ", waypoints.size(), " waypoints")

    # Print road distribution for debugging
    if roads.size() > 0:
        var avg_x = 0.0
        var avg_z = 0.0
        var count = 0
        for road in roads:
            var path: PackedVector3Array = road.path
            for point in path:
                avg_x += point.x
                avg_z += point.z
                count += 1

        if count > 0:
            avg_x /= count
            avg_z /= count
            print("   Average road position: (", avg_x, ", ", avg_z, ")")

        # Print some sample road endpoints
        print("   Sample road endpoints (first 5):")
        for i in range(min(5, roads.size())):
            var road = roads[i]
            var path: PackedVector3Array = road.path
            if path.size() >= 2:
                var start = path[0]
                var end = path[-1]  # Last element
                print("     ", i, ": from (", start.x, ", ", start.z, ") to (", end.x, ", ", end.z, ")")

func _build_candidate_edges(waypoints: Array, k: int) -> Array:
    var edges := []
    var n := waypoints.size()

    # For each waypoint, connect to k nearest neighbors
    for i in range(n):
        var wp_i: Dictionary = waypoints[i]
        var pi: Vector3 = wp_i.position

        # Build distance list to all other waypoints
        var distances := []
        for j in range(n):
            if i == j:
                continue
            var wp_j: Dictionary = waypoints[j]
            var pj: Vector3 = wp_j.position

            var dist: float = pi.distance_to(pj)
            var slope_penalty := _estimate_slope_cost(pi, pj)
            var water_penalty := _estimate_water_cost(pi, pj)
            var weight: float = dist + slope_penalty + water_penalty

            distances.append({"idx": j, "weight": weight, "dist": dist})

        # Sort by weight
        distances.sort_custom(func(a, b): return a.weight < b.weight)

        # Connect to k nearest neighbors
        for neighbor_idx in range(min(k, distances.size())):
            var neighbor_data: Dictionary = distances[neighbor_idx]
            var j: int = neighbor_data.idx
            var wp_j: Dictionary = waypoints[j]
            var pj: Vector3 = wp_j.position

            # Add edge (avoid duplicates by checking i < j)
            if i < j:
                edges.append({
                    "from": pi,
                    "to": pj,
                    "weight": neighbor_data.weight,
                    "dist": neighbor_data.dist,
                    "from_idx": i,
                    "to_idx": j
                })

    return edges

func _estimate_slope_cost(a: Vector3, b: Vector3) -> float:
    # Sample 5 points along the line
    var total_penalty := 0.0
    var samples := 5

    for i in range(samples):
        var t: float = float(i) / float(samples - 1)
        var p: Vector3 = a.lerp(b, t)
        var slope: float = ctx.terrain_generator.get_slope_at(p.x, p.z)

        if slope > 14.0:
            total_penalty += 70.0 * (slope / 45.0)

    return total_penalty / float(samples)

func _estimate_water_cost(a: Vector3, b: Vector3) -> float:
    # Sample 5 points along the line
    var water_count := 0
    var samples := 5
    var sea_level: float = float(ctx.params.get("sea_level", 20.0))

    for i in range(samples):
        var t: float = float(i) / float(samples - 1)
        var p: Vector3 = a.lerp(b, t)
        var h: float = ctx.terrain_generator.get_height_at(p.x, p.z)

        if h < sea_level:
            water_count += 1

    # Penalty proportional to water crossings
    return float(water_count) * 35.0

func _build_mst(edges: Array, waypoints: Array) -> Array:
    # Sort edges by weight
    var sorted_edges := edges.duplicate()
    sorted_edges.sort_custom(func(a, b): return a.weight < b.weight)

    # Union-Find data structure
    var parent := []
    parent.resize(waypoints.size())
    for i in range(waypoints.size()):
        parent[i] = i

    var find_root = func(x: int) -> int:
        var root: int = x
        while parent[root] != root:
            root = parent[root]
        # Path compression
        var node: int = x
        while node != root:
            var next: int = parent[node]
            parent[node] = root
            node = next
        return root

    # Kruskal's algorithm
    var mst := []
    for edge in sorted_edges:
        var from_idx: int = edge.from_idx
        var to_idx: int = edge.to_idx

        var root_from: int = find_root.call(from_idx)
        var root_to: int = find_root.call(to_idx)

        # If not in same set, add edge to MST
        if root_from != root_to:
            mst.append(edge)
            parent[root_from] = root_to

    return mst

func _add_loop_edges(mst_edges: Array, candidate_edges: Array, density_multiplier: float, rng: RandomNumberGenerator) -> Array:
    var final := mst_edges.duplicate()
    var target_count := int(float(mst_edges.size()) * density_multiplier)

    # Add random candidate edges that aren't in MST
    var available := []
    for edge in candidate_edges:
        var in_mst := false
        for mst_edge in mst_edges:
            if (edge.from_idx == mst_edge.from_idx and edge.to_idx == mst_edge.to_idx) or \
               (edge.from_idx == mst_edge.to_idx and edge.to_idx == mst_edge.from_idx):
                in_mst = true
                break
        if not in_mst:
            available.append(edge)

    # Shuffle and add up to target count
    available.shuffle()
    var to_add := mini(available.size(), target_count - mst_edges.size())
    for i in range(to_add):
        final.append(available[i])

    return final

func _build_roads_from_edges(edges: Array, params: Dictionary) -> Array:
    var roads := []
    var road_module := RoadModule.new()
    road_module.set_terrain_generator(ctx.terrain_generator)
    road_module.world_ctx = ctx

    # Create roads root node for visual meshes
    var infra: Node3D = ctx.get_layer("Infrastructure")
    var roads_root := Node3D.new()
    roads_root.name = "OrganicRoadNetwork"
    infra.add_child(roads_root)

    # Material for roads
    var road_mat := StandardMaterial3D.new()
    road_mat.roughness = 0.95
    road_mat.metallic = 0.0
    road_mat.albedo_color = Color(0.08, 0.08, 0.085)
    road_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)

    for edge in edges:
        var from: Vector3 = edge.from
        var to: Vector3 = edge.to

        # Use RoadModule A* pathfinding with coarser grid for long-distance roads
        # Grid resolution scales with distance: 24m for short roads, up to 60m for very long roads
        var distance: float = from.distance_to(to)
        var grid_res: float = clamp(24.0 + (distance / 400.0), 24.0, 60.0)

        var path: PackedVector3Array = road_module.generate_road(from, to, {
            "smooth": true,
            "allow_bridges": true,
            "grid_resolution": grid_res
        })

        if path.size() < 2:
            push_warning("Road pathfinding failed, using straight line")
            path = PackedVector3Array([from, to])

        # Create visual mesh for this road
        var temp_width := 12.0  # Will be reclassified later
        var road_mesh: MeshInstance3D = road_module.create_road_mesh(path, temp_width, road_mat)
        if road_mesh != null:
            road_mesh.name = "Road"
            roads_root.add_child(road_mesh)

        # Store road data
        roads.append({
            "path": path,
            "width": 12.0,  # Default width, will be reclassified
            "type": "local",
            "from": from,
            "to": to,
            "weight": edge.weight
        })

    return roads

func _classify_road_hierarchy(roads: Array, params: Dictionary) -> void:
    var highway_threshold: float = float(params.get("road_highway_threshold", 5000.0))
    var arterial_threshold: float = float(params.get("road_arterial_threshold", 1000.0))

    for road in roads:
        var path: PackedVector3Array = road.path
        var length := _calculate_path_length(path)

        if length > highway_threshold:
            road.type = "highway"
            road.width = 24.0
        elif length > arterial_threshold:
            road.type = "arterial"
            road.width = 16.0
        else:
            road.type = "local"
            road.width = 10.0

func _calculate_path_length(path: PackedVector3Array) -> float:
    var length := 0.0
    for i in range(1, path.size()):
        length += path[i].distance_to(path[i - 1])
    return length
