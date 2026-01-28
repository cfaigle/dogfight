class_name RoadMasterPlanner
extends RefCounted

## Centralized road network planner using build → test → refine strategy
## Replaces scattered road generation with unified planning system

# Road request structure:
# {
#   "id": String,
#   "type": String,  # "highway", "arterial", "lane", "city_grid", "town_spoke", etc
#   "from": Vector3,
#   "to": Vector3,
#   "width": float,
#   "priority": int,  # Higher = more important
#   "material": Material,
#   "allow_merge": bool
# }

var _road_requests: Array = []
var _water_crossings: Array = []  # Detected bridge zones
var _boat_spawn_zones: Array = []  # Areas where boats spawn (exclude bridges)
var _optimized_roads: Array = []  # Final road network after optimization
var _exclusion_zones: Dictionary = {}  # Spatial grid of no-build zones

var terrain_generator: RefCounted = null
var bridge_clearance: float = 15.0
var road_terrain_offset: float = 1.2
var merge_threshold: float = 50.0  # Roads within 50m get merged

# Economic routing parameters
var bridge_cost_multiplier: float = 5.0   # Bridges cost 5× more than land roads (reduced from 15x)
var min_population_for_bridge: int = 50   # Allow bridges to smaller settlements (reduced from 200)
var max_cost_per_capita: float = 100000.0  # More generous cost per person (increased from $50k)

# Spatial grid for fast lookups
var _grid_cell_size: float = 100.0


## ============================================================================
## PHASE 1: COLLECTION - Gather all road requests
## ============================================================================

func request_highway(from: Vector3, to: Vector3, width: float, mat: Material, priority: int = 10) -> String:
    var id: String = "highway_%d" % _road_requests.size()
    _road_requests.append({
        "id": id,
        "type": "highway",
        "from": from,
        "to": to,
        "width": width,
        "priority": priority,
        "material": mat,
        "allow_merge": true
    })
    return id


func request_arterial(from: Vector3, to: Vector3, width: float, mat: Material, priority: int = 8) -> String:
    var id: String = "arterial_%d" % _road_requests.size()
    _road_requests.append({
        "id": id,
        "type": "arterial",
        "from": from,
        "to": to,
        "width": width,
        "priority": priority,
        "material": mat,
        "allow_merge": true
    })
    return id


func request_lane(from: Vector3, to: Vector3, width: float, mat: Material, priority: int = 5) -> String:
    var id: String = "lane_%d" % _road_requests.size()
    _road_requests.append({
        "id": id,
        "type": "lane",
        "from": from,
        "to": to,
        "width": width,
        "priority": priority,
        "material": mat,
        "allow_merge": true
    })
    return id


func request_settlement_road(from: Vector3, to: Vector3, width: float, mat: Material, settlement_name: String, priority: int = 7) -> String:
    var id: String = "settlement_%s_%d" % [settlement_name, _road_requests.size()]
    _road_requests.append({
        "id": id,
        "type": "settlement",
        "from": from,
        "to": to,
        "width": width,
        "priority": priority,
        "material": mat,
        "allow_merge": false,  # Don't merge settlement roads with regional ones
        "settlement": settlement_name
    })
    return id


func mark_boat_spawn_zone(center: Vector3, radius: float) -> void:
    _boat_spawn_zones.append({
        "center": center,
        "radius": radius
    })


## ============================================================================
## PHASE 2: ANALYSIS - Detect conflicts and issues
## ============================================================================

func analyze_network() -> Dictionary:
    print("🔍 RoadMasterPlanner: Analyzing %d road requests..." % _road_requests.size())

    var analysis: Dictionary = {
        "total_requests": _road_requests.size(),
        "overlapping_roads": [],
        "bridge_conflicts": [],
        "boat_conflicts": [],
        "terrain_issues": []
    }

    # Detect overlapping roads
    analysis.overlapping_roads = _detect_overlapping_roads()
    print("   → Found %d overlapping road pairs" % analysis.overlapping_roads.size())

    # Detect bridge zones
    _detect_water_crossings()
    print("   → Detected %d water crossing zones" % _water_crossings.size())

    # Check for boat conflicts
    analysis.boat_conflicts = _detect_boat_conflicts()
    print("   → Found %d roads conflicting with boat spawns" % analysis.boat_conflicts.size())

    # Analyze terrain clipping potential
    analysis.terrain_issues = _analyze_terrain_issues()
    print("   → Found %d roads with potential terrain clipping" % analysis.terrain_issues.size())

    return analysis


func _detect_overlapping_roads() -> Array:
    var overlaps: Array = []

    for i in range(_road_requests.size()):
        var road_a: Dictionary = _road_requests[i]
        if not road_a.get("allow_merge", true):
            continue

        for j in range(i + 1, _road_requests.size()):
            var road_b: Dictionary = _road_requests[j]
            if not road_b.get("allow_merge", true):
                continue

            # Check if roads are parallel and close
            var dist: float = _min_distance_between_segments(
                road_a.from, road_a.to,
                road_b.from, road_b.to
            )

            if dist < merge_threshold:
                overlaps.append({
                    "road_a": road_a.id,
                    "road_b": road_b.id,
                    "distance": dist
                })

    return overlaps


func _detect_water_crossings() -> void:
    _water_crossings.clear()

    if terrain_generator == null:
        return

    # Sample each road to find water crossings
    for request in _road_requests:
        var from: Vector3 = request.from
        var to: Vector3 = request.to
        var samples: int = maxi(10, int(from.distance_to(to) / 50.0))

        var in_water: bool = false
        var crossing_start: Vector3 = Vector3.ZERO

        for i in range(samples + 1):
            var t: float = float(i) / float(samples)
            var p: Vector3 = from.lerp(to, t)
            var h: float = terrain_generator.get_height_at(p.x, p.z)
            var is_water: bool = h < float(Game.sea_level)

            if is_water and not in_water:
                # Start of crossing
                crossing_start = p
                in_water = true
            elif not is_water and in_water:
                # End of crossing
                var crossing_center: Vector3 = (crossing_start + p) * 0.5
                var crossing_width: float = crossing_start.distance_to(p)

                # Check if we already have a nearby crossing
                var found_existing: bool = false
                for existing in _water_crossings:
                    if existing.center.distance_to(crossing_center) < 100.0:
                        found_existing = true
                        break

                if not found_existing:
                    _water_crossings.append({
                        "center": crossing_center,
                        "width": crossing_width,
                        "roads": [request.id]
                    })

                in_water = false


func _detect_boat_conflicts() -> Array:
    var conflicts: Array = []

    for crossing in _water_crossings:
        for boat_zone in _boat_spawn_zones:
            var dist: float = crossing.center.distance_to(boat_zone.center)
            if dist < (boat_zone.radius + crossing.width * 0.5):
                conflicts.append({
                    "crossing": crossing,
                    "boat_zone": boat_zone
                })

    return conflicts


func _analyze_terrain_issues() -> Array:
    var issues: Array = []

    if terrain_generator == null:
        return issues

    for request in _road_requests:
        var from: Vector3 = request.from
        var to: Vector3 = request.to
        var samples: int = 20

        var max_slope: float = 0.0
        var min_clearance: float = INF

        for i in range(samples + 1):
            var t: float = float(i) / float(samples)
            var p: Vector3 = from.lerp(to, t)
            var slope: float = terrain_generator.get_slope_at(p.x, p.z)
            var h: float = terrain_generator.get_height_at(p.x, p.z)
            var clearance: float = abs(p.y - h)

            max_slope = maxf(max_slope, slope)
            min_clearance = minf(min_clearance, clearance)

        if max_slope > 20.0 or min_clearance < 0.5:
            issues.append({
                "road": request.id,
                "max_slope": max_slope,
                "min_clearance": min_clearance
            })

    return issues


## ============================================================================
## PHASE 3: OPTIMIZATION - Merge, consolidate, adjust
## ============================================================================

func optimize_network() -> void:
    print("🔧 RoadMasterPlanner: Optimizing network...")

    # Sort by priority (higher first)
    _road_requests.sort_custom(func(a, b): return a.priority > b.priority)

    # Merge overlapping roads
    _merge_overlapping_roads()

    # Consolidate bridges at water crossings
    _consolidate_bridges()

    # Adjust road heights for terrain
    _adjust_road_heights()

    # Mark boat exclusion zones at bridges
    _mark_bridge_exclusion_zones()

    print("   → Optimized to %d final roads" % _optimized_roads.size())


func _merge_overlapping_roads() -> void:
    var merged_ids: Dictionary = {}

    for i in range(_road_requests.size()):
        if merged_ids.has(_road_requests[i].id):
            continue

        var road_a: Dictionary = _road_requests[i]
        if not road_a.get("allow_merge", true):
            _optimized_roads.append(road_a)
            continue

        var merged: bool = false

        for j in range(i + 1, _road_requests.size()):
            if merged_ids.has(_road_requests[j].id):
                continue

            var road_b: Dictionary = _road_requests[j]
            if not road_b.get("allow_merge", true):
                continue

            var dist: float = _min_distance_between_segments(
                road_a.from, road_a.to,
                road_b.from, road_b.to
            )

            if dist < merge_threshold:
                # Merge into higher priority road
                merged_ids[road_b.id] = true
                merged = true
                # Use wider width
                road_a.width = maxf(road_a.width, road_b.width)

        _optimized_roads.append(road_a)


func _consolidate_bridges() -> void:
    # Group roads by water crossing
    for crossing in _water_crossings:
        var roads_at_crossing: Array = []

        for road in _optimized_roads:
            var midpoint: Vector3 = (road.from + road.to) * 0.5
            if midpoint.distance_to(crossing.center) < crossing.width * 0.5 + 50.0:
                roads_at_crossing.append(road)

        if roads_at_crossing.size() > 1:
            # Multiple roads cross here - they'll share the same bridge deck height
            var max_width: float = 0.0
            for r in roads_at_crossing:
                max_width = maxf(max_width, r.width)

            crossing["consolidated_width"] = max_width


func _adjust_road_heights() -> void:
    # Ensure all roads have proper heights calculated
    for road in _optimized_roads:
        # Heights will be calculated during path generation
        pass


func _mark_bridge_exclusion_zones() -> void:
    for crossing in _water_crossings:
        _exclusion_zones[crossing.center] = {
            "type": "bridge",
            "radius": crossing.width * 0.5 + 20.0,
            "center": crossing.center
        }


## ============================================================================
## PHASE 4: BUILDING - Generate final road network
## ============================================================================

func build_network(parent: Node3D) -> Dictionary:
    print("🏗️ RoadMasterPlanner: Building optimized road network...")

    var built_roads: Array = []
    var bridge_pillars: Array = []

    for road in _optimized_roads:
        var path: PackedVector3Array = _create_road_path(
            road.from,
            road.to,
            road.width
        )

        if path.size() < 2:
            continue

        # Create road mesh
        var mesh_inst: MeshInstance3D = _create_road_mesh(path, road.width, road.material)
        if mesh_inst != null:
            mesh_inst.name = road.id
            parent.add_child(mesh_inst)

            # Add bridge pillars if needed
            var pillars: Array = _add_bridge_pillars(parent, path, road.width, road.material)
            bridge_pillars.append_array(pillars)

            built_roads.append({
                "path": path,
                "width": road.width,
                "type": road.type,
                "from": road.from,
                "to": road.to
            })

    print("   → Built %d roads with %d bridge pillars" % [built_roads.size(), bridge_pillars.size()])

    return {
        "roads": built_roads,
        "bridge_pillars": bridge_pillars,
        "exclusion_zones": _exclusion_zones,
        "water_crossings": _water_crossings
    }


func _create_road_path(start: Vector3, end: Vector3, width: float) -> PackedVector3Array:
    var path := PackedVector3Array()
    var dist: float = start.distance_to(end)
    var segments: int = maxi(20, int(dist / 20.0))

    for i in range(segments + 1):
        var t: float = float(i) / float(segments)
        var p: Vector3 = start.lerp(end, t)

        # Add slight curve for organic feel
        var curve_amount: float = 20.0 / (width / 10.0)
        var curve_offset: float = sin(t * PI) * curve_amount
        var perp: Vector3 = Vector3(-(end.z - start.z), 0, end.x - start.x).normalized()
        p += perp * curve_offset

        # Calculate proper height (terrain OR bridge)
        if terrain_generator != null:
            var terrain_height: float = terrain_generator.get_height_at(p.x, p.z)
            var water_level: float = float(Game.sea_level)

            if terrain_height < water_level:
                # BRIDGE: Use deck height
                p.y = water_level + bridge_clearance
            else:
                # LAND: Use terrain + adaptive offset
                var slope: float = terrain_generator.get_slope_at(p.x, p.z)
                var adaptive_offset: float = road_terrain_offset + (slope * 0.1)
                p.y = terrain_height + adaptive_offset

        path.append(p)

    return path


func _create_road_mesh(path: PackedVector3Array, width: float, material: Material) -> MeshInstance3D:
    if path.size() < 2:
        return null

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var thickness: float = 0.3
    var dist_along: float = 0.0

    for i in range(path.size() - 1):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]

        var dir_xz: Vector3 = Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
        var right: Vector3 = dir_xz.cross(Vector3.UP).normalized() * width * 0.5

        # Use path Y values directly (already correct)
        var v0_top := Vector3(p0.x - right.x, p0.y, p0.z - right.z)
        var v1_top := Vector3(p0.x + right.x, p0.y, p0.z + right.z)
        var v2_top := Vector3(p1.x + right.x, p1.y, p1.z + right.z)
        var v3_top := Vector3(p1.x - right.x, p1.y, p1.z - right.z)

        var v0_bot := v0_top - Vector3.UP * thickness
        var v1_bot := v1_top - Vector3.UP * thickness
        var v2_bot := v2_top - Vector3.UP * thickness
        var v3_bot := v3_top - Vector3.UP * thickness

        var segment_length: float = p0.distance_to(p1)
        var u_scale: float = 0.05
        var uv_start: float = dist_along * u_scale
        var uv_end: float = (dist_along + segment_length) * u_scale

        # Top surface
        st.set_normal(Vector3.UP); st.set_uv(Vector2(0, uv_start)); st.add_vertex(v0_top)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(1, uv_end)); st.add_vertex(v2_top)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(1, uv_start)); st.add_vertex(v1_top)

        st.set_normal(Vector3.UP); st.set_uv(Vector2(0, uv_start)); st.add_vertex(v0_top)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(0, uv_end)); st.add_vertex(v3_top)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(1, uv_end)); st.add_vertex(v2_top)

        # Side walls
        var left_normal := -right.normalized()
        st.set_normal(left_normal); st.set_uv(Vector2(0, uv_start)); st.add_vertex(v0_top)
        st.set_normal(left_normal); st.set_uv(Vector2(0, uv_end)); st.add_vertex(v3_top)
        st.set_normal(left_normal); st.set_uv(Vector2(0.1, uv_start)); st.add_vertex(v0_bot)

        st.set_normal(left_normal); st.set_uv(Vector2(0.1, uv_start)); st.add_vertex(v0_bot)
        st.set_normal(left_normal); st.set_uv(Vector2(0, uv_end)); st.add_vertex(v3_top)
        st.set_normal(left_normal); st.set_uv(Vector2(0.1, uv_end)); st.add_vertex(v3_bot)

        var right_normal := right.normalized()
        st.set_normal(right_normal); st.set_uv(Vector2(0, uv_start)); st.add_vertex(v1_top)
        st.set_normal(right_normal); st.set_uv(Vector2(0.1, uv_start)); st.add_vertex(v1_bot)
        st.set_normal(right_normal); st.set_uv(Vector2(0, uv_end)); st.add_vertex(v2_top)

        st.set_normal(right_normal); st.set_uv(Vector2(0.1, uv_start)); st.add_vertex(v1_bot)
        st.set_normal(right_normal); st.set_uv(Vector2(0.1, uv_end)); st.add_vertex(v2_bot)
        st.set_normal(right_normal); st.set_uv(Vector2(0, uv_end)); st.add_vertex(v2_top)

        dist_along += segment_length

    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    if material != null:
        mi.material_override = material
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mi


func _add_bridge_pillars(parent: Node3D, path: PackedVector3Array, width: float, material: Material) -> Array:
    var pillars: Array = []

    if terrain_generator == null:
        return pillars

    var pillar_spacing: float = 60.0
    var pillar_width: float = width * 0.15
    var pillar_depth: float = pillar_width * 0.8

    var dist_along: float = 0.0
    var last_pillar_dist: float = 0.0

    for i in range(path.size() - 1):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]
        var segment_length: float = p0.distance_to(p1)

        # Check if over water
        var h0: float = terrain_generator.get_height_at(p0.x, p0.z)
        var h1: float = terrain_generator.get_height_at(p1.x, p1.z)
        var water_level: float = float(Game.sea_level)

        if h0 < water_level or h1 < water_level:
            var deck_height: float = water_level + bridge_clearance

            while (dist_along - last_pillar_dist) >= pillar_spacing:
                last_pillar_dist += pillar_spacing

                var t: float = (last_pillar_dist - (dist_along - segment_length)) / segment_length
                t = clampf(t, 0.0, 1.0)
                var pillar_pos: Vector3 = p0.lerp(p1, t)

                var ground_height: float = terrain_generator.get_height_at(pillar_pos.x, pillar_pos.z)
                var pillar_base: float = minf(ground_height, water_level - 1.0)

                if (deck_height - pillar_base) > 5.0:
                    var pillar: MeshInstance3D = _create_pillar(
                        pillar_pos.x, pillar_pos.z,
                        pillar_base, deck_height - 0.3,
                        pillar_width, pillar_depth, material
                    )
                    if pillar != null:
                        parent.add_child(pillar)
                        pillars.append(pillar)

        dist_along += segment_length

    return pillars


func _create_pillar(x: float, z: float, bottom_y: float, top_y: float, width: float, depth: float, material: Material) -> MeshInstance3D:
    var height: float = top_y - bottom_y
    if height <= 0.0:
        return null

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var taper: float = 0.9

    var base_corners: Array[Vector3] = [
        Vector3(x - hw, bottom_y, z - hd),
        Vector3(x + hw, bottom_y, z - hd),
        Vector3(x + hw, bottom_y, z + hd),
        Vector3(x - hw, bottom_y, z + hd),
    ]

    var top_corners: Array[Vector3] = [
        Vector3(x - hw * taper, top_y, z - hd * taper),
        Vector3(x + hw * taper, top_y, z - hd * taper),
        Vector3(x + hw * taper, top_y, z + hd * taper),
        Vector3(x - hw * taper, top_y, z + hd * taper),
    ]

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


## ============================================================================
## UTILITY FUNCTIONS
## ============================================================================

## Classify settlements by importance/population for road hierarchy
func classify_settlement(settlement: Dictionary) -> String:
    var population: int = settlement.get("population", 100)

    # Major hub: worthy of expensive infrastructure
    if population >= 500:
        return "major_hub"
    # Medium town: can justify moderate costs
    elif population >= 200:
        return "medium_town"
    # Minor hamlet: cheap roads only
    else:
        return "minor_hamlet"


## Check if a road connection is economically viable
func is_economically_viable(cost_info: Dictionary, population_served: int) -> bool:
    # Always allow land-only roads
    if cost_info.water_distance < 10.0:
        return true

    # Require minimum population for bridge construction
    if population_served < min_population_for_bridge:
        return false

    # Check cost per capita (simplified: assume distance ≈ cost in arbitrary units)
    var cost_per_person: float = cost_info.economic_cost / float(maxi(1, population_served))

    if cost_per_person > max_cost_per_capita:
        return false

    return true


## Calculate economic cost of building a road (land vs bridge distance)
func calculate_edge_cost(from: Vector3, to: Vector3) -> Dictionary:
    var total_distance: float = from.distance_to(to)
    var land_distance: float = 0.0
    var water_distance: float = 0.0

    if terrain_generator == null:
        return {
            "total_distance": total_distance,
            "land_distance": total_distance,
            "water_distance": 0.0,
            "economic_cost": total_distance
        }

    # Ray-march along path to measure land vs water segments
    var samples: int = maxi(20, int(total_distance / 50.0))
    var water_level: float = float(Game.sea_level)

    for i in range(samples):
        var t0: float = float(i) / float(samples)
        var t1: float = float(i + 1) / float(samples)
        var p0: Vector3 = from.lerp(to, t0)
        var p1: Vector3 = from.lerp(to, t1)

        var h0: float = terrain_generator.get_height_at(p0.x, p0.z)
        var h1: float = terrain_generator.get_height_at(p1.x, p1.z)
        var segment_length: float = p0.distance_to(p1)

        # Average height of segment
        var avg_height: float = (h0 + h1) * 0.5

        if avg_height < water_level:
            water_distance += segment_length
        else:
            land_distance += segment_length

    # Economic cost = land_km * $1M/km + water_km * $15M/km (simplified)
    var economic_cost: float = (land_distance * 1.0) + (water_distance * bridge_cost_multiplier)

    return {
        "total_distance": total_distance,
        "land_distance": land_distance,
        "water_distance": water_distance,
        "economic_cost": economic_cost,
        "is_expensive": water_distance > (total_distance * 0.3)  # >30% over water
    }


func _min_distance_between_segments(a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3) -> float:
    # Simplified: Check endpoints and midpoints
    var a_mid := (a1 + a2) * 0.5
    var b_mid := (b1 + b2) * 0.5

    var dists: Array[float] = [
        a1.distance_to(b1),
        a1.distance_to(b2),
        a2.distance_to(b1),
        a2.distance_to(b2),
        a_mid.distance_to(b_mid),
    ]

    var min_dist: float = INF
    for d in dists:
        min_dist = minf(min_dist, d)

    return min_dist


func clear() -> void:
    _road_requests.clear()
    _water_crossings.clear()
    _boat_spawn_zones.clear()
    _optimized_roads.clear()
    _exclusion_zones.clear()


func get_exclusion_zones() -> Dictionary:
    return _exclusion_zones
