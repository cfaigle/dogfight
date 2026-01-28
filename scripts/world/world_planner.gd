class_name WorldPlanner
extends RefCounted

## High-level world planning coordinator
## Decides WHERE settlements go and HOW they connect

var terrain_generator: RefCounted = null
var rng: RandomNumberGenerator = null
var world_params: Dictionary = {}

# Planning outputs
var planned_settlements: Array = []  # Array of {type, center, radius, population, plan}
var regional_roads: Array = []  # Array of {from, to, type, width}


## Main planning entry point
func plan_world(terrain_gen: RefCounted, params: Dictionary, random: RandomNumberGenerator) -> Dictionary:
    terrain_generator = terrain_gen
    world_params = params
    rng = random

    print("🌍 WorldPlanner: Strategic world planning...")

    # Step 1: Plan settlement locations (WHERE to build)
    _plan_settlement_locations()

    # Step 2: Plan regional road network (HOW to connect)
    _plan_regional_roads()

    print("   ✅ Planned %d settlements and %d regional roads" % [planned_settlements.size(), regional_roads.size()])

    return {
        "settlements": planned_settlements,
        "regional_roads": regional_roads
    }


## Step 1: Strategic settlement placement using terrain regions
func _plan_settlement_locations() -> void:
    planned_settlements.clear()

    var terrain_size: float = float(Game.settings.get("terrain_size", 6000.0))
    var city_count: int = int(world_params.get("city_count", 1))
    var town_count: int = int(world_params.get("town_count", 6))
    var hamlet_count: int = int(world_params.get("hamlet_count", 12))

    print("   📍 Planning %d cities, %d towns, %d hamlets" % [city_count, town_count, hamlet_count])

    # Get terrain regions from world generation
    var terrain_regions = terrain_generator.terrain_regions if terrain_generator.has_method("get_terrain_regions") else {}
    
    # CITY: Central location, flat terrain, large radius - use plains when possible
    for _i in range(city_count):
        var base_radius: float = 500.0
        var location: Vector3 = _find_good_settlement_location_in_regions("city", base_radius, 0.45, terrain_regions, ["plains", "hills"])
        
        # If ideal location not found, try terrain-following placement
        if location == Vector3.ZERO:
            location = _find_terrain_following_settlement_location("city", base_radius, 0.65)
            if location != Vector3.ZERO:
                print("   ℹ️  City using terrain-following placement at ", location)
        
        # If still not found, try relaxed requirements
        if location == Vector3.ZERO:
            location = _find_good_settlement_location_in_regions("city", base_radius, 0.80, terrain_regions, ["plains", "hills", "mountains"])
            if location != Vector3.ZERO:
                print("   ⚠️  City using relaxed terrain requirements at ", location)
        
        if location != Vector3.ZERO:
            # Add size variation - some cities are much larger
            var size_factor: float = rng.randf_range(0.8, 2.5)  # 80% to 250% size range
            var city_radius: float = rng.randf_range(520.0, 820.0) * size_factor
            var city_population: int = int(rng.randi_range(800, 1500) * size_factor)

            planned_settlements.append({
                "type": "city",
                "center": location,
                "radius": city_radius,
                "population": city_population,
                "priority": 1
            })
        else:
            print("   ❌ Could not place city after all attempts")

    # TOWNS: Spread around map, good land
    for _i in range(town_count):
        var base_radius: float = 400.0
        var location: Vector3 = _find_good_settlement_location_in_regions("town", base_radius, 0.55, terrain_regions, ["plains", "hills"])
        
        # If ideal location not found, try terrain-following placement
        if location == Vector3.ZERO:
            location = _find_terrain_following_settlement_location("town", base_radius, 0.75)
            if location != Vector3.ZERO:
                print("   ℹ️  Town using terrain-following placement at ", location)
        
        # If still not found, try relaxed requirements
        if location == Vector3.ZERO:
            location = _find_good_settlement_location_in_regions("town", base_radius, 0.90, terrain_regions, ["plains", "hills", "mountains"])
            if location != Vector3.ZERO:
                print("   ⚠️  Town using relaxed terrain requirements at ", location)
        
        if location != Vector3.ZERO:
            # Add size variation - some towns are much larger
            var size_factor: float = rng.randf_range(0.6, 2.0)  # 60% to 200% size range
            var town_radius: float = rng.randf_range(300.0, 520.0) * size_factor
            var town_population: int = int(rng.randi_range(300, 800) * size_factor)

            planned_settlements.append({
                "type": "town",
                "center": location,
                "radius": town_radius,
                "population": town_population,
                "priority": 2
            })
        else:
            print("   ❌ Could not place town after all attempts")

    # HAMLETS: Rural areas, terrain-following placement
    for _i in range(hamlet_count):
        var location: Vector3 = _find_hamlet_location_terrain_following()
        if location != Vector3.ZERO:
            var hamlet_radius: float = rng.randf_range(150.0, 280.0)
            var hamlet_population: int = rng.randi_range(50, 200)

            planned_settlements.append({
                "type": "hamlet",
                "center": location,
                "radius": hamlet_radius,
                "population": hamlet_population,
                "priority": 3
            })


## Find good location for settlement type
func _find_good_settlement_location(type: String, min_spacing: float, max_slope: float) -> Vector3:
    var terrain_size: float = float(Game.settings.get("terrain_size", 6000.0))
    var half_size: float = terrain_size * 0.5
    var water_level: float = float(Game.sea_level)

    # Different search strategies per type
    var prefer_coast: bool = (type == "town" and rng.randf() < 0.3)  # 30% of towns near coast
    var max_attempts: int = 50

    for _attempt in range(max_attempts):
        var location: Vector3

        if type == "city":
            # Cities: prefer central areas
            location = Vector3(
                rng.randf_range(-half_size * 0.5, half_size * 0.5),
                0.0,
                rng.randf_range(-half_size * 0.5, half_size * 0.5)
            )
        elif prefer_coast:
            # Coastal towns
            var angle: float = rng.randf() * TAU
            var dist: float = half_size * rng.randf_range(0.7, 0.9)
            location = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
        else:
            # Random placement
            location = Vector3(
                rng.randf_range(-half_size * 0.8, half_size * 0.8),
                0.0,
                rng.randf_range(-half_size * 0.8, half_size * 0.8)
            )

        # Check terrain validity
        if terrain_generator == null:
            continue

        var height: float = terrain_generator.get_height_at(location.x, location.z)
        var slope: float = terrain_generator.get_slope_at(location.x, location.z)

        # Must be above water
        if height < water_level + 6.0:
            print("   ❌ Rejected ", type, " at ", location, ": too low (", height, " vs sea level ", water_level + 6.0, ")")
            continue

        # Must have acceptable slope
        if slope > max_slope:
            print("   ❌ Rejected ", type, " at ", location, ": too steep (", slope, " vs max ", max_slope, ")")
            continue

        # Must not be too close to existing settlements
        if _too_close_to_settlements(location, min_spacing):
            continue

        # Valid location found!
        location.y = height
        return location

    # Failed to find location - try more relaxed requirements
    print("   ⚠️ Could not find ideal location for ", type, ", trying relaxed requirements...")
    
    # Try with much more relaxed requirements
    for _attempt2 in range(20):
        var location2: Vector3
        if type == "city":
            location2 = Vector3(
                rng.randf_range(-half_size * 0.3, half_size * 0.3),  # Much smaller central area
                0.0,
                rng.randf_range(-half_size * 0.3, half_size * 0.3)
            )
        else:
            location2 = Vector3(
                rng.randf_range(-half_size * 0.4, half_size * 0.4),  # Much smaller area
                0.0,
                rng.randf_range(-half_size * 0.4, half_size * 0.4)
            )
        
        if terrain_generator == null:
            continue
        
        var height2: float = terrain_generator.get_height_at(location2.x, location2.z)
        var slope2: float = terrain_generator.get_slope_at(location2.x, location2.z)
        
        # Much more relaxed requirements
        if height2 >= water_level + 2.0 and slope2 <= 1.0:  # Very relaxed
            print("   ✅ Found relaxed location for ", type, ": ", location2)
            location2.y = height2
            return location2

    # Failed to find location
    push_warning("WorldPlanner: Could not find valid location for %s after %d attempts" % [type, max_attempts])
    return Vector3.ZERO


## Find settlement location using terrain regions
func _find_good_settlement_location_in_regions(type: String, base_radius: float, max_slope: float, terrain_regions: Dictionary, preferred_regions: Array) -> Vector3:
    var terrain_size: float = float(Game.settings.get("terrain_size", 6000.0))
    var half_size: float = terrain_size * 0.5
    var water_level: float = float(Game.sea_level)
    var max_attempts: int = 50
    
    print("   🔍 Looking for %s in preferred regions: %s" % [type, preferred_regions])
    
    # Try to find locations in preferred terrain regions first
    for attempt in range(max_attempts):
        var location: Vector3
        
        # Sample from preferred regions if available
        if terrain_regions.has("plains") and preferred_regions.has("plains"):
            # Try to place in plains first
            var plains_positions = terrain_regions.plains
            if plains_positions.size() > 0:
                var random_plain = plains_positions[rng.randi() % plains_positions.size()]
                var offset_x = rng.randf_range(-200, 200)
                var offset_z = rng.randf_range(-200, 200)
                location = Vector3(
                    -half_size + random_plain.x * (terrain_size / 192.0) + offset_x,
                    0.0,
                    -half_size + random_plain.y * (terrain_size / 192.0) + offset_z
                )
            else:
                # Fallback to random placement
                location = Vector3(
                    rng.randf_range(-half_size * 0.5, half_size * 0.5),
                    0.0,
                    rng.randf_range(-half_size * 0.5, half_size * 0.5)
                )
        else:
            # Random placement with regional bias
            location = Vector3(
                rng.randf_range(-half_size * 0.6, half_size * 0.6),
                0.0,
                rng.randf_range(-half_size * 0.6, half_size * 0.6)
            )
        
        if terrain_generator == null:
            continue
        
        var height: float = terrain_generator.get_height_at(location.x, location.z)
        var slope: float = terrain_generator.get_slope_at(location.x, location.z)
        
        # Check basic requirements
        if height < water_level + 5.0 or slope > max_slope:
            continue
        
        # Minimum spacing from other settlements
        var min_spacing: float = 600.0 if type == "city" else 400.0
        if _too_close_to_settlements(location, min_spacing):
            continue
        
        # Valid location found!
        print("   ✅ Found %s location in terrain region: height=%.1f, slope=%.2f" % [type, height, slope])
        location.y = height
        return location
    
    # Fallback to regular search if region-based fails
    print("   ⚠️ Region-based search failed for %s, trying regular search..." % type)
    return _find_good_settlement_location(type, base_radius, max_slope)


## Terrain-following hamlet placement algorithm
func _find_hamlet_location_terrain_following() -> Vector3:
    var terrain_size: float = float(Game.settings.get("terrain_size", 6000.0))
    var half_size: float = terrain_size * 0.5
    var water_level: float = float(Game.sea_level)
    var max_attempts: int = 100  # More attempts for hamlets
    
    print("   🏔️  Terrain-following hamlet placement...")
    
    # Strategy: Start from random high points and flow downhill to find good spots
    for attempt in range(max_attempts):
        # Start from a random point
        var start_x: float = rng.randf_range(-half_size * 0.8, half_size * 0.8)
        var start_z: float = rng.randf_range(-half_size * 0.8, half_size * 0.8)
        
        if terrain_generator == null:
            continue
        
        var start_height: float = terrain_generator.get_height_at(start_x, start_z)
        
        # Skip if starting underwater
        if start_height < water_level + 10.0:
            continue
        
        # Follow terrain downhill to find a good spot
        var current_pos: Vector3 = Vector3(start_x, start_height, start_z)
        var steps: int = 0
        var max_steps: int = 20
        
        while steps < max_steps:
            steps += 1
            
            # Sample neighboring points to find downhill direction
            var best_pos: Vector3 = current_pos
            var best_height: float = current_pos.y
            var found_lower: bool = false
            
            # Check 8 directions
            for angle_offset in range(0, 360, 45):
                var angle: float = deg_to_rad(float(angle_offset))
                var test_dist: float = 50.0
                var test_x: float = current_pos.x + cos(angle) * test_dist
                var test_z: float = current_pos.z + sin(angle) * test_dist
                
                # Keep within bounds
                if abs(test_x) > half_size * 0.9 or abs(test_z) > half_size * 0.9:
                    continue
                
                var test_height: float = terrain_generator.get_height_at(test_x, test_z)
                var test_slope: float = terrain_generator.get_slope_at(test_x, test_z)
                
                # Check if this is a good hamlet spot
                if test_height > water_level + 5.0 and test_height < water_level + 80.0:
                    if test_slope < 0.8:  # Reasonable slope for hamlet
                        # Check if it's lower than current (moving downhill)
                        if test_height < best_height:
                            best_pos = Vector3(test_x, test_height, test_z)
                            best_height = test_height
                            found_lower = true
                        # Or if it's a flat spot at reasonable height
                        elif test_slope < 0.3 and not found_lower:
                            # Check spacing from other settlements
                            if not _too_close_to_settlements(Vector3(test_x, 0, test_z), 200.0):
                                print("   ✅ Found terrain-following hamlet: height=%.1f, slope=%.2f" % [test_height, test_slope])
                                return Vector3(test_x, test_height, test_z)
            
            # Move to best lower position found
            if found_lower:
                current_pos = best_pos
            else:
                # No lower ground found, check current position
                var current_slope: float = terrain_generator.get_slope_at(current_pos.x, current_pos.z)
                if current_slope < 0.7 and current_pos.y > water_level + 5.0:
                    if not _too_close_to_settlements(Vector3(current_pos.x, 0, current_pos.z), 200.0):
                        print("   ✅ Found terrain-following hamlet at stopping point: height=%.1f, slope=%.2f" % [current_pos.y, current_slope])
                        return current_pos
                break  # Stop following this path
    
    # Fallback: Try random placement with very relaxed requirements
    print("   ⚠️ Terrain-following failed, trying random hamlet placement...")
    for fallback_attempt in range(30):
        var random_x: float = rng.randf_range(-half_size * 0.7, half_size * 0.7)
        var random_z: float = rng.randf_range(-half_size * 0.7, half_size * 0.7)
        
        var random_height: float = terrain_generator.get_height_at(random_x, random_z)
        var random_slope: float = terrain_generator.get_slope_at(random_x, random_z)
        
        # Very relaxed requirements for hamlets
        if random_height > water_level + 2.0 and random_slope < 1.2:
            if not _too_close_to_settlements(Vector3(random_x, 0, random_z), 150.0):
                print("   ✅ Found random hamlet: height=%.1f, slope=%.2f" % [random_height, random_slope])
                return Vector3(random_x, random_height, random_z)
    
    # Failed completely
    print("   ❌ Could not place hamlet after all attempts")
    return Vector3.ZERO


## Terrain-following placement for cities and towns (more flexible than ideal placement)
func _find_terrain_following_settlement_location(type: String, base_radius: float, max_slope: float) -> Vector3:
    var terrain_size: float = float(Game.settings.get("terrain_size", 6000.0))
    var half_size: float = terrain_size * 0.5
    var water_level: float = float(Game.sea_level)
    var max_attempts: int = 75
    
    print("   🏔️  Terrain-following ", type, " placement...")
    
    # Strategy: Start from random points and find best suitable location
    for attempt in range(max_attempts):
        var start_x: float = rng.randf_range(-half_size * 0.8, half_size * 0.8)
        var start_z: float = rng.randf_range(-half_size * 0.8, half_size * 0.8)
        
        if terrain_generator == null:
            continue
        
        var start_height: float = terrain_generator.get_height_at(start_x, start_z)
        
        # Skip if starting underwater or too high
        if start_height < water_level + 8.0 or start_height > water_level + 150.0:
            continue
        
        # Sample area around starting point to find best location
        var best_pos: Vector3 = Vector3.ZERO
        var best_score: float = -1.0
        
        # Check multiple points in the area
        for sample in range(12):
            var angle: float = rng.randf() * TAU
            var sample_dist: float = base_radius * rng.randf_range(0.5, 1.5)
            var sample_x: float = start_x + cos(angle) * sample_dist
            var sample_z: float = start_z + sin(angle) * sample_dist
            
            # Keep within bounds
            if abs(sample_x) > half_size * 0.9 or abs(sample_z) > half_size * 0.9:
                continue
            
            var sample_height: float = terrain_generator.get_height_at(sample_x, sample_z)
            var sample_slope: float = terrain_generator.get_slope_at(sample_x, sample_z)
            
            # Score this location (higher is better)
            var score: float = 0.0
            
            # Height score - prefer moderate elevation
            var height_score: float = 1.0 - abs(sample_height - (water_level + 30.0)) / 100.0
            height_score = clamp(height_score, 0.0, 1.0)
            
            # Slope score - prefer flatter areas
            var slope_score: float = 1.0 - sample_slope / max_slope
            slope_score = clamp(slope_score, 0.0, 1.0)
            
            # Combine scores
            score = (height_score * 0.6) + (slope_score * 0.4)
            
            # Check if this is the best so far
            if score > best_score:
                # Check spacing from other settlements
                if not _too_close_to_settlements(Vector3(sample_x, 0, sample_z), base_radius * 1.5):
                    best_pos = Vector3(sample_x, sample_height, sample_z)
                    best_score = score
        
        # If we found a good location
        if best_score > 0.5:  # At least 50% quality
            print("   ✅ Found terrain-following ", type, ": height=%.1f, slope=%.2f, score=%.2f" % [best_pos.y, terrain_generator.get_slope_at(best_pos.x, best_pos.z), best_score])
            return best_pos
    
    # Failed to find terrain-following location
    print("   ❌ Terrain-following ", type, " placement failed after ", max_attempts, " attempts")
    return Vector3.ZERO


## Check if too close to existing settlements
func _too_close_to_settlements(pos: Vector3, min_distance: float) -> bool:
    for settlement in planned_settlements:
        if settlement is Dictionary:
            var center: Vector3 = settlement.get("center", Vector3.ZERO)
            if pos.distance_to(center) < min_distance:
                return true
    return false


## Step 2: Plan regional road network using economic routing
func _plan_regional_roads() -> void:
    regional_roads.clear()

    if planned_settlements.is_empty():
        return

    # Classify settlements by hierarchy
    var major_hubs: Array = []
    var medium_towns: Array = []
    var minor_hamlets: Array = []

    for settlement in planned_settlements:
        if not settlement is Dictionary:
            continue

        var population: int = settlement.get("population", 100)
        var priority: int = settlement.get("priority", 3)

        if priority == 1 or population >= 500:
            major_hubs.append(settlement)
        elif priority == 2 or population >= 200:
            medium_towns.append(settlement)
        else:
            minor_hamlets.append(settlement)

    print("   🛣️  Road hierarchy: %d major hubs, %d medium towns, %d minor" % [major_hubs.size(), medium_towns.size(), minor_hamlets.size()])

    # Build MST for major hubs (economic cost-weighted)
    if major_hubs.size() >= 2:
        var mst_edges: Array = _build_economic_mst(major_hubs)

        for edge in mst_edges:
            regional_roads.append({
                "from": edge.from,
                "to": edge.to,
                "type": "highway",
                "width": 24.0,
                "cost_info": edge.cost_info
            })

    # Connect medium towns to nearest major hub
    for town in medium_towns:
        var town_pos: Vector3 = town.get("center", Vector3.ZERO)
        var town_pop: int = town.get("population", 200)
        var nearest_hub: Vector3 = _find_nearest_settlement(town_pos, major_hubs)

        if nearest_hub != Vector3.ZERO:
            var cost_info: Dictionary = _calculate_edge_cost(nearest_hub, town_pos)

            # Check economic viability
            if _is_economically_viable(cost_info, town_pop):
                regional_roads.append({
                    "from": nearest_hub,
                    "to": town_pos,
                    "type": "arterial",
                    "width": 16.0,
                    "cost_info": cost_info
                })
            else:
                print("   ❌ Rejected arterial to town (pop %d): %.0fm water" % [town_pop, cost_info.water_distance])

    # Connect minor hamlets (land-only routes)
    for hamlet in minor_hamlets:
        var hamlet_pos: Vector3 = hamlet.get("center", Vector3.ZERO)
        var hamlet_pop: int = hamlet.get("population", 50)
        var nearest: Vector3 = _find_nearest_settlement(hamlet_pos, major_hubs + medium_towns)

        if nearest != Vector3.ZERO:
            var cost_info: Dictionary = _calculate_edge_cost(nearest, hamlet_pos)

            # Hamlets: only if 95%+ land route (no expensive bridges)
            if cost_info.water_distance < (cost_info.total_distance * 0.05):
                regional_roads.append({
                    "from": nearest,
                    "to": hamlet_pos,
                    "type": "lane",
                    "width": 10.0,
                    "cost_info": cost_info
                })


## Build MST using economic cost (bridge penalty)
func _build_economic_mst(settlements: Array) -> Array:
    if settlements.size() < 2:
        return []

    # Build all possible edges with costs
    var edges: Array = []
    for i in range(settlements.size()):
        var si: Dictionary = settlements[i]
        var pi: Vector3 = si.get("center", Vector3.ZERO)

        for j in range(i + 1, settlements.size()):
            var sj: Dictionary = settlements[j]
            var pj: Vector3 = sj.get("center", Vector3.ZERO)

            var cost_info: Dictionary = _calculate_edge_cost(pi, pj)

            edges.append({
                "from": pi,
                "to": pj,
                "weight": cost_info.economic_cost,
                "from_idx": i,
                "to_idx": j,
                "cost_info": cost_info
            })

    # Sort by weight
    edges.sort_custom(func(a, b): return a.weight < b.weight)

    # Kruskal's MST algorithm
    var parent: Array = []
    parent.resize(settlements.size())
    for i in range(settlements.size()):
        parent[i] = i

    var find_root = func(x: int) -> int:
        while parent[x] != x:
            x = parent[x]
        return x

    var mst: Array = []
    for edge in edges:
        var rx: int = find_root.call(edge.from_idx)
        var ry: int = find_root.call(edge.to_idx)

        if rx != ry:
            mst.append(edge)
            parent[rx] = ry

            if mst.size() >= settlements.size() - 1:
                break

    return mst


## Calculate edge cost (land vs water distance)
func _calculate_edge_cost(from: Vector3, to: Vector3) -> Dictionary:
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

    # Ray-march along path
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

        var avg_height: float = (h0 + h1) * 0.5

        if avg_height < water_level:
            water_distance += segment_length
        else:
            land_distance += segment_length

    # Economic cost: bridges cost 15× more
    var bridge_cost_multiplier: float = 15.0
    var economic_cost: float = (land_distance * 1.0) + (water_distance * bridge_cost_multiplier)

    return {
        "total_distance": total_distance,
        "land_distance": land_distance,
        "water_distance": water_distance,
        "economic_cost": economic_cost
    }


## Check if road is economically viable
func _is_economically_viable(cost_info: Dictionary, population_served: int) -> bool:
    # Always allow land-only roads
    if cost_info.water_distance < 10.0:
        return true

    # Require minimum population for bridges
    var min_pop: int = 200
    if population_served < min_pop:
        return false

    # Check cost per capita
    var max_cost_per_capita: float = 50000.0
    var cost_per_person: float = cost_info.economic_cost / float(maxi(1, population_served))

    return cost_per_person <= max_cost_per_capita


## Find nearest settlement from list
func _find_nearest_settlement(pos: Vector3, settlements: Array) -> Vector3:
    var nearest: Vector3 = Vector3.ZERO
    var min_dist: float = INF

    for settlement in settlements:
        if not settlement is Dictionary:
            continue

        var center: Vector3 = settlement.get("center", Vector3.ZERO)
        var dist: float = pos.distance_to(center)

        if dist < min_dist:
            min_dist = dist
            nearest = center

    return nearest
