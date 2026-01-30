extends WorldComponentBase
class_name TerrainCarvingComponent

## Physically modifies terrain heightmap to create flat road beds
## Runs AFTER heightmap generation but BEFORE terrain mesh
## Solves road clipping by carving roads into the landscape

func get_priority() -> int:
    return 58  # After organic_building_placement (65), before terrain_mesh regeneration

func get_dependencies() -> Array[String]:
    return ["heightmap", "organic_road_network"]

func get_optional_params() -> Dictionary:
    return {
        "enable_terrain_carving": true,
        "road_carve_width_multiplier": 2.0,  # Carve wider than road (shoulders) - increased for better integration
        "road_blend_distance": 12.0,  # Smooth transition distance (meters) - increased for better blending
        "min_carve_depth": 0.3,  # Minimum terrain change (meters) - reduced for more sensitivity
        "max_carve_depth": 12.0,  # Maximum cut/fill (meters) - increased for major terrain modifications
        "embankment_slope": 0.3,  # Slope ratio for embankments (1:3) - gentler slopes
        "carve_density": 3.0,  # Sample points every 3m along road for carving
        "carve_depth_offset": 0.5,  # Additional offset to ensure roads sit properly in terrain
        "drainage_channels": true,  # Add drainage channels alongside roads
        "shoulder_width_multiplier": 1.3,  # Width multiplier for road shoulders
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if not bool(params.get("enable_terrain_carving", true)):
        return

    if ctx == null or ctx.terrain_generator == null:
        push_error("TerrainCarvingComponent: missing ctx or terrain_generator")
        return

    if not ctx.has_data("organic_roads"):
        push_warning("TerrainCarvingComponent: no organic_roads to carve")
        return

    if ctx.hmap == null or ctx.hmap.is_empty():
        push_error("TerrainCarvingComponent: heightmap not available")
        return

    print("⛏️ TerrainCarvingComponent: Carving roads into terrain...")

    var roads: Array = ctx.get_data("organic_roads")
    var water_crossings: Array = []
    if ctx.has_data("water_crossings"):
        water_crossings = ctx.get_data("water_crossings")

    var width_multiplier: float = float(params.get("road_carve_width_multiplier", 2.0))
    var blend_distance: float = float(params.get("road_blend_distance", 12.0))
    var min_depth: float = float(params.get("min_carve_depth", 0.3))
    var max_depth: float = float(params.get("max_carve_depth", 12.0))
    var embankment_slope: float = float(params.get("embankment_slope", 0.3))
    var carve_density: float = float(params.get("carve_density", 3.0))
    var carve_depth_offset: float = float(params.get("carve_depth_offset", 0.5))
    var create_drainage: bool = bool(params.get("drainage_channels", true))
    var shoulder_width_mult: float = float(params.get("shoulder_width_multiplier", 1.3))

    var carved_count: int = 0
    var bridge_count: int = 0

    for road in roads:
        if not road is Dictionary:
            continue

        var path: PackedVector3Array = road.get("path", PackedVector3Array())
        var road_width: float = road.get("width", 12.0)
        var shoulder_width: float = road_width * shoulder_width_mult
        var carve_width: float = road_width * width_multiplier

        if path.size() < 2:
            continue

        # Check if this road crosses water (is a bridge)
        var is_bridge: bool = _road_crosses_water(path, water_crossings)

        if is_bridge:
            bridge_count += 1
            continue  # Don't carve under bridges

        # Carve this road into terrain with enhanced parameters
        _carve_road_path(path, carve_width, blend_distance, min_depth, max_depth, embankment_slope, carve_depth_offset, create_drainage)
        carved_count += 1

    print("   ⛏️ Carved %d roads (%d bridges left natural)" % [carved_count, bridge_count])

    # CRITICAL: Regenerate terrain mesh with modified heightmap
    _regenerate_terrain_mesh()


## Check if road crosses water (is a bridge)
func _road_crosses_water(path: PackedVector3Array, water_crossings: Array) -> bool:
    if water_crossings.is_empty():
        return false

    # Sample midpoint and quarter points
    var samples: Array[Vector3] = [
        path[0],
        path[path.size() / 4],
        path[path.size() / 2],
        path[path.size() * 3 / 4],
        path[path.size() - 1]
    ]

    for sample in samples:
        for crossing in water_crossings:
            if not crossing is Dictionary:
                continue
            var center: Vector3 = crossing.get("center", Vector3.ZERO)
            var width: float = crossing.get("width", 100.0)

            if sample.distance_to(center) < width * 0.5 + 50.0:
                return true  # Road crosses this water zone

    return false


## Carve a road path into the heightmap with enhanced detail
func _carve_road_path(path: PackedVector3Array, carve_width: float, blend_distance: float, min_depth: float, max_depth: float, embankment_slope: float, carve_depth_offset: float = 0.5, create_drainage: bool = true) -> void:
    # Sample points along path more densely for better carving
    var sample_spacing: float = 3.0  # Sample every 3m (more detailed)
    var samples: Array = []

    for i in range(path.size() - 1):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]
        var dist: float = p0.distance_to(p1)
        var segments: int = maxi(1, int(dist / sample_spacing))

        for j in range(segments):
            var t: float = float(j) / float(segments)
            var p: Vector3 = p0.lerp(p1, t)
            # Adjust height to be slightly below terrain for better integration
            var terrain_height: float = ctx.terrain_generator.get_height_at(p.x, p.z)
            var adjusted_y: float = min(p.y, terrain_height - carve_depth_offset)
            samples.append(Vector3(p.x, adjusted_y, p.z))

    # Add final point
    if path.size() > 0:
        var final_point: Vector3 = path[path.size() - 1]
        var terrain_height: float = ctx.terrain_generator.get_height_at(final_point.x, final_point.z)
        var adjusted_final_y: float = min(final_point.y, terrain_height - carve_depth_offset)
        samples.append(Vector3(final_point.x, adjusted_final_y, final_point.z))

    # For each sample point, carve terrain in a radius with multi-pass approach
    var total_carve_width: float = carve_width + blend_distance * 2.0
    var half_width: float = total_carve_width * 0.5

    for sample in samples:
        var sample_pos: Vector3 = sample as Vector3
        var target_height: float = sample_pos.y

        # Carve in a square around this point
        var world_x_min: float = sample_pos.x - half_width
        var world_x_max: float = sample_pos.x + half_width
        var world_z_min: float = sample_pos.z - half_width
        var world_z_max: float = sample_pos.z + half_width

        # Convert to heightmap indices
        var hmap_res: int = ctx.hmap_res
        var hmap_step: float = ctx.hmap_step
        var hmap_half: float = ctx.hmap_half

        var hmap_x_min: int = maxi(0, int((world_x_min + hmap_half) / hmap_step))
        var hmap_x_max: int = mini(hmap_res - 1, int((world_x_max + hmap_half) / hmap_step))
        var hmap_z_min: int = maxi(0, int((world_z_min + hmap_half) / hmap_step))
        var hmap_z_max: int = mini(hmap_res - 1, int((world_z_max + hmap_half) / hmap_step))

        # Multi-pass carving for better results
        for pass_num in range(2):  # Two passes for better carving
            # Modify heightmap in this region
            for hz in range(hmap_z_min, hmap_z_max + 1):
                for hx in range(hmap_x_min, hmap_x_max + 1):
                    var world_x: float = float(hx) * hmap_step - hmap_half
                    var world_z: float = float(hz) * hmap_step - hmap_half

                    var dist_to_center: float = Vector2(world_x - sample_pos.x, world_z - sample_pos.z).length()

                    # Calculate blend factor with more nuanced approach
                    var blend: float = 0.0
                    if dist_to_center < carve_width * 0.5:
                        # Inside road - full carve
                        blend = 1.0
                    elif dist_to_center < carve_width * 0.5 + blend_distance:
                        # Blend zone - smooth transition
                        var t: float = (dist_to_center - carve_width * 0.5) / blend_distance
                        blend = 1.0 - smoothstep(0.0, 1.0, t)
                    else:
                        # Outside influence - skip
                        continue

                    # Get current height
                    var idx: int = hz * hmap_res + hx
                    var current_height: float = ctx.hmap[idx]

                    # Calculate target height (road bed or embankment)
                    var final_target: float = target_height

                    # If we're on a slope, create embankment
                    var height_diff: float = current_height - target_height
                    if abs(height_diff) > min_depth:
                        # Clamp to max cut/fill
                        height_diff = clampf(height_diff, -max_depth, max_depth)

                        # Calculate embankment height based on distance
                        if dist_to_center > carve_width * 0.5 * 0.8:  # Outer 20% of road
                            var embankment_factor: float = (dist_to_center - carve_width * 0.5 * 0.8) / (carve_width * 0.5 * 0.2)
                            embankment_factor = clampf(embankment_factor, 0.0, 1.0)
                            # Gradual slope up/down
                            final_target = target_height + height_diff * embankment_factor * embankment_slope

                    # Blend with existing terrain (with stronger effect in first pass)
                    var pass_blend_factor: float = 0.7 if pass_num == 0 else 0.3
                    var new_height: float = lerpf(current_height, final_target, blend * pass_blend_factor)

                    # Apply the change
                    ctx.hmap[idx] = new_height

    # Add drainage channels if enabled
    if create_drainage:
        _add_drainage_channels(path, carve_width, blend_distance)


## Add drainage channels alongside roads
func _add_drainage_channels(path: PackedVector3Array, road_width: float, blend_distance: float) -> void:
    if path.size() < 2:
        return

    # Calculate channel positions (typically on the sides of the road)
    var channel_depth: float = 0.8  # Depth of drainage channel
    var channel_width: float = road_width * 0.3  # Width of drainage channel (30% of road width)
    var channel_offset: float = road_width * 0.7  # Distance from road center to channel center

    # Sample points along path for drainage
    var sample_spacing: float = 8.0  # Drainage channel sampling
    var samples: Array = []

    for i in range(path.size() - 1):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]
        var dist: float = p0.distance_to(p1)
        var segments: int = maxi(1, int(dist / sample_spacing))

        for j in range(segments):
            var t: float = float(j) / float(segments)
            var p: Vector3 = p0.lerp(p1, t)
            samples.append(p)

    # Add final point
    if path.size() > 0:
        samples.append(path[path.size() - 1])

    # Calculate direction vectors for perpendicular channel placement
    for i in range(samples.size()):
        var sample_pos: Vector3 = samples[i] as Vector3

        # Calculate direction vector for this segment
        var direction: Vector3
        if i == 0 and samples.size() > 1:
            direction = (samples[1] as Vector3 - sample_pos).normalized()
        elif i == samples.size() - 1:
            direction = (sample_pos - (samples[i-1] as Vector3)).normalized()
        else:
            var prev_dir: Vector3 = (sample_pos - (samples[i-1] as Vector3)).normalized()
            var next_dir: Vector3 = ((samples[i+1] as Vector3) - sample_pos).normalized()
            direction = (prev_dir + next_dir).normalized()

        # Calculate perpendicular vector for channel placement
        var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()

        # Create channels on both sides of the road
        for side in [-1, 1]:
            var channel_center: Vector3 = sample_pos + perpendicular * channel_offset * side

            # Carve drainage channel
            _carve_drainage_channel(channel_center, channel_width, channel_depth, blend_distance)


## Carve a single drainage channel
func _carve_drainage_channel(center: Vector3, width: float, depth: float, blend_distance: float) -> void:
    var total_width: float = width + blend_distance * 2.0
    var half_width: float = total_width * 0.5

    # Convert to heightmap indices
    var hmap_res: int = ctx.hmap_res
    var hmap_step: float = ctx.hmap_step
    var hmap_half: float = ctx.hmap_half

    var world_x_min: float = center.x - half_width
    var world_x_max: float = center.x + half_width
    var world_z_min: float = center.z - half_width
    var world_z_max: float = center.z + half_width

    var hmap_x_min: int = maxi(0, int((world_x_min + hmap_half) / hmap_step))
    var hmap_x_max: int = mini(hmap_res - 1, int((world_x_max + hmap_half) / hmap_step))
    var hmap_z_min: int = maxi(0, int((world_z_min + hmap_half) / hmap_step))
    var hmap_z_max: int = mini(hmap_res - 1, int((world_z_max + hmap_half) / hmap_step))

    # Modify heightmap in this region
    for hz in range(hmap_z_min, hmap_z_max + 1):
        for hx in range(hmap_x_min, hmap_x_max + 1):
            var world_x: float = float(hx) * hmap_step - hmap_half
            var world_z: float = float(hz) * hmap_step - hmap_half

            var dist_to_center: float = Vector2(world_x - center.x, world_z - center.z).length()

            # Calculate blend factor
            var blend: float = 0.0
            if dist_to_center < width * 0.5:
                # Inside channel - full depth
                blend = 1.0
            elif dist_to_center < width * 0.5 + blend_distance:
                # Blend zone - smooth transition
                var t: float = (dist_to_center - width * 0.5) / blend_distance
                blend = 1.0 - smoothstep(0.0, 1.0, t)
            else:
                # Outside influence - skip
                continue

            # Get current height
            var idx: int = hz * hmap_res + hx
            var current_height: float = ctx.hmap[idx]

            # Calculate target height (channel bottom)
            var target_height: float = current_height - depth * blend

            # Apply the change
            ctx.hmap[idx] = target_height


## Force regeneration of terrain mesh with modified heightmap
func _regenerate_terrain_mesh() -> void:
    print("   🔄 Regenerating terrain mesh with carved roads...")

    if ctx.terrain_generator == null:
        push_error("TerrainCarvingComponent: terrain_generator not available")
        return

    # Get the world root to find terrain container
    var terrain_root: Node3D = ctx.terrain_render_root
    if terrain_root == null:
        push_warning("TerrainCarvingComponent: terrain_render_root not found, skipping mesh regeneration")
        return

    # Clear existing terrain meshes
    for child in terrain_root.get_children():
        child.queue_free()

    # Rebuild terrain with modified heightmap
    # terrain_generator.build_terrain() will read from ctx.hmap which we just carved
    var terrain_params: Dictionary = {
        "terrain_size": float(Game.settings.get("terrain_size", 6000.0)),
        "terrain_amp": float(Game.settings.get("terrain_amp", 300.0)),
        "terrain_res": int(Game.settings.get("terrain_res", 1024)),
        "terrain_chunk_cells": int(Game.settings.get("terrain_chunk_cells", 32)),
        "terrain_lod_enabled": bool(Game.settings.get("terrain_lod_enabled", true)),
        "terrain_lod0_r": float(Game.settings.get("terrain_lod0_radius", 3250.0)),
        "terrain_lod1_r": float(Game.settings.get("terrain_lod1_radius", 8000.0)),
    }

    # Create a minimal RNG for terrain generation (deterministic)
    var rng := RandomNumberGenerator.new()
    rng.seed = int(Game.settings.get("world_seed", 12345))

    # Rebuild terrain mesh (build_terrain returns the root node)
    var new_terrain_root: Node3D = ctx.terrain_generator.build_terrain(
        terrain_root.get_parent() if terrain_root.get_parent() else ctx.get_layer("Terrain"),
        terrain_params,
        rng
    )

    # Update context reference
    if new_terrain_root != null:
        ctx.terrain_render_root = new_terrain_root

    print("   ✅ Terrain mesh regenerated with carved roads")
