class_name RoadCostOptimizer
extends RefCounted

## Optimizes road routing using cost functions that consider multiple factors

var terrain_generator: TerrainGenerator = null
var world_context: WorldContext = null

# Cost weights - these can be tuned to prioritize certain factors
var terrain_cost_weight: float = 1.0      # Weight for terrain difficulty
var water_crossing_cost: float = 500.0    # Flat cost for water crossings
var slope_cost_weight: float = 5.0        # Weight for steep slopes
var curve_cost_weight: float = 2.0        # Weight for sharp curves
var length_cost_weight: float = 0.5       # Weight for total length
var settlement_proximity_bonus: float = -50.0  # Bonus for passing near settlements
var environmental_cost: float = 100.0     # Cost for environmentally sensitive areas

# Thresholds and limits
var max_slope_for_roads: float = 20.0     # Maximum slope in degrees
var min_curve_radius: float = 30.0        # Minimum curve radius in meters

func set_terrain_generator(terrain_gen: TerrainGenerator) -> void:
    terrain_generator = terrain_gen

func set_world_context(world_ctx: WorldContext) -> void:
    world_context = world_ctx

## Calculate the total cost of a potential road segment
func calculate_segment_cost(start_pos: Vector3, end_pos: Vector3, params: Dictionary = {}) -> Dictionary:
    var cost_details: Dictionary = {
        "base_length_cost": 0.0,
        "terrain_cost": 0.0,
        "slope_cost": 0.0,
        "water_crossing_cost": 0.0,
        "environmental_cost": 0.0,
        "settlement_bonus": 0.0,
        "total_cost": 0.0,
        "feasibility": true,
        "factors": []
    }
    
    if terrain_generator == null:
        cost_details.total_cost = start_pos.distance_to(end_pos) * length_cost_weight
        return cost_details
    
    var distance: float = start_pos.distance_to(end_pos)
    var samples: int = max(5, int(distance / 50.0))  # Sample every ~50m or 5 samples minimum
    
    # Base length cost
    cost_details.base_length_cost = distance * length_cost_weight
    
    # Sample along the path to calculate various costs
    var total_terrain_cost: float = 0.0
    var total_slope_cost: float = 0.0
    var total_environmental_cost: float = 0.0
    var has_water_crossing: bool = false
    var has_environmental_issue: bool = false
    
    var prev_pos: Vector3 = start_pos
    var prev_slope: float = terrain_generator.get_slope_at(prev_pos.x, prev_pos.z)
    
    for i in range(1, samples + 1):
        var t: float = float(i) / float(samples)
        var pos: Vector3 = start_pos.lerp(end_pos, t)
        
        # Terrain height and slope
        var height: float = terrain_generator.get_height_at(pos.x, pos.z)
        var slope: float = terrain_generator.get_slope_at(pos.x, pos.z)
        
        # Sea level check
        var sea_level: float = float(params.get("sea_level", 20.0))
        if height < sea_level:
            has_water_crossing = true
            # Additional cost for being underwater
            total_terrain_cost += 10.0
        
        # Slope cost
        if slope > max_slope_for_roads:
            cost_details.feasibility = false
            cost_details.factors.append("slope_too_steep: %.2f > %.2f" % [slope, max_slope_for_roads])
        if slope > max_slope_for_roads * 0.7:  # Apply cost when approaching limit
            total_slope_cost += (slope - (max_slope_for_roads * 0.7)) * slope_cost_weight
        
        # Terrain difficulty cost (based on roughness/complexity)
        total_terrain_cost += _calculate_terrain_difficulty(pos.x, pos.z) * terrain_cost_weight
        
        # Environmental cost (if applicable)
        if _is_environmentally_sensitive(pos.x, pos.z):
            has_environmental_issue = true
            total_environmental_cost += environmental_cost
        
        # Curve cost calculation (requires previous position and slope)
        if i > 1:
            var current_slope = terrain_generator.get_slope_at(pos.x, pos.z)
            var slope_change = abs(current_slope - prev_slope)
            
            # If there's a significant change in slope, it might indicate a curve or difficult terrain
            if slope_change > 5.0:  # Arbitrary threshold for significant change
                cost_details.factors.append("slope_change_at_%d: %.2f" % [i, slope_change])
        
        prev_pos = pos
        prev_slope = slope
    
    # Apply bonuses for passing near settlements (if world context available)
    var settlement_bonus: float = 0.0
    if world_context != null and world_context.has_method("get_nearby_settlements"):
        var nearby_settlements = world_context.get_nearby_settlements(end_pos.x, end_pos.z, 500.0)
        if nearby_settlements.size() > 0:
            settlement_bonus = -nearby_settlements.size() * settlement_proximity_bonus  # Negative = bonus
    
    # Sum up costs
    cost_details.terrain_cost = total_terrain_cost / float(max(samples, 1))  # Average per unit length
    cost_details.slope_cost = total_slope_cost / float(max(samples, 1))
    cost_details.water_crossing_cost = water_crossing_cost if has_water_crossing else 0.0
    cost_details.environmental_cost = total_environmental_cost
    cost_details.settlement_bonus = settlement_bonus
    
    cost_details.total_cost = (
        cost_details.base_length_cost +
        cost_details.terrain_cost +
        cost_details.slope_cost +
        cost_details.water_crossing_cost +
        cost_details.environmental_cost +
        cost_details.settlement_bonus  # May be negative (bonus)
    )
    
    return cost_details

## Calculate terrain difficulty based on local variation
func _calculate_terrain_difficulty(x: float, z: float) -> float:
    # Calculate local terrain complexity by sampling nearby points
    var center_height: float = terrain_generator.get_height_at(x, z)
    var sample_distance: float = 20.0
    var total_variation: float = 0.0
    
    # Sample in 4 directions around the point
    var directions: Array[Vector2] = [
        Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN,
        Vector2.RIGHT + Vector2.UP, Vector2.RIGHT + Vector2.DOWN,
        Vector2.LEFT + Vector2.UP, Vector2.LEFT + Vector2.DOWN
    ]
    
    for dir in directions:
        var sample_x: float = x + dir.x * sample_distance
        var sample_z: float = z + dir.y * sample_distance
        var sample_height: float = terrain_generator.get_height_at(sample_x, sample_z)
        total_variation += abs(sample_height - center_height)
    
    # Average variation across all samples
    var avg_variation: float = total_variation / float(directions.size())
    
    # Return normalized difficulty (0-1 scale based on expected max variation)
    return min(avg_variation / 10.0, 1.0)  # Clamp to 0-1 range

## Check if a location is environmentally sensitive
func _is_environmentally_sensitive(x: float, z: float) -> bool:
    # This would check against protected areas, rare biomes, etc.
    # For now, return false - in a real implementation this would check world data
    return false

## Optimize a path between two points using cost minimization
func optimize_path(start_pos: Vector3, end_pos: Vector3, params: Dictionary = {}) -> Dictionary:
    # This would implement a more sophisticated pathfinding algorithm that
    # minimizes the cost function rather than just distance
    # For now, return the direct path with cost evaluation
    
    var direct_path_cost: Dictionary = calculate_segment_cost(start_pos, end_pos, params)
    
    var result: Dictionary = {
        "optimal_path": PackedVector3Array([start_pos, end_pos]),
        "cost_details": direct_path_cost,
        "is_feasible": direct_path_cost.feasibility,
        "alternative_paths": []  # Would contain other possible routes in a full implementation
    }
    
    # In a full implementation, this would use A* or similar with the cost function
    # to find the lowest-cost path, not just the straight-line path
    
    return result

## Optimize road network for a set of settlements
func optimize_settlement_network(settlements: Array, params: Dictionary = {}) -> Dictionary:
    var optimization_result: Dictionary = {
        "recommended_connections": [],
        "total_cost": 0.0,
        "feasibility_report": [],
        "optimization_stats": {}
    }
    
    if settlements.size() < 2:
        return optimization_result
    
    # For each pair of settlements, calculate connection cost
    var connections: Array = []
    
    for i in range(settlements.size()):
        for j in range(i + 1, settlements.size()):
            var settlement_a: Dictionary = settlements[i]
            var settlement_b: Dictionary = settlements[j]
            
            var pos_a: Vector3 = settlement_a.get("center", Vector3.ZERO)
            var pos_b: Vector3 = settlement_b.get("center", Vector3.ZERO)
            
            if pos_a != Vector3.ZERO and pos_b != Vector3.ZERO:
                var cost_info: Dictionary = calculate_segment_cost(pos_a, pos_b, params)
                
                var connection: Dictionary = {
                    "settlement_a": settlement_a,
                    "settlement_b": settlement_b,
                    "cost_details": cost_info,
                    "total_cost": cost_info.total_cost,
                    "is_feasible": cost_info.feasibility,
                    "distance": pos_a.distance_to(pos_b)
                }
                
                connections.append(connection)
    
    # Sort connections by cost (lowest first) - but consider feasibility
    connections.sort_custom(func(a, b):
        if a.is_feasible and not b.is_feasible:
            return true
        elif not a.is_feasible and b.is_feasible:
            return false
        else:
            return a.total_cost < b.total_cost
    )
    
    # Select connections based on optimization strategy
    # This could implement MST, Prim's algorithm, or other network optimization
    
    optimization_result.recommended_connections = connections
    optimization_result.total_cost = 0.0
    
    for conn in connections:
        optimization_result.total_cost += conn.total_cost
        
        if not conn.is_feasible:
            optimization_result.feasibility_report.append({
                "connection": "%s to %s" % [conn.settlement_a.get("name", "unknown"), conn.settlement_b.get("name", "unknown")],
                "issues": conn.cost_details.factors
            })
    
    optimization_result.optimization_stats = {
        "total_possible_connections": connections.size(),
        "feasible_connections": len(connections.filter(func(conn): return conn.is_feasible)),
        "infeasible_connections": len(connections.filter(func(conn): return not conn.is_feasible))
    }
    
    return optimization_result

## Evaluate the economic viability of a road connection
func evaluate_economic_viability(cost_details: Dictionary, population_served: int, params: Dictionary = {}) -> Dictionary:
    var evaluation: Dictionary = {
        "is_viable": true,
        "cost_per_capita": 0.0,
        "viability_score": 1.0,
        "recommendation": "build",
        "justification": ""
    }
    
    if population_served <= 0:
        evaluation.is_viable = false
        evaluation.recommendation = "reject"
        evaluation.justification = "No population to serve"
        return evaluation
    
    var total_cost: float = cost_details.total_cost
    var cost_per_capita: float = total_cost / float(population_served)
    
    evaluation.cost_per_capita = cost_per_capita
    
    # Economic thresholds
    var max_cost_per_capita: float = float(params.get("max_cost_per_capita", 10000.0))
    var min_cost_effectiveness_ratio: float = float(params.get("min_cost_effectiveness_ratio", 0.1))
    
    if cost_per_capita > max_cost_per_capita:
        evaluation.is_viable = false
        evaluation.viability_score = max_cost_per_capita / cost_per_capita  # Ratio showing how far over budget
        evaluation.recommendation = "reject"
        evaluation.justification = "Cost per capita (%.2f) exceeds maximum (%.2f)" % [cost_per_capita, max_cost_per_capita]
    elif cost_per_capita > max_cost_per_capita * 0.8:
        evaluation.viability_score = 0.5
        evaluation.recommendation = "consider_with_alternatives"
        evaluation.justification = "Cost per capita is high (%.2f), consider alternatives" % cost_per_capita
    else:
        evaluation.viability_score = 1.0 - (cost_per_capita / max_cost_per_capita)  # Higher score for lower cost
        evaluation.recommendation = "approve"
        evaluation.justification = "Cost per capita is reasonable (%.2f)" % cost_per_capita
    
    return evaluation