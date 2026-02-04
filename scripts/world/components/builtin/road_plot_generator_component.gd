extends WorldComponentBase
class_name RoadPlotGeneratorComponent

## Generates building plots along roads based on local density
## Priority: 57 (after density analysis)

func get_priority() -> int:
    return 57

func get_dependencies() -> Array[String]:
    return ["organic_roads", "road_density_analysis", "heightmap"]

func get_optional_params() -> Dictionary:
    return {
        "plot_urban_spacing": 25.0,
        "plot_suburban_spacing": 40.0,
        "plot_rural_spacing": 60.0,
        "plot_urban_setback": 15.0,
        "plot_suburban_setback": 20.0,
        "plot_rural_setback": 25.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("RoadPlotGeneratorComponent: missing ctx/terrain_generator")
        return

    if not ctx.has_data("organic_roads") or not ctx.has_data("density_grid"):
        push_warning("RoadPlotGeneratorComponent: missing organic_roads or density_grid")
        ctx.set_data("building_plots", [])
        return

    var roads: Array = ctx.get_data("organic_roads")
    var density_grid: Dictionary = ctx.get_data("density_grid")
    var terrain_size: int = int(params.get("terrain_size", 4096))
    var cell_size: float = float(params.get("density_grid_cell_size", 100.0))

    var all_plots: Array = []

    # Generate plots along each road
    for road in roads:
        var plots := _generate_plots_along_road(road, density_grid, cell_size, terrain_size, params)
        all_plots.append_array(plots)

    ctx.set_data("building_plots", all_plots)
    print("RoadPlotGenerator: Generated ", all_plots.size(), " building plots along ", roads.size(), " roads")

func _generate_plots_along_road(road: Dictionary, density_grid: Dictionary, cell_size: float, terrain_size: int, params: Dictionary) -> Array:
    var plots: Array = []
    var path: PackedVector3Array = road.path

    if path.size() < 2:
        return plots

    # Walk along road path
    for i in range(1, path.size()):
        var p1 := path[i - 1]
        var p2 := path[i]
        var segment_length := p1.distance_to(p2)
        var segment_dir := (p2 - p1).normalized()

        # Sample density at segment midpoint
        var mid_point := (p1 + p2) * 0.5
        var density := _sample_density_at_position(mid_point, density_grid, cell_size)
        var plot_params := _determine_plot_params(density, params)

        # Place plots along segment
        var local_dist := 0.0
        while local_dist < segment_length:
            var t := local_dist / segment_length
            var road_pos := p1.lerp(p2, t)

            # Place plots on both sides of road
            for side in [-1, 1]:
                var plot = _create_plot_at_position(road_pos, segment_dir, side, plot_params, terrain_size, road.get("type", "local"), params)
                if plot != null:
                    plots.append(plot)

            local_dist += plot_params.spacing

    return plots

func _determine_plot_params(density_score: float, params: Dictionary) -> Dictionary:
    var urban_core_threshold: float = float(params.get("density_urban_core_threshold", 15.0))
    var urban_threshold: float = float(params.get("density_urban_threshold", 8.0))
    var suburban_threshold: float = float(params.get("density_suburban_threshold", 4.0))

    var plot_params := {}

    if density_score >= urban_core_threshold:
        plot_params.density_class = "urban_core"
        plot_params.spacing = float(params.get("plot_urban_spacing", 15.0))
        plot_params.setback = float(params.get("plot_urban_setback", 8.0))
        plot_params.lot_width = 10.0
        plot_params.lot_depth = 12.0
        # Don't assign building type here - assign individually to each plot
        plot_params.height_category = "tall"
    elif density_score >= urban_threshold:
        plot_params.density_class = "urban"
        plot_params.spacing = 20.0
        plot_params.setback = 10.0
        plot_params.lot_width = 12.0
        plot_params.lot_depth = 14.0
        # Don't assign building type here - assign individually to each plot
        plot_params.height_category = "medium"
    elif density_score >= suburban_threshold:
        plot_params.density_class = "suburban"
        plot_params.spacing = float(params.get("plot_suburban_spacing", 30.0))
        plot_params.setback = float(params.get("plot_suburban_setback", 12.0))
        plot_params.lot_width = 14.0
        plot_params.lot_depth = 18.0
        # Don't assign building type here - assign individually to each plot
        plot_params.height_category = "low"
    else:
        plot_params.density_class = "rural"
        plot_params.spacing = float(params.get("plot_rural_spacing", 50.0))
        plot_params.setback = float(params.get("plot_rural_setback", 15.0))
        plot_params.lot_width = 20.0
        plot_params.lot_depth = 25.0
        # Don't assign building type here - assign individually to each plot
        plot_params.height_category = "low"

    return plot_params

func _create_plot_at_position(road_pos: Vector3, road_dir: Vector3, side: int, plot_params: Dictionary, terrain_size: int, road_type: String, params: Dictionary):
    # Calculate perpendicular direction (to the side of road)
    var perp_dir := Vector3(-road_dir.z, 0, road_dir.x) * side
    var plot_pos: Vector3 = road_pos + perp_dir * float(plot_params.setback)

    # Check terrain suitability
    if not _check_plot_buildability(plot_pos, terrain_size, params):
        return null

    # Calculate yaw to face road
    var yaw := atan2(-perp_dir.x, -perp_dir.z)

    # Assign random building type based on density class for this specific plot
    var building_type: String = ""
    var density_class = plot_params.density_class
    if density_class == "urban_core":
        var urban_core_types = ["office_building", "skyscraper", "victorian_mansion", "manor", "mansion", "villa", "chateau", "villa_italian"]
        building_type = urban_core_types[randi() % urban_core_types.size()]
    elif density_class == "urban":
        var urban_types = ["factory", "industrial", "factory_building", "warehouse", "workshop", "foundry", "mill_factory", "power_station", "train_station", "market_stall", "shop", "bakery", "inn", "tavern", "pub"]
        building_type = urban_types[randi() % urban_types.size()]
    elif density_class == "suburban":
        var suburban_types = ["white_stucco_house", "stone_farmhouse", "cottage_small", "cottage_medium", "cottage_large", "house_victorian", "house_colonial", "house_tudor", "stone_cottage", "stone_cottage_new", "thatched_cottage", "timber_cabin", "log_chalet", "cottage"]
        building_type = suburban_types[randi() % suburban_types.size()]
    else:  # rural
        var rural_types = ["grain_silo", "corn_feeder", "windmill", "mill", "radio_tower", "barn", "blacksmith", "farmhouse", "stable", "gristmill", "sawmill", "outbuilding", "granary", "fishing_hut", "shepherd_hut", "cottage", "stone_cottage", "stone_cottage_new", "thatched_cottage", "timber_cabin", "log_chalet", "rustic_cabin"]
        building_type = rural_types[randi() % rural_types.size()]

    return {
        "position": plot_pos,
        "yaw": yaw,
        "setback": plot_params.setback,
        "lot_width": plot_params.lot_width,
        "lot_depth": plot_params.lot_depth,
        "density_class": plot_params.density_class,
        "building_type": building_type,
        "height_category": plot_params.height_category
    }

func _check_plot_buildability(pos: Vector3, terrain_size: int, params: Dictionary) -> bool:
    # Check bounds - terrain is centered at origin
    var half: float = terrain_size * 0.5
    if pos.x < -half or pos.x > half or pos.z < -half or pos.z > half:
        return false

    # Check height above sea level
    var height := ctx.terrain_generator.get_height_at(pos.x, pos.z)
    var sea_level: float = float(params.get("sea_level", 0.0))
    if height < sea_level + 0.5:
        return false

    # Check slope - more permissive
    var slope := ctx.terrain_generator.get_slope_at(pos.x, pos.z)
    if slope > 40.0:
        return false

    return true

func _sample_density_at_position(pos: Vector3, density_grid: Dictionary, cell_size: float) -> float:
    var cell := Vector2i(int(pos.x / cell_size), int(pos.z / cell_size))
    if density_grid.has(cell):
        return density_grid[cell].density_score
    return 0.0
