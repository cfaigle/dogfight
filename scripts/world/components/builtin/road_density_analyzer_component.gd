extends WorldComponentBase
class_name RoadDensityAnalyzerComponent

## Analyzes road network topology to calculate urban density
## Identifies emergent settlements from road intersection density
## Priority: 56 (after organic_roads)

func get_priority() -> int:
    return 56

func get_dependencies() -> Array[String]:
    return ["organic_roads"]

func get_optional_params() -> Dictionary:
    return {
        "density_grid_cell_size": 100.0,
        "density_urban_core_threshold": 15.0,
        "density_urban_threshold": 8.0,
        "density_suburban_threshold": 4.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null:
        push_error("RoadDensityAnalyzerComponent: missing ctx")
        return

    if not ctx.has_data("organic_roads"):
        push_warning("RoadDensityAnalyzerComponent: no organic_roads available")
        ctx.set_data("density_grid", {})
        ctx.set_data("emergent_settlements", [])
        return

    var roads: Array = ctx.get_data("organic_roads")
    # DEBUG: Verify roads data was preserved
    print("   🔧 RoadDensityAnalyzer: organic_roads received with ", roads.size(), " roads")
    var terrain_size: int = int(params.get("terrain_size", 4096))
    var cell_size: float = float(params.get("density_grid_cell_size", 100.0))

    # Build spatial grid for density calculation
    var density_grid := _build_density_grid(roads, terrain_size, cell_size)

    # Smooth density field
    _smooth_density_field(density_grid, cell_size, terrain_size)

    # Identify emergent urban centers
    var settlements := _identify_urban_centers(density_grid, cell_size, params)

    ctx.set_data("density_grid", density_grid)
    ctx.set_data("emergent_settlements", settlements)
    print("RoadDensityAnalyzer: Identified ", settlements.size(), " emergent settlements from road network")

func _build_density_grid(roads: Array, terrain_size: int, cell_size: float) -> Dictionary:
    var grid := {}

    # Count road segments per cell
    for road in roads:
        var path: PackedVector3Array = road.path
        for i in range(1, path.size()):
            var p1 := path[i - 1]
            var p2 := path[i]

            # Rasterize line segment into grid cells
            var cells := _rasterize_line_to_cells(p1, p2, cell_size)
            for cell in cells:
                if not grid.has(cell):
                    grid[cell] = {"road_count": 0, "intersection_count": 0, "density_score": 0.0}
                grid[cell].road_count += 1

    # Count intersections per cell
    var intersections := _find_road_intersections(roads)
    for intersection_pos in intersections:
        var cell := _world_to_cell(intersection_pos, cell_size)
        if not grid.has(cell):
            grid[cell] = {"road_count": 0, "intersection_count": 0, "density_score": 0.0}
        grid[cell].intersection_count += 1

    # Calculate density scores
    for cell in grid:
        var data = grid[cell]
        data.density_score = (data.road_count * 1.0) + (data.intersection_count * 5.0)

    return grid

func _smooth_density_field(grid: Dictionary, cell_size: float, terrain_size: int) -> void:
    # 2-iteration box filter for smooth transitions
    for iteration in range(2):
        var smoothed := {}

        for cell in grid:
            var neighbors := _get_neighbor_cells(cell)
            var sum := 0.0
            var count := 0

            for neighbor in neighbors:
                if grid.has(neighbor):
                    sum += grid[neighbor].density_score
                    count += 1

            if count > 0:
                smoothed[cell] = sum / float(count)
            else:
                smoothed[cell] = grid[cell].density_score

        # Apply smoothed values
        for cell in smoothed:
            if grid.has(cell):
                grid[cell].density_score = smoothed[cell]

func _identify_urban_centers(grid: Dictionary, cell_size: float, params: Dictionary) -> Array:
    var settlements: Array = []
    var urban_core_threshold: float = float(params.get("density_urban_core_threshold", 15.0))
    var urban_threshold: float = float(params.get("density_urban_threshold", 8.0))
    var suburban_threshold: float = float(params.get("density_suburban_threshold", 4.0))

    # Find local maxima in density field
    var local_maxima: Array = []
    for cell in grid:
        var density: float = grid[cell].density_score
        if density < suburban_threshold:
            continue

        var is_local_max := true
        var neighbors := _get_neighbor_cells(cell)
        for neighbor in neighbors:
            if grid.has(neighbor) and grid[neighbor].density_score > density:
                is_local_max = false
                break

        if is_local_max:
            local_maxima.append(cell)

    # Convert local maxima to settlements
    for cell in local_maxima:
        var density: float = grid[cell].density_score
        var density_class := ""
        var radius := 0.0

        if density >= urban_core_threshold:
            density_class = "urban_core"
            radius = 400.0
        elif density >= urban_threshold:
            density_class = "urban"
            radius = 300.0
        elif density >= suburban_threshold:
            density_class = "suburban"
            radius = 200.0
        else:
            density_class = "rural"
            radius = 100.0

        var center := _cell_to_world(cell, cell_size)
        settlements.append({
            "center": center,
            "radius": radius,
            "density_score": density,
            "density_class": density_class
        })

    return settlements

func _find_road_intersections(roads: Array) -> Array:
    var intersections: Array = []
    var threshold := 5.0  # Distance threshold for intersection detection

    # Find where road paths cross
    for i in range(roads.size()):
        for j in range(i + 1, roads.size()):
            var path1: PackedVector3Array = roads[i].path
            var path2: PackedVector3Array = roads[j].path

            # Check if paths share endpoints (actual intersection)
            for p1 in [path1[0], path1[path1.size() - 1]]:
                for p2 in [path2[0], path2[path2.size() - 1]]:
                    if p1.distance_to(p2) < threshold:
                        intersections.append((p1 + p2) * 0.5)

    return intersections

func _rasterize_line_to_cells(p1: Vector3, p2: Vector3, cell_size: float) -> Array:
    var cells := []
    var dist := p1.distance_to(p2)
    var steps: int = max(int(dist / cell_size) + 1, 2)

    for i in range(steps):
        var t := i / float(steps - 1)
        var pos := p1.lerp(p2, t)
        var cell := _world_to_cell(pos, cell_size)
        if not cells.has(cell):
            cells.append(cell)

    return cells

func _world_to_cell(pos: Vector3, cell_size: float) -> Vector2i:
    return Vector2i(int(pos.x / cell_size), int(pos.z / cell_size))

func _cell_to_world(cell: Vector2i, cell_size: float) -> Vector3:
    return Vector3(cell.x * cell_size + cell_size * 0.5, 0, cell.y * cell_size + cell_size * 0.5)

func _get_neighbor_cells(cell: Vector2i) -> Array:
    return [
        cell + Vector2i(-1, -1), cell + Vector2i(0, -1), cell + Vector2i(1, -1),
        cell + Vector2i(-1, 0),  cell,                   cell + Vector2i(1, 0),
        cell + Vector2i(-1, 1),  cell + Vector2i(0, 1),  cell + Vector2i(1, 1)
    ]
