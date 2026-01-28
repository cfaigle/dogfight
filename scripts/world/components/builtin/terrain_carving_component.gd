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
        "road_carve_width_multiplier": 1.5,  # Carve wider than road (shoulders)
        "road_blend_distance": 8.0,  # Smooth transition distance (meters)
        "min_carve_depth": 0.5,  # Minimum terrain change (meters)
        "max_carve_depth": 8.0,  # Maximum cut/fill (meters)
        "embankment_slope": 0.5,  # Slope ratio for embankments (1:2)
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

    var width_multiplier: float = float(params.get("road_carve_width_multiplier", 1.5))
    var blend_distance: float = float(params.get("road_blend_distance", 8.0))
    var min_depth: float = float(params.get("min_carve_depth", 0.5))
    var max_depth: float = float(params.get("max_carve_depth", 8.0))
    var embankment_slope: float = float(params.get("embankment_slope", 0.5))

    var carved_count: int = 0
    var bridge_count: int = 0

    for road in roads:
        if not road is Dictionary:
            continue

        var path: PackedVector3Array = road.get("path", PackedVector3Array())
        var road_width: float = road.get("width", 12.0)
        var carve_width: float = road_width * width_multiplier

        if path.size() < 2:
            continue

        # Check if this road crosses water (is a bridge)
        var is_bridge: bool = _road_crosses_water(path, water_crossings)

        if is_bridge:
            bridge_count += 1
            continue  # Don't carve under bridges

        # Carve this road into terrain
        _carve_road_path(path, carve_width, blend_distance, min_depth, max_depth, embankment_slope)
        carved_count += 1

    print("   ⛏️ Carved %d roads (%d bridges left natural)" % [carved_count, bridge_count])

    # CRITICAL: Regenerate terrain mesh with modified heightmap
    # DEBUG: Check if Infrastructure layer exists before clearing
    var infra := ctx.get_layer("Infrastructure")
    print("   🔧 DEBUG: Before terrain regen, Infrastructure layer has ", infra.get_child_count() if infra != null else "null", " children")
    
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


## Carve a road path into the heightmap
func _carve_road_path(path: PackedVector3Array, carve_width: float, blend_distance: float, min_depth: float, max_depth: float, embankment_slope: float) -> void:
    # Sample points along path densely
    var sample_spacing: float = 5.0  # Sample every 5m
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

    # For each sample point, carve terrain in a radius
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

        # Modify heightmap in this region
        for hz in range(hmap_z_min, hmap_z_max + 1):
            for hx in range(hmap_x_min, hmap_x_max + 1):
                var world_x: float = float(hx) * hmap_step - hmap_half
                var world_z: float = float(hz) * hmap_step - hmap_half

                var dist_to_center: float = Vector2(world_x - sample_pos.x, world_z - sample_pos.z).length()

                # Calculate blend factor
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

                # Blend with existing terrain
                var new_height: float = lerpf(current_height, final_target, blend)

                # Apply the change
                ctx.hmap[idx] = new_height


## Force regeneration of terrain mesh with modified heightmap
func _regenerate_terrain_mesh() -> void:
    # DEBUG: Check if Infrastructure layer survived terrain regeneration
    var infra := ctx.get_layer("Infrastructure")
    print("   🔧 DEBUG: After terrain regen, Infrastructure layer has ", infra.get_child_count() if infra != null else "null", " children")
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
