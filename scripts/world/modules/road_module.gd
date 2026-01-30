class_name RoadModule
extends RefCounted

## Road generation module with basic A* pathfinding.
##
## API:
## - generate_road(start, end, params) -> PackedVector3Array
## - create_road_mesh(path, width, material) -> MeshInstance3D
##
## Notes:
## - Uses a 2D grid (Vector2i keys) for speed
## - Adds cost for water and steep slopes
## - Path smoothing is a simple averaging pass (fast + stable)

# Grid / costs
var _grid_resolution: float = 12.0 # meters per cell
var _water_cost: float = 500.0  # High cost to avoid water without bridges
var _steep_cost: float = 70.0
var _bridge_cost: float = 15.0  # Low cost - bridges are cheap to build

# Terrain query interface
var _terrain_generator: TerrainGenerator = null
var _world_ctx: WorldContext = null

# Terrain query cache for performance
var _height_cache: Dictionary = {}  # Vector2i -> float
var _slope_cache: Dictionary = {}   # Vector2i -> float

# Convenience properties (callers can set fields directly).
var terrain_generator: TerrainGenerator:
    set(value):
        _terrain_generator = value
    get:
        return _terrain_generator

var world_ctx: WorldContext:
    set(value):
        _world_ctx = value
    get:
        return _world_ctx

var road_width: float = 18.0
var road_smooth: bool = true
var allow_bridges: bool = true

func set_terrain_generator(gen: TerrainGenerator) -> void:
    _terrain_generator = gen

func set_grid_resolution(meters: float) -> void:
    _grid_resolution = maxf(2.0, meters)

## Generate road between two points.
func generate_road(start: Vector3, end: Vector3, params: Dictionary = {}) -> PackedVector3Array:
    if _terrain_generator == null:
        push_error("RoadModule: terrain_generator not set")
        return PackedVector3Array()

    # Merge caller params with instance defaults.
    var p_allow_bridges: bool = bool(params.get("allow_bridges", allow_bridges))
    var p_smooth: bool = bool(params.get("smooth", road_smooth))
    var p_grid: float = float(params.get("grid_resolution", _grid_resolution))
    set_grid_resolution(p_grid)

    var path: Array[Vector3] = _find_path(start, end, p_allow_bridges)

    if p_smooth:
        path = _smooth_path(path)

    # Densify path for better terrain following and smoother connections
    path = _densify_path(path, 15.0)  # Add points every 15m

    # Convert to packed array.
    var out := PackedVector3Array()
    out.resize(path.size())
    for i in range(path.size()):
        out[i] = path[i]
    return out

## A* on a 2D grid with binary heap and spatial culling. Returns Array[Vector3] world points.
func _find_path(start: Vector3, end: Vector3, p_allow_bridges: bool) -> Array[Vector3]:
    # Clear terrain cache for new pathfinding request
    _height_cache.clear()
    _slope_cache.clear()

    var open_heap: Array = []  # Binary min-heap: [f_score, Vector2i]
    var open_lookup: Dictionary = {}  # Vector2i -> heap index
    var closed: Dictionary = {}
    var came_from: Dictionary = {}
    var g_score: Dictionary = {}
    var f_score: Dictionary = {}

    var start_key: Vector2i = _vec_to_grid(start)
    var end_key: Vector2i = _vec_to_grid(end)

    # Adaptive spatial culling: corridor width scales with distance
    var straight_dist: float = start.distance_to(end)
    var corridor_width: float = maxf(straight_dist * 1.2, 8000.0)  # 120% of distance or 8km minimum (wider for complex terrain)
    var corridor_cells: int = int(corridor_width / _grid_resolution)

    var min_x: int = mini(start_key.x, end_key.x) - corridor_cells
    var max_x: int = maxi(start_key.x, end_key.x) + corridor_cells
    var min_y: int = mini(start_key.y, end_key.y) - corridor_cells
    var max_y: int = maxi(start_key.y, end_key.y) + corridor_cells

    _heap_insert(open_heap, open_lookup, f_score, start_key, _heuristic(start, end))
    g_score[start_key] = 0.0
    f_score[start_key] = _heuristic(start, end)

    var iterations: int = 0
    var max_iterations: int = 50000  # Doubled for complex terrain and long roads

    while not open_heap.is_empty() and iterations < max_iterations:
        iterations += 1

        # Extract node with smallest f (O(log n) instead of O(n))
        var current_key: Vector2i = _heap_extract_min(open_heap, open_lookup, f_score)

        if current_key == end_key:
            return _reconstruct_path(came_from, current_key, start_key, start, end)

        closed[current_key] = true

        for n in _get_neighbors(current_key):
            # Spatial culling: skip nodes outside corridor
            if n.x < min_x or n.x > max_x or n.y < min_y or n.y > max_y:
                continue

            if closed.has(n):
                continue

            var a_pos: Vector3 = _grid_to_vec(current_key)
            var b_pos: Vector3 = _grid_to_vec(n)
            var tentative_g: float = float(g_score.get(current_key, INF)) + _movement_cost(a_pos, b_pos, p_allow_bridges)

            var old_g: float = float(g_score.get(n, INF))
            if tentative_g >= old_g:
                continue

            came_from[n] = current_key
            g_score[n] = tentative_g
            var new_f: float = tentative_g + _heuristic(b_pos, end)

            if open_lookup.has(n):
                # Update existing node in heap
                _heap_update(open_heap, open_lookup, f_score, n, new_f)
            else:
                # Insert new node into heap
                _heap_insert(open_heap, open_lookup, f_score, n, new_f)

            f_score[n] = new_f

    # Fallback: straight line.
    var dist: float = start.distance_to(end)
    push_warning("RoadModule: No path found after %d iterations (distance: %.0fm, corridor: %.0fm) - using straight line" % [
        iterations, dist, corridor_width
    ])
    return [start, end]


## Binary min-heap operations for fast priority queue (O(log n) instead of O(n))

func _heap_insert(heap: Array, lookup: Dictionary, f_score: Dictionary, key: Vector2i, f: float) -> void:
    heap.append(key)
    var idx: int = heap.size() - 1
    lookup[key] = idx
    _heap_bubble_up(heap, lookup, f_score, idx)


func _heap_extract_min(heap: Array, lookup: Dictionary, f_score: Dictionary) -> Vector2i:
    if heap.is_empty():
        return Vector2i.ZERO

    var min_key: Vector2i = heap[0]
    lookup.erase(min_key)

    if heap.size() == 1:
        heap.pop_back()
        return min_key

    # Move last element to root and bubble down
    heap[0] = heap[heap.size() - 1]
    heap.pop_back()
    if not heap.is_empty():
        lookup[heap[0]] = 0
        _heap_bubble_down(heap, lookup, f_score, 0)

    return min_key


func _heap_update(heap: Array, lookup: Dictionary, f_score: Dictionary, key: Vector2i, new_f: float) -> void:
    if not lookup.has(key):
        return

    var idx: int = lookup[key]
    var old_f: float = float(f_score.get(key, INF))

    if new_f < old_f:
        _heap_bubble_up(heap, lookup, f_score, idx)
    else:
        _heap_bubble_down(heap, lookup, f_score, idx)


func _heap_bubble_up(heap: Array, lookup: Dictionary, f_score: Dictionary, idx: int) -> void:
    while idx > 0:
        var parent_idx: int = (idx - 1) / 2
        var child_f: float = float(f_score.get(heap[idx], INF))
        var parent_f: float = float(f_score.get(heap[parent_idx], INF))

        if child_f >= parent_f:
            break

        # Swap
        var temp: Vector2i = heap[idx]
        heap[idx] = heap[parent_idx]
        heap[parent_idx] = temp
        lookup[heap[idx]] = idx
        lookup[heap[parent_idx]] = parent_idx

        idx = parent_idx


func _heap_bubble_down(heap: Array, lookup: Dictionary, f_score: Dictionary, idx: int) -> void:
    var size: int = heap.size()

    while true:
        var left_idx: int = 2 * idx + 1
        var right_idx: int = 2 * idx + 2
        var smallest_idx: int = idx

        if left_idx < size:
            var smallest_f: float = float(f_score.get(heap[smallest_idx], INF))
            var left_f: float = float(f_score.get(heap[left_idx], INF))
            if left_f < smallest_f:
                smallest_idx = left_idx

        if right_idx < size:
            var smallest_f: float = float(f_score.get(heap[smallest_idx], INF))
            var right_f: float = float(f_score.get(heap[right_idx], INF))
            if right_f < smallest_f:
                smallest_idx = right_idx

        if smallest_idx == idx:
            break

        # Swap
        var temp: Vector2i = heap[idx]
        heap[idx] = heap[smallest_idx]
        heap[smallest_idx] = temp
        lookup[heap[idx]] = idx
        lookup[heap[smallest_idx]] = smallest_idx

        idx = smallest_idx


func _movement_cost(from: Vector3, to: Vector3, p_allow_bridges: bool) -> float:
    var base_cost: float = from.distance_to(to)

    # Use cached terrain queries
    var grid_key: Vector2i = _vec_to_grid(to)

    var h: float
    if _height_cache.has(grid_key):
        h = _height_cache[grid_key]
    else:
        h = _terrain_generator.get_height_at(to.x, to.z)
        _height_cache[grid_key] = h

    if h < float(Game.sea_level):
        return base_cost + (_bridge_cost if p_allow_bridges else _water_cost)

    # Check if in lake (lakes are above sea level, so need separate check)
    if _world_ctx != null and _world_ctx.has_method("is_in_lake"):
        if _world_ctx.is_in_lake(to.x, to.z):
            return base_cost + (_bridge_cost if p_allow_bridges else _water_cost)

    var slope: float
    if _slope_cache.has(grid_key):
        slope = _slope_cache[grid_key]
    else:
        slope = _terrain_generator.get_slope_at(to.x, to.z)
        _slope_cache[grid_key] = slope

    if slope > 14.0:
        return base_cost + _steep_cost * (slope / 45.0)

    return base_cost

func _heuristic(a: Vector3, b: Vector3) -> float:
    return a.distance_to(b)

func _get_neighbors(key: Vector2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for dy in [-1, 0, 1]:
        for dx in [-1, 0, 1]:
            if dx == 0 and dy == 0:
                continue
            out.append(Vector2i(key.x + dx, key.y + dy))
    return out

func _vec_to_grid(pos: Vector3) -> Vector2i:
    return Vector2i(int(floor(pos.x / _grid_resolution)), int(floor(pos.z / _grid_resolution)))

func _grid_to_vec(key: Vector2i) -> Vector3:
    # Center of the cell, with Y from terrain (cached).
    var x: float = (float(key.x) + 0.5) * _grid_resolution
    var z: float = (float(key.y) + 0.5) * _grid_resolution

    var y: float
    if _height_cache.has(key):
        y = _height_cache[key]
    else:
        y = _terrain_generator.get_height_at(x, z)
        _height_cache[key] = y

    return Vector3(x, y + 0.08, z)

func _reconstruct_path(came_from: Dictionary, current: Vector2i, start_key: Vector2i, start_pos: Vector3, end_pos: Vector3) -> Array[Vector3]:
    var keys: Array[Vector2i] = [current]
    var cur: Vector2i = current
    var guard: int = 0
    while cur != start_key and came_from.has(cur) and guard < 20000:
        guard += 1
        cur = came_from[cur] as Vector2i
        keys.append(cur)

    keys.reverse()

    var pts: Array[Vector3] = []
    pts.resize(keys.size())
    for i in range(keys.size()):
        pts[i] = _grid_to_vec(keys[i])

    # Snap endpoints to the requested points (avoid noticeable "grid snapping" at ends).
    if pts.size() >= 1:
        pts[0] = start_pos
    if pts.size() >= 2:
        pts[pts.size() - 1] = end_pos
    return pts

func _smooth_path(path: Array[Vector3]) -> Array[Vector3]:
    if path.size() < 3:
        return path

    var out: Array[Vector3] = []
    out.append(path[0])

    for i in range(1, path.size() - 1):
        var p0: Vector3 = path[i - 1]
        var p1: Vector3 = path[i]
        var p2: Vector3 = path[i + 1]
        var s: Vector3 = (p0 + p1 + p2) / 3.0
        s.y = _terrain_generator.get_height_at(s.x, s.z) + 0.5  # Higher offset
        out.append(s)

    out.append(path[path.size() - 1])
    return out

## Densify path by adding intermediate points for better terrain following
func _densify_path(path: Array[Vector3], max_segment_length: float) -> Array[Vector3]:
    if path.size() < 2:
        return path

    var out: Array[Vector3] = []

    for i in range(path.size() - 1):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]
        out.append(p0)

        var dist: float = p0.distance_to(p1)
        var segments: int = int(ceil(dist / max_segment_length))

        # Add intermediate points
        for j in range(1, segments):
            var t: float = float(j) / float(segments)
            var p: Vector3 = p0.lerp(p1, t)
            p.y = _terrain_generator.get_height_at(p.x, p.z) + 0.5  # Sample terrain height
            out.append(p)

    out.append(path[path.size() - 1])
    return out

## Create a road strip mesh that conforms to terrain and return a MeshInstance3D (or Node3D with bridges).
func create_road_mesh(path: PackedVector3Array, width: float = 18.0, material: Material = null) -> MeshInstance3D:
    if path.size() < 2:
        return null

    # Detect bridge spans
    var bridge_spans: Array = _detect_bridge_spans(path)
    var has_bridges: bool = bridge_spans.size() > 0

    # Build set of bridge segment indices for fast lookup
    var bridge_segments: Dictionary = {}
    for span in bridge_spans:
        for i in range(span.start, span.end):
            bridge_segments[i] = true

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var road_offset: float = 0.5  # Offset above terrain (must be visible after terrain carving)
    var dist_along: float = 0.0  # For distance-based UVs

    for i in range(path.size() - 1):
        # Skip road mesh in bridge areas (bridge will be created separately)
        if bridge_segments.has(i):
            continue

        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]

        # Use flattened XZ direction to avoid vertical twist
        var dir_xz: Vector3 = Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
        var right: Vector3 = dir_xz.cross(Vector3.UP).normalized() * width * 0.5

        # Calculate edge vertex positions
        var v0_base: Vector3 = p0 - right
        var v1_base: Vector3 = p0 + right
        var v2_base: Vector3 = p1 + right
        var v3_base: Vector3 = p1 - right

        # Sample terrain height for EACH edge vertex
        var v0: Vector3 = v0_base
        var v1: Vector3 = v1_base
        var v2: Vector3 = v2_base
        var v3: Vector3 = v3_base

        if _terrain_generator != null:
            # Use a smaller offset to account for subsequent terrain carving
            var adjusted_offset: float = max(0.1, road_offset - 0.2)  # Reduce offset to account for carving
            v0.y = _terrain_generator.get_height_at(v0.x, v0.z) + adjusted_offset
            v1.y = _terrain_generator.get_height_at(v1.x, v1.z) + adjusted_offset
            v2.y = _terrain_generator.get_height_at(v2.x, v2.z) + adjusted_offset
            v3.y = _terrain_generator.get_height_at(v3.x, v3.z) + adjusted_offset

        # Calculate normals from terrain slope (better lighting)
        var n0: Vector3 = _get_terrain_normal(v0.x, v0.z)
        var n1: Vector3 = _get_terrain_normal(v1.x, v1.z)
        var n2: Vector3 = _get_terrain_normal(v2.x, v2.z)
        var n3: Vector3 = _get_terrain_normal(v3.x, v3.z)

        # Distance-based UVs for consistent texture tiling
        var segment_length: float = p0.distance_to(p1)
        var u_scale: float = 0.05  # Texture repeat frequency (lower = more repetition)
        var uv_start: float = dist_along * u_scale
        var uv_end: float = (dist_along + segment_length) * u_scale

        # Fixed winding order: counter-clockwise when viewed from above
        st.set_normal(n0); st.set_uv(Vector2(0.0, uv_start)); st.add_vertex(v0)
        st.set_normal(n2); st.set_uv(Vector2(1.0, uv_end)); st.add_vertex(v2)
        st.set_normal(n1); st.set_uv(Vector2(1.0, uv_start)); st.add_vertex(v1)

        st.set_normal(n0); st.set_uv(Vector2(0.0, uv_start)); st.add_vertex(v0)
        st.set_normal(n3); st.set_uv(Vector2(0.0, uv_end)); st.add_vertex(v3)
        st.set_normal(n2); st.set_uv(Vector2(1.0, uv_end)); st.add_vertex(v2)

        dist_along += segment_length

    # Create road mesh
    var road_mi := MeshInstance3D.new()
    road_mi.mesh = st.commit()
    road_mi.position = Vector3.ZERO  # Vertices in world coords
    if material != null:
        road_mi.material_override = material
    road_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    # If no bridges, return just the road mesh
    if not has_bridges:
        return road_mi

# Create parent node to hold road + bridges
    # NOTE: We're changing to return Node3D when bridges exist
    # The parent class Node3D is compatible with caller expectations
    var parent := MeshInstance3D.new()  # Use MeshInstance3D as parent to maintain type compatibility
    parent.name = "RoadWithBridges"
    parent.mesh = road_mi.mesh  # Give parent the road mesh
    if material != null:
        parent.material_override = material
    parent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    # Vertices are already in world coordinates, don't offset parent position

    # Create bridge deck meshes as children
    for span in bridge_spans:
        var bridge_mi: MeshInstance3D = _create_bridge_deck(path, span, width, material)
        if bridge_mi != null:
            bridge_mi.name = "Bridge_%d" % span.start
            parent.add_child(bridge_mi)

    return parent


## Get terrain normal at a given position for better road lighting
func _get_terrain_normal(x: float, z: float) -> Vector3:
    if _terrain_generator == null:
        return Vector3.UP

    # Sample heights around the point to estimate normal
    var sample_dist: float = 2.0
    var h_center: float = _terrain_generator.get_height_at(x, z)
    var h_right: float = _terrain_generator.get_height_at(x + sample_dist, z)
    var h_forward: float = _terrain_generator.get_height_at(x, z + sample_dist)

    # Calculate tangent vectors
    var right_vec: Vector3 = Vector3(sample_dist, h_right - h_center, 0.0)
    var forward_vec: Vector3 = Vector3(0.0, h_forward - h_center, sample_dist)

    # Cross product gives normal
    var normal: Vector3 = forward_vec.cross(right_vec).normalized()

    # Ensure normal points upward
    if normal.y < 0.0:
        normal = -normal

    return normal


## Detect bridge spans in a road path (consecutive segments over water)
func _detect_bridge_spans(path: PackedVector3Array) -> Array:
    var spans: Array = []
    if _terrain_generator == null:
        return spans

    var in_span: bool = false
    var span_start: int = -1

    for i in range(path.size()):
        var p: Vector3 = path[i]
        var is_over_water: bool = _is_over_water(p.x, p.z)

        if is_over_water and not in_span:
            # Start new span
            span_start = i
            in_span = true
        elif not is_over_water and in_span:
            # End current span
            if span_start >= 0 and (i - span_start) >= 2:  # At least 2 points
                spans.append({"start": span_start, "end": i - 1})
            in_span = false
            span_start = -1

    # Handle span that extends to end of path
    if in_span and span_start >= 0:
        spans.append({"start": span_start, "end": path.size() - 1})

    return spans


## Check if a position is over water (sea or lake)
func _is_over_water(x: float, z: float) -> bool:
    if _terrain_generator == null:
        return false

    var h: float = _terrain_generator.get_height_at(x, z)

    # Check sea level
    if h < float(Game.sea_level):
        return true

    # Check lakes if world context available
    if _world_ctx != null and _world_ctx.has_method("is_in_lake"):
        if _world_ctx.is_in_lake(x, z, 0.0):
            return true

    return false


## Create bridge deck mesh for a span
func _create_bridge_deck(path: PackedVector3Array, span: Dictionary, width: float, material: Material) -> MeshInstance3D:
    var start_idx: int = span.start
    var end_idx: int = span.end

    if start_idx >= end_idx or start_idx < 0 or end_idx >= path.size():
        return null

    # Calculate deck height (water surface + clearance, with ramps)
    var clearance: float = 8.0  # Height above water
    var ramp_distance: float = 40.0  # Distance to ramp up/down

    # Find water level under bridge
    var max_water_height: float = -10000.0
    for i in range(start_idx, end_idx + 1):
        var p: Vector3 = path[i]
        var water_h: float = float(Game.sea_level)
        if _world_ctx != null and _world_ctx.has_method("is_in_lake"):
            if _world_ctx.is_in_lake(p.x, p.z, 0.0):
                # Lake water level (approximate)
                water_h = _terrain_generator.get_height_at(p.x, p.z)
        max_water_height = maxf(max_water_height, water_h)

    var deck_height: float = max_water_height + clearance

    # Find bank heights for ramp blending
    var start_bank_height: float = path[start_idx].y if start_idx > 0 else deck_height
    var end_bank_height: float = path[end_idx].y if end_idx < path.size() - 1 else deck_height

    # Create bridge deck mesh
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var bridge_mat := StandardMaterial3D.new()
    bridge_mat.albedo_color = Color(0.12, 0.12, 0.13)  # Slightly lighter than road
    bridge_mat.roughness = 0.90
    bridge_mat.metallic = 0.15  # Slight metallic for structural look

    var dist_along: float = 0.0

    for i in range(start_idx, end_idx):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]

        # Use flattened XZ direction
        var dir_xz: Vector3 = Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
        var right: Vector3 = dir_xz.cross(Vector3.UP).normalized() * width * 0.5

        # Calculate positions with ramp blending
        var t0: float = float(i - start_idx) / float(end_idx - start_idx)
        var t1: float = float(i + 1 - start_idx) / float(end_idx - start_idx)

        # Smooth ramp using smoothstep
        var blend0: float = smoothstep(0.0, 0.25, t0) * smoothstep(1.0, 0.75, t0)
        var blend1: float = smoothstep(0.0, 0.25, t1) * smoothstep(1.0, 0.75, t1)

        var h0: float = lerpf(start_bank_height, deck_height, blend0) if t0 < 0.25 else lerpf(deck_height, end_bank_height, (t0 - 0.75) / 0.25) if t0 > 0.75 else deck_height
        var h1: float = lerpf(start_bank_height, deck_height, blend1) if t1 < 0.25 else lerpf(deck_height, end_bank_height, (t1 - 0.75) / 0.25) if t1 > 0.75 else deck_height

        var v0: Vector3 = Vector3(p0.x, h0, p0.z) - right
        var v1: Vector3 = Vector3(p0.x, h0, p0.z) + right
        var v2: Vector3 = Vector3(p1.x, h1, p1.z) + right
        var v3: Vector3 = Vector3(p1.x, h1, p1.z) - right

        # Distance-based UVs
        var segment_length: float = p0.distance_to(p1)
        var u_scale: float = 0.05
        var uv_start: float = dist_along * u_scale
        var uv_end: float = (dist_along + segment_length) * u_scale

        # Add deck surface
        st.set_normal(Vector3.UP); st.set_uv(Vector2(0.0, uv_start)); st.add_vertex(v0)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(1.0, uv_end)); st.add_vertex(v2)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(1.0, uv_start)); st.add_vertex(v1)

        st.set_normal(Vector3.UP); st.set_uv(Vector2(0.0, uv_start)); st.add_vertex(v0)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(0.0, uv_end)); st.add_vertex(v3)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(1.0, uv_end)); st.add_vertex(v2)

        # Add simple railings (vertical quads on sides)
        var rail_height: float = 1.2
        var rail_v0_bottom: Vector3 = v0
        var rail_v0_top: Vector3 = v0 + Vector3.UP * rail_height
        var rail_v3_bottom: Vector3 = v3
        var rail_v3_top: Vector3 = v3 + Vector3.UP * rail_height

        var rail_v1_bottom: Vector3 = v1
        var rail_v1_top: Vector3 = v1 + Vector3.UP * rail_height
        var rail_v2_bottom: Vector3 = v2
        var rail_v2_top: Vector3 = v2 + Vector3.UP * rail_height

        # Left railing
        var left_normal: Vector3 = -right.normalized()
        st.set_normal(left_normal); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(rail_v0_bottom)
        st.set_normal(left_normal); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(rail_v3_top)
        st.set_normal(left_normal); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(rail_v0_top)

        st.set_normal(left_normal); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(rail_v0_bottom)
        st.set_normal(left_normal); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(rail_v3_bottom)
        st.set_normal(left_normal); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(rail_v3_top)

        # Right railing
        var right_normal: Vector3 = right.normalized()
        st.set_normal(right_normal); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(rail_v1_bottom)
        st.set_normal(right_normal); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(rail_v1_top)
        st.set_normal(right_normal); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(rail_v2_top)

        st.set_normal(right_normal); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(rail_v1_bottom)
        st.set_normal(right_normal); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(rail_v2_top)
        st.set_normal(right_normal); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(rail_v2_bottom)

        dist_along += segment_length

    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    mi.material_override = bridge_mat
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

    # Add support pillars
    _add_bridge_pillars(mi, path, start_idx, end_idx, deck_height, width, bridge_mat)

    return mi


## Add support pillars/piers to a bridge
func _add_bridge_pillars(parent: MeshInstance3D, path: PackedVector3Array, start_idx: int, end_idx: int, deck_height: float, bridge_width: float, material: Material) -> void:
    if _terrain_generator == null:
        return

    var pillar_spacing: float = 60.0  # Pillars every 60m
    var pillar_width: float = bridge_width * 0.15  # Pillars are 15% of bridge width
    var pillar_depth: float = pillar_width * 0.8

    # Calculate bridge path length and place pillars
    var dist_along: float = 0.0
    var last_pillar_dist: float = 0.0

    for i in range(start_idx, end_idx):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]
        var segment_length: float = p0.distance_to(p1)

        # Check if we need a pillar in this segment
        while (dist_along - last_pillar_dist) >= pillar_spacing:
            last_pillar_dist += pillar_spacing

            # Find position along segment for pillar
            var t: float = (last_pillar_dist - (dist_along - segment_length)) / segment_length
            t = clampf(t, 0.0, 1.0)
            var pillar_pos_xz: Vector3 = p0.lerp(p1, t)

            # Get ground height under pillar
            var ground_height: float = _terrain_generator.get_height_at(pillar_pos_xz.x, pillar_pos_xz.z)

            # Only create pillar if significantly above ground (not on ramps)
            if (deck_height - ground_height) > 3.0:
                var pillar_mesh: MeshInstance3D = _create_single_pillar(
                    pillar_pos_xz.x,
                    pillar_pos_xz.z,
                    ground_height,
                    deck_height,
                    pillar_width,
                    pillar_depth,
                    material
                )
                if pillar_mesh != null:
                    parent.add_child(pillar_mesh)

        dist_along += segment_length


## Create a single bridge support pillar
func _create_single_pillar(x: float, z: float, bottom_y: float, top_y: float, width: float, depth: float, material: Material) -> MeshInstance3D:
    var height: float = top_y - bottom_y
    if height <= 0.0:
        return null

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var hw: float = width * 0.5
    var hd: float = depth * 0.5

    # Base vertices (at ground)
    var base_corners: Array[Vector3] = [
        Vector3(x - hw, bottom_y, z - hd),  # 0: back-left
        Vector3(x + hw, bottom_y, z - hd),  # 1: back-right
        Vector3(x + hw, bottom_y, z + hd),  # 2: front-right
        Vector3(x - hw, bottom_y, z + hd),  # 3: front-left
    ]

    # Top vertices (at deck level) - slightly tapered
    var taper: float = 0.9  # 90% width at top
    var top_corners: Array[Vector3] = [
        Vector3(x - hw * taper, top_y, z - hd * taper),  # 4: back-left
        Vector3(x + hw * taper, top_y, z - hd * taper),  # 5: back-right
        Vector3(x + hw * taper, top_y, z + hd * taper),  # 6: front-right
        Vector3(x - hw * taper, top_y, z + hd * taper),  # 7: front-left
    ]

    # Create 4 side faces
    var face_normals: Array[Vector3] = [
        Vector3(0, 0, -1),  # Back face
        Vector3(1, 0, 0),   # Right face
        Vector3(0, 0, 1),   # Front face
        Vector3(-1, 0, 0),  # Left face
    ]

    for side in range(4):
        var next_side: int = (side + 1) % 4
        var b0: Vector3 = base_corners[side]
        var b1: Vector3 = base_corners[next_side]
        var t0: Vector3 = top_corners[side]
        var t1: Vector3 = top_corners[next_side]
        var normal: Vector3 = face_normals[side]

        # Two triangles per face
        st.set_normal(normal); st.set_uv(Vector2(0, 1)); st.add_vertex(b0)
        st.set_normal(normal); st.set_uv(Vector2(1, 0)); st.add_vertex(t1)
        st.set_normal(normal); st.set_uv(Vector2(0, 0)); st.add_vertex(t0)

        st.set_normal(normal); st.set_uv(Vector2(0, 1)); st.add_vertex(b0)
        st.set_normal(normal); st.set_uv(Vector2(1, 1)); st.add_vertex(b1)
        st.set_normal(normal); st.set_uv(Vector2(1, 0)); st.add_vertex(t1)

    # Top cap (connects to bridge deck)
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
