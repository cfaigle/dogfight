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
        "farm_lane_count": 20,  # Number of country lanes to farms/rural areas
        "farm_band": 2600.0,  # Distance from settlement to look for farm lanes
        "bridge_clearance": 15.0,  # Height above water for ships to pass (meters)
        "road_terrain_offset": 1.2,  # How far above terrain (meters)
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
    var bridge_clearance: float = float(params.get("bridge_clearance", 15.0))
    var road_offset: float = float(params.get("road_terrain_offset", 1.2))

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
    var trunk_roads: Array = _build_trunk_highways(destinations, roads_root, highway_width, highway_mat, bridge_clearance, road_offset, rng)
    print("🛣️ Built %d trunk highways" % trunk_roads.size())

    # PHASE 3: Branch arterial roads to secondary destinations
    var arterial_roads: Array = _build_arterial_branches(destinations, trunk_roads, roads_root, arterial_width, arterial_mat, bridge_clearance, road_offset, rng)
    print("🛤️ Added %d arterial branches" % arterial_roads.size())

    # PHASE 4: Country lanes to rural areas (if farms exist)
    var lane_roads: Array = _build_country_lanes(destinations, trunk_roads + arterial_roads, roads_root, lane_width, lane_mat, bridge_clearance, road_offset, rng)
    print("🌾 Added %d country lanes" % lane_roads.size())

    # Store all roads for building placement
    var all_roads: Array = trunk_roads + arterial_roads + lane_roads
    ctx.set_data("regional_roads", all_roads)

    # Store farm destinations for farms_component to use
    var farm_dests: Array = []
    for dest in destinations:
        if dest is Dictionary and dest.get("type", "") == "farm":
            farm_dests.append(dest.get("position", Vector3.ZERO))
    ctx.set_data("farm_lane_destinations", farm_dests)

    print("✅ Regional road network complete: %d total roads (%d country lanes to farms)" % [all_roads.size(), lane_roads.size()])


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

    # 4. Farm locations (rural areas around settlements)
    var farm_band: float = float(params.get("farm_band", 2600.0))
    var farm_lane_count: int = int(params.get("farm_lane_count", 20))

    for settlement in ctx.settlements:
        if not (settlement is Dictionary):
            continue

        var s_type: String = settlement.get("type", "")
        if s_type == "industry":
            continue

        var center: Vector3 = settlement.get("center", Vector3.ZERO)
        var radius: float = settlement.get("radius", 350.0)
        var zones: Dictionary = settlement.get("zones", {}) as Dictionary
        var suburb_r: float = float(zones.get("suburb_radius", radius * 1.25))

        # Find farm locations in band around settlement
        var inner: float = maxf(suburb_r, radius) + 120.0
        var outer: float = inner + farm_band
        var lanes_per_settlement: int = maxi(2, farm_lane_count / maxi(1, ctx.settlements.size()))

        for i in range(lanes_per_settlement):
            var ang: float = float(i) * TAU / float(lanes_per_settlement) + rng.randf_range(-0.3, 0.3)
            var rr: float = inner + rng.randf_range(0.3, 0.8) * (outer - inner)
            var x: float = center.x + cos(ang) * rr
            var z: float = center.z + sin(ang) * rr
            var h: float = ctx.terrain_generator.get_height_at(x, z)

            # Only add if suitable for farming (above water, not too steep)
            if h > float(Game.sea_level) + 1.0:
                var slope: float = ctx.terrain_generator.get_slope_at(x, z)
                if slope < 15.0:  # Reasonable farmland
                    dests.append({
                        "type": "farm",
                        "position": Vector3(x, h, z),
                        "priority": 5  # Lower priority than coastline
                    })

    return dests


## Build trunk highways connecting major destinations (MST + loops)
func _build_trunk_highways(destinations: Array, parent: Node3D, width: float, mat: Material, bridge_clearance: float, road_offset: float, rng: RandomNumberGenerator) -> Array:
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
        var path: PackedVector3Array = _create_organic_road_path(edge.from, edge.to, width, bridge_clearance, road_offset)
        if path.size() > 1:
            var mi: MeshInstance3D = _create_road_mesh(path, width, mat)
            mi.name = "Highway_%d" % roads.size()
            parent.add_child(mi)

            # Add bridge pillars if crossing water
            _add_bridge_pillars_to_road(parent, path, width, mat, bridge_clearance)

            roads.append({
                "path": path,
                "width": width,
                "type": "highway",
                "from": edge.from,
                "to": edge.to
            })

    return roads


## Build arterial roads branching from highways to secondary destinations
func _build_arterial_branches(destinations: Array, trunk_roads: Array, parent: Node3D, width: float, mat: Material, bridge_clearance: float, road_offset: float, rng: RandomNumberGenerator) -> Array:
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
            var path: PackedVector3Array = _create_organic_road_path(nearest_point, pos, width, bridge_clearance, road_offset)
            if path.size() > 1:
                var mi: MeshInstance3D = _create_road_mesh(path, width, mat)
                mi.name = "Arterial_%d" % roads.size()
                parent.add_child(mi)

                # Add bridge pillars if crossing water
                _add_bridge_pillars_to_road(parent, path, width, mat, bridge_clearance)

                roads.append({
                    "path": path,
                    "width": width,
                    "type": "arterial",
                    "from": nearest_point,
                    "to": pos
                })

    return roads


## Build country lanes to low-priority rural destinations
func _build_country_lanes(destinations: Array, existing_roads: Array, parent: Node3D, width: float, mat: Material, bridge_clearance: float, road_offset: float, rng: RandomNumberGenerator) -> Array:
    var roads: Array = []

    # Filter to low-priority destinations (coastline, farms, rural)
    var rural_dests: Array = []
    for dest in destinations:
        if dest is Dictionary and dest.get("priority", 999) >= 4:
            rural_dests.append(dest)

    print("🌾 Building country lanes to %d rural destinations (coastline + farms)" % rural_dests.size())

    # Connect to nearest road
    for dest in rural_dests:
        if not dest is Dictionary:
            continue

        var dest_type: String = dest.get("type", "")
        var pos: Vector3 = dest.get("position", Vector3.ZERO)
        if pos == Vector3.ZERO:
            continue

        var nearest_point: Vector3 = _find_nearest_road_point(pos, existing_roads)
        if nearest_point != Vector3.ZERO:
            var dist_to_road: float = nearest_point.distance_to(pos)

            # Farms: always connect if >100m away
            # Coastline: always connect if >100m away
            var min_dist: float = 100.0 if dest_type in ["farm", "coastline"] else 200.0

            if dist_to_road > min_dist:
                var path: PackedVector3Array = _create_organic_road_path(nearest_point, pos, width, bridge_clearance, road_offset)
                if path.size() > 1:
                    var mi: MeshInstance3D = _create_road_mesh(path, width, mat)
                    mi.name = "%s_Lane_%d" % [dest_type.capitalize(), roads.size()]
                    parent.add_child(mi)

                    # Add bridge pillars if crossing water
                    _add_bridge_pillars_to_road(parent, path, width, mat, bridge_clearance)

                    roads.append({
                        "path": path,
                        "width": width,
                        "type": "lane",
                        "subtype": dest_type,
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


## Create organic road path (curved, follows terrain OR bridges over water)
func _create_organic_road_path(start: Vector3, end: Vector3, width: float, bridge_clearance: float, road_offset: float) -> PackedVector3Array:
    var path := PackedVector3Array()
    var dist: float = start.distance_to(end)
    var segments: int = maxi(20, int(dist / 20.0))  # Even denser: 20m segments

    for i in range(segments + 1):
        var t: float = float(i) / float(segments)
        var p: Vector3 = start.lerp(end, t)

        # Add slight curve for organic feel (wider roads = gentler curves)
        var curve_amount: float = 20.0 / (width / 10.0)
        var curve_offset: float = sin(t * PI) * curve_amount
        var perp: Vector3 = Vector3(-(end.z - start.z), 0, end.x - start.x).normalized()
        p += perp * curve_offset

        # Project to terrain OR bridge deck
        if ctx.terrain_generator != null:
            var terrain_height: float = ctx.terrain_generator.get_height_at(p.x, p.z)
            var water_level: float = float(Game.sea_level)

            # Check if over water
            if terrain_height < water_level:
                # BRIDGE: Use deck height (water + clearance for ships)
                p.y = water_level + bridge_clearance
            else:
                # LAND ROAD: Use terrain + offset (adaptive based on slope)
                var slope: float = ctx.terrain_generator.get_slope_at(p.x, p.z)
                var adaptive_offset: float = road_offset + (slope * 0.1)  # Extra offset on slopes
                p.y = terrain_height + adaptive_offset

        path.append(p)

    return path


## Create road mesh with thickness
func _create_road_mesh(path: PackedVector3Array, width: float, material: Material) -> MeshInstance3D:
    if path.size() < 2:
        return MeshInstance3D.new()

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

        # Top surface vertices - use path Y values (already correct for bridges/terrain)
        var v0_top: Vector3 = p0 - right
        var v1_top: Vector3 = p0 + right
        var v2_top: Vector3 = p1 + right
        var v3_top: Vector3 = p1 - right

        # CRITICAL: Use path Y values directly! Path already has correct heights:
        #  - Land roads: terrain + adaptive offset
        #  - Bridges: water_level + clearance
        # DO NOT resample terrain or we'll create underwater bridge decks!
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


## Check if position is over water
func _is_over_water(x: float, z: float) -> bool:
    if ctx == null or ctx.terrain_generator == null:
        return false
    var h: float = ctx.terrain_generator.get_height_at(x, z)
    return h < float(Game.sea_level)


## Add bridge pillars if road crosses water
func _add_bridge_pillars_to_road(parent: Node3D, path: PackedVector3Array, width: float, material: Material, bridge_clearance: float = 15.0) -> void:
    if ctx == null or ctx.terrain_generator == null:
        return

    var pillar_spacing: float = 60.0  # Pillars every 60m
    var pillar_width: float = width * 0.15  # 15% of road width
    var pillar_depth: float = pillar_width * 0.8

    var dist_along: float = 0.0
    var last_pillar_dist: float = 0.0
    var in_water: bool = false

    for i in range(path.size() - 1):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]
        var segment_length: float = p0.distance_to(p1)

        # Check if this segment is over water
        var p0_water: bool = _is_over_water(p0.x, p0.z)
        var p1_water: bool = _is_over_water(p1.x, p1.z)

        if p0_water or p1_water:
            if not in_water:
                in_water = true
                last_pillar_dist = dist_along  # Reset pillar counter

            # Calculate proper deck height: water level + clearance for ships
            var water_level: float = float(Game.sea_level)
            var deck_height: float = water_level + bridge_clearance

            # Check if we need a pillar in this segment
            while (dist_along - last_pillar_dist) >= pillar_spacing:
                last_pillar_dist += pillar_spacing

                # Find position along segment for pillar
                var t: float = (last_pillar_dist - (dist_along - segment_length)) / segment_length
                t = clampf(t, 0.0, 1.0)
                var pillar_pos: Vector3 = p0.lerp(p1, t)

                # Get ground/water bottom height
                var ground_height: float = ctx.terrain_generator.get_height_at(pillar_pos.x, pillar_pos.z)
                var pillar_base: float = minf(ground_height, water_level - 1.0)  # Pillars to water bottom

                # Create pillar from bottom to deck (only if tall enough)
                if (deck_height - pillar_base) > 5.0:  # Minimum 5m pillar height
                    var pillar: MeshInstance3D = _create_bridge_pillar(
                        pillar_pos.x,
                        pillar_pos.z,
                        pillar_base,
                        deck_height - 0.3,  # Stop just below deck thickness
                        pillar_width,
                        pillar_depth,
                        material
                    )
                    if pillar != null:
                        parent.add_child(pillar)
        else:
            in_water = false

        dist_along += segment_length


## Create a single bridge support pillar
func _create_bridge_pillar(x: float, z: float, bottom_y: float, top_y: float, width: float, depth: float, material: Material) -> MeshInstance3D:
    var height: float = top_y - bottom_y
    if height <= 0.0:
        return null

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var hw: float = width * 0.5
    var hd: float = depth * 0.5

    # Base vertices (at ground/water bottom)
    var base_corners: Array[Vector3] = [
        Vector3(x - hw, bottom_y, z - hd),
        Vector3(x + hw, bottom_y, z - hd),
        Vector3(x + hw, bottom_y, z + hd),
        Vector3(x - hw, bottom_y, z + hd),
    ]

    # Top vertices (at deck level) - slightly tapered
    var taper: float = 0.9
    var top_corners: Array[Vector3] = [
        Vector3(x - hw * taper, top_y, z - hd * taper),
        Vector3(x + hw * taper, top_y, z - hd * taper),
        Vector3(x + hw * taper, top_y, z + hd * taper),
        Vector3(x - hw * taper, top_y, z + hd * taper),
    ]

    # Create 4 side faces
    var face_normals: Array[Vector3] = [
        Vector3(0, 0, -1), Vector3(1, 0, 0),
        Vector3(0, 0, 1), Vector3(-1, 0, 0),
    ]

    for side in range(4):
        var next_side: int = (side + 1) % 4
        var b0: Vector3 = base_corners[side]
        var b1: Vector3 = base_corners[next_side]
        var t0: Vector3 = top_corners[side]
        var t1: Vector3 = top_corners[next_side]
        var normal: Vector3 = face_normals[side]

        st.set_normal(normal); st.set_uv(Vector2(0, 1)); st.add_vertex(b0)
        st.set_normal(normal); st.set_uv(Vector2(1, 0)); st.add_vertex(t1)
        st.set_normal(normal); st.set_uv(Vector2(0, 0)); st.add_vertex(t0)

        st.set_normal(normal); st.set_uv(Vector2(0, 1)); st.add_vertex(b0)
        st.set_normal(normal); st.set_uv(Vector2(1, 1)); st.add_vertex(b1)
        st.set_normal(normal); st.set_uv(Vector2(1, 0)); st.add_vertex(t1)

    # Top cap
    st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 0)); st.add_vertex(top_corners[0])
    st.set_normal(Vector3.UP); st.set_uv(Vector2(1, 1)); st.add_vertex(top_corners[2])
    st.set_normal(Vector3.UP); st.set_uv(Vector2(1, 0)); st.add_vertex(top_corners[1])

    st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 0)); st.add_vertex(top_corners[0])
    st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 1)); st.add_vertex(top_corners[3])
    st.set_normal(Vector3.UP); st.set_uv(Vector2(1, 1)); st.add_vertex(top_corners[2])

    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    mi.material_override = material
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    return mi
