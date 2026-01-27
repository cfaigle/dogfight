class_name RoadNetworkGenerator
extends RefCounted

## Builds the inter-settlement road/highway network using MST + loop edges.

var _terrain: TerrainGenerator = null

func set_terrain_generator(t: TerrainGenerator) -> void:
    _terrain = t

func generate(ctx: WorldContext, params: Dictionary, rng: RandomNumberGenerator) -> Array:
    var roads: Array = []
    if _terrain == null:
        push_warning("RoadNetworkGenerator: No terrain generator set")
        return roads
    if ctx.settlements.is_empty():
        push_warning("RoadNetworkGenerator: No settlements found")
        return roads

    var enable_roads: bool = bool(params.get("enable_roads", true))
    if not enable_roads:
        return roads

    var road_width: float = float(params.get("road_width", 18.0))
    var highway_width: float = float(params.get("highway_width", road_width * 1.6))
    var smooth: bool = bool(params.get("road_smooth", true))
    var allow_bridges: bool = bool(params.get("allow_bridges", true))
    var k_neighbors: int = int(params.get("road_k_neighbors", 6))  # Connect to k nearest neighbors
    var road_density_target: float = float(params.get("road_density_target", 3.5))  # Extra edges multiplier (very dense network)

    var road_module := RoadModule.new()
    road_module.set_terrain_generator(_terrain)
    road_module.world_ctx = ctx
    road_module.road_width = road_width
    road_module.road_smooth = smooth
    road_module.allow_bridges = allow_bridges

    # Material (cached)
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.roughness = 0.95
    mat.metallic = 0.0
    mat.albedo_color = Color(0.08, 0.08, 0.085)
    mat.uv1_scale = Vector3(0.5, 0.5, 0.5)

    # Create roads root
    var infra: Node3D = ctx.get_layer("Infrastructure")
    var root := Node3D.new()
    root.name = "RoadNetwork"
    infra.add_child(root)

    # Build intelligent network using MST + extra edges
    var candidate_edges: Array = _build_candidate_edges(ctx.settlements, k_neighbors)
    var mst_edges: Array = _build_mst(candidate_edges, ctx.settlements)
    var final_edges: Array = _add_loop_edges(mst_edges, candidate_edges, road_density_target, rng)

    print("🛣️ Road network: %d settlements, %d candidate edges, %d MST edges, %d final edges" % [
        ctx.settlements.size(), candidate_edges.size(), mst_edges.size(), final_edges.size()
    ])

    # Track intersections for snapping
    var intersections: Dictionary = {}  # Vector3 (rounded) -> Vector3 (exact)
    var snap_distance: float = 35.0  # Snap endpoints within 35m

    # Build roads from final edges with intersection snapping
    for edge in final_edges:
        var from: Vector3 = edge.from
        var to: Vector3 = edge.to

        # Snap endpoints to nearby intersections
        from = _snap_to_intersection(from, intersections, snap_distance)
        to = _snap_to_intersection(to, intersections, snap_distance)

        var is_highway: bool = edge.weight > 9000.0  # Long roads become highways
        var w: float = highway_width if is_highway else road_width

        var pts: PackedVector3Array = road_module.generate_road(from, to, {"smooth": smooth, "allow_bridges": allow_bridges})

        # Even if pathfinding failed, we still get a fallback straight line (2 points)
        # which is fine for distant connections
        if pts.size() < 2:
            push_warning("Road generation returned empty path")
            continue

        var mi: MeshInstance3D = road_module.create_road_mesh(pts, w, mat)
        if mi != null:
            mi.name = "Highway" if is_highway else "Road"
            root.add_child(mi)
            roads.append({"from": from, "to": to, "points": pts, "width": w})

    return roads


## Build candidate edges using k-nearest-neighbors + hub connections
func _build_candidate_edges(settlements: Array, k: int) -> Array:
    var edges: Array = []
    var n: int = settlements.size()

    if n < 2:
        push_warning("RoadNetworkGenerator: Need at least 2 settlements for roads")
        return edges

    # Find city/hub for guaranteed connectivity
    var hub_idx: int = 0
    for i in range(n):
        var s: Dictionary = settlements[i] as Dictionary
        if s.get("type", "") == "city":
            hub_idx = i
            break

    # For each settlement, connect to k nearest neighbors + hub
    for i in range(n):
        var si: Dictionary = settlements[i] as Dictionary
        var pi: Vector3 = si.get("center", Vector3.ZERO)
        if pi == Vector3.ZERO:
            continue

        # Build distance list to all other settlements
        var distances: Array = []
        for j in range(n):
            if i == j:
                continue
            var sj: Dictionary = settlements[j] as Dictionary
            var pj: Vector3 = sj.get("center", Vector3.ZERO)
            if pj == Vector3.ZERO:
                continue

            var dist: float = pi.distance_to(pj)
            var slope_penalty: float = _estimate_slope_cost(pi, pj)
            var water_penalty: float = _estimate_water_cost(pi, pj)
            var weight: float = dist + slope_penalty + water_penalty

            distances.append({"idx": j, "weight": weight, "dist": dist})

        # Sort by weight
        distances.sort_custom(func(a, b): return a.weight < b.weight)

        # Connect to k nearest neighbors
        for neighbor_idx in range(min(k, distances.size())):
            var neighbor_data: Dictionary = distances[neighbor_idx]
            var j: int = neighbor_data.idx
            var sj: Dictionary = settlements[j] as Dictionary
            var pj: Vector3 = sj.get("center", Vector3.ZERO)

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

        # Always connect to hub (if not self)
        if i != hub_idx:
            var hub: Dictionary = settlements[hub_idx] as Dictionary
            var ph: Vector3 = hub.get("center", Vector3.ZERO)
            if ph != Vector3.ZERO:
                var dist: float = pi.distance_to(ph)
                var slope_penalty: float = _estimate_slope_cost(pi, ph)
                var water_penalty: float = _estimate_water_cost(pi, ph)
                var weight: float = dist + slope_penalty + water_penalty

                # Check if edge already exists
                var exists: bool = false
                for e in edges:
                    if (e.from_idx == i and e.to_idx == hub_idx) or (e.from_idx == hub_idx and e.to_idx == i):
                        exists = true
                        break

                if not exists:
                    edges.append({
                        "from": pi if i < hub_idx else ph,
                        "to": ph if i < hub_idx else pi,
                        "weight": weight,
                        "dist": dist,
                        "from_idx": min(i, hub_idx),
                        "to_idx": max(i, hub_idx)
                    })

    return edges


## Estimate slope cost along straight line between points
func _estimate_slope_cost(a: Vector3, b: Vector3) -> float:
    if _terrain == null:
        return 0.0

    # Sample 5 points along the line
    var total_penalty: float = 0.0
    var samples: int = 5

    for i in range(samples):
        var t: float = float(i) / float(samples - 1)
        var p: Vector3 = a.lerp(b, t)
        var slope: float = _terrain.get_slope_at(p.x, p.z)

        if slope > 14.0:
            total_penalty += 70.0 * (slope / 45.0)

    return total_penalty / float(samples)


## Estimate water crossing cost along straight line
func _estimate_water_cost(a: Vector3, b: Vector3) -> float:
    if _terrain == null:
        return 0.0

    # Sample 5 points along the line
    var water_count: int = 0
    var samples: int = 5

    for i in range(samples):
        var t: float = float(i) / float(samples - 1)
        var p: Vector3 = a.lerp(b, t)
        var h: float = _terrain.get_height_at(p.x, p.z)

        if h < float(Game.sea_level):
            water_count += 1

    # Penalty proportional to water crossings
    return float(water_count) * 35.0


## Build Minimum Spanning Tree using Kruskal's algorithm
func _build_mst(edges: Array, settlements: Array) -> Array:
    # Sort edges by weight
    var sorted_edges: Array = edges.duplicate()
    sorted_edges.sort_custom(func(a, b): return a.weight < b.weight)

    # Union-Find data structure
    var parent: Array = []
    parent.resize(settlements.size())
    for i in range(settlements.size()):
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

    var union = func(x: int, y: int) -> void:
        var rx: int = find_root.call(x)
        var ry: int = find_root.call(y)
        if rx != ry:
            parent[rx] = ry

    # Build MST
    var mst: Array = []
    for edge in sorted_edges:
        var from_idx: int = edge.from_idx
        var to_idx: int = edge.to_idx

        if find_root.call(from_idx) != find_root.call(to_idx):
            mst.append(edge)
            union.call(from_idx, to_idx)

            # MST is complete when we have n-1 edges
            if mst.size() >= settlements.size() - 1:
                break

    return mst


## Add extra edges for loops until target density reached
func _add_loop_edges(mst_edges: Array, all_edges: Array, density_multiplier: float, rng: RandomNumberGenerator) -> Array:
    var final_edges: Array = mst_edges.duplicate()
    var target_count: int = int(float(mst_edges.size()) * density_multiplier)

    # Build set of existing edges for fast lookup
    var existing: Dictionary = {}
    for e in final_edges:
        var key: String = "%d_%d" % [e.from_idx, e.to_idx]
        existing[key] = true

    # Sort remaining edges by weight
    var remaining: Array = []
    for e in all_edges:
        var key: String = "%d_%d" % [e.from_idx, e.to_idx]
        if not existing.has(key):
            remaining.append(e)

    remaining.sort_custom(func(a, b): return a.weight < b.weight)

    # Add best remaining edges until target reached
    for e in remaining:
        if final_edges.size() >= target_count:
            break
        final_edges.append(e)
        var key: String = "%d_%d" % [e.from_idx, e.to_idx]
        existing[key] = true

    return final_edges


## Snap a point to nearby intersection, or register as new intersection
func _snap_to_intersection(point: Vector3, intersections: Dictionary, snap_dist: float) -> Vector3:
    # Round to grid for fast lookup (10m grid)
    var grid_size: float = 10.0
    var grid_x: int = int(round(point.x / grid_size))
    var grid_z: int = int(round(point.z / grid_size))

    # Check nearby grid cells (3x3 neighborhood)
    for dx in [-1, 0, 1]:
        for dz in [-1, 0, 1]:
            var check_key: Vector2i = Vector2i(grid_x + dx, grid_z + dz)
            if intersections.has(check_key):
                var existing_point: Vector3 = intersections[check_key]
                var dist: float = point.distance_to(existing_point)
                if dist < snap_dist:
                    # Snap to existing intersection
                    return existing_point

    # No nearby intersection found, register this as new intersection
    var key: Vector2i = Vector2i(grid_x, grid_z)
    intersections[key] = point
    return point
