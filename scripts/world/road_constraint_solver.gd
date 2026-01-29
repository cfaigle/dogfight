class_name RoadConstraintSolver
extends RefCounted

## Handles constraint satisfaction for road placement to avoid terrain obstacles

var terrain_generator: TerrainGenerator = null
var world_context: WorldContext = null

# Constraint parameters
var min_slope: float = 0.0  # degrees
var max_slope: float = 20.0  # degrees - roads shouldn't be too steep
var min_clearance: float = 2.0  # minimum clearance above terrain
var max_clearance: float = 15.0  # maximum clearance (avoid floating roads)
var water_avoidance_distance: float = 50.0  # distance to stay away from water
var settlement_avoidance_distance: float = 20.0  # distance to stay away from buildings
var obstacle_buffer: float = 10.0  # buffer around obstacles

func set_terrain_generator(terrain_gen: TerrainGenerator) -> void:
    terrain_generator = terrain_gen

func set_world_context(world_ctx: WorldContext) -> void:
    world_context = world_ctx

## Check if a potential road segment satisfies all constraints
func is_valid_road_segment(start_pos: Vector3, end_pos: Vector3, params: Dictionary = {}) -> bool:
    if terrain_generator == null:
        push_warning("RoadConstraintSolver: terrain_generator not set")
        return true  # Assume valid if no terrain data available
    
    var samples: int = max(10, int(start_pos.distance_to(end_pos) / 20.0))
    var sea_level: float = float(params.get("sea_level", 20.0))
    var min_road_length: float = float(params.get("min_road_length", 50.0))
    
    # Check minimum length
    if start_pos.distance_to(end_pos) < min_road_length:
        return false
    
    # Sample along the road segment
    for i in range(samples + 1):
        var t: float = float(i) / float(samples)
        var pos: Vector3 = start_pos.lerp(end_pos, t)
        
        # Check slope constraint
        var slope: float = terrain_generator.get_slope_at(pos.x, pos.z)
        if slope > max_slope:
            return false
        
        # Check terrain clearance
        var terrain_height: float = terrain_generator.get_height_at(pos.x, pos.z)
        var clearance: float = abs(pos.y - terrain_height)
        if clearance < min_clearance or clearance > max_clearance:
            return false
        
        # Check water avoidance
        if terrain_height < sea_level:
            return false
        
        # Check if in lake (if world context available)
        if world_context != null and world_context.has_method("is_in_lake"):
            if world_context.is_in_lake(pos.x, pos.z):
                return false
        
        # Check for obstacles near the path (if world context available)
        if world_context != null and world_context.has_method("has_obstacle_near"):
            if world_context.has_obstacle_near(pos.x, pos.z, obstacle_buffer):
                return false
    
    return true

## Calculate a cost for a potential road segment based on constraints
func calculate_road_cost(start_pos: Vector3, end_pos: Vector3, params: Dictionary = {}) -> float:
    var base_cost: float = start_pos.distance_to(end_pos)
    var constraint_penalty: float = 0.0
    
    if terrain_generator == null:
        return base_cost
    
    var samples: int = max(10, int(start_pos.distance_to(end_pos) / 20.0))
    var sea_level: float = float(params.get("sea_level", 20.0))
    
    # Sample along the road segment to calculate penalties
    for i in range(samples + 1):
        var t: float = float(i) / float(samples)
        var pos: Vector3 = start_pos.lerp(end_pos, t)
        
        # Slope penalty
        var slope: float = terrain_generator.get_slope_at(pos.x, pos.z)
        if slope > max_slope * 0.7:  # Apply penalty when approaching limit
            constraint_penalty += (slope - (max_slope * 0.7)) * 5.0  # Steeper slopes cost more
        
        # Terrain clearance penalty
        var terrain_height: float = terrain_generator.get_height_at(pos.x, pos.z)
        var clearance: float = abs(pos.y - terrain_height)
        if clearance < min_clearance * 0.5:
            constraint_penalty += (min_clearance * 0.5 - clearance) * 10.0
        elif clearance > max_clearance * 1.5:
            constraint_penalty += (clearance - max_clearance * 1.5) * 5.0
        
        # Water proximity penalty
        if terrain_height < (sea_level + 5.0):
            constraint_penalty += 50.0  # Significant penalty for being near water level
        
        # Check if in lake (if world context available)
        if world_context != null and world_context.has_method("is_in_lake"):
            if world_context.is_in_lake(pos.x, pos.z):
                constraint_penalty += 100.0  # Very high penalty for lakes
    
    return base_cost + constraint_penalty

## Find a valid path between two points that satisfies constraints
func find_constraint_satisfying_path(start_pos: Vector3, end_pos: Vector3, params: Dictionary = {}) -> PackedVector3Array:
    # This would implement a pathfinding algorithm that considers constraints
    # For now, return a straight line if valid, or empty array if not
    if is_valid_road_segment(start_pos, end_pos, params):
        var path: PackedVector3Array = PackedVector3Array()
        path.append(start_pos)
        path.append(end_pos)
        return path
    else:
        # In a full implementation, this would use a constrained pathfinding algorithm
        # For now, return empty to indicate no valid path found
        return PackedVector3Array()

## Check if a position is suitable for a road node
func is_valid_node_position(pos: Vector3, params: Dictionary = {}) -> bool:
    if terrain_generator == null:
        return true
    
    var terrain_height: float = terrain_generator.get_height_at(pos.x, pos.z)
    var sea_level: float = float(params.get("sea_level", 20.0))
    var slope: float = terrain_generator.get_slope_at(pos.x, pos.z)
    
    # Check if position is above water
    if terrain_height < sea_level:
        return false
    
    # Check if slope is acceptable
    if slope > max_slope:
        return false
    
    # Check if in lake (if world context available)
    if world_context != null and world_context.has_method("is_in_lake"):
        if world_context.is_in_lake(pos.x, pos.z):
            return false
    
    # Check for obstacles near the position (if world context available)
    if world_context != null and world_context.has_method("has_obstacle_near"):
        if world_context.has_obstacle_near(pos.x, pos.z, obstacle_buffer):
            return false
    
    return true

## Get a list of constraint-violating points along a path
func get_constraint_violations(start_pos: Vector3, end_pos: Vector3, params: Dictionary = {}) -> Array:
    var violations: Array = []
    
    if terrain_generator == null:
        return violations
    
    var samples: int = max(10, int(start_pos.distance_to(end_pos) / 20.0))
    var sea_level: float = float(params.get("sea_level", 20.0))
    
    for i in range(samples + 1):
        var t: float = float(i) / float(samples)
        var pos: Vector3 = start_pos.lerp(end_pos, t)
        var terrain_height: float = terrain_generator.get_height_at(pos.x, pos.z)
        var slope: float = terrain_generator.get_slope_at(pos.x, pos.z)
        
        var violation: Dictionary = {
            "position": pos,
            "violations": []
        }
        
        # Check slope
        if slope > max_slope:
            violation.violations.append({
                "type": "slope",
                "value": slope,
                "limit": max_slope
            })
        
        # Check terrain clearance
        var clearance: float = abs(pos.y - terrain_height)
        if clearance < min_clearance:
            violation.violations.append({
                "type": "clearance_low",
                "value": clearance,
                "limit": min_clearance
            })
        elif clearance > max_clearance:
            violation.violations.append({
                "type": "clearance_high", 
                "value": clearance,
                "limit": max_clearance
            })
        
        # Check water
        if terrain_height < sea_level:
            violation.violations.append({
                "type": "water",
                "value": terrain_height,
                "limit": sea_level
            })
        
        # Check lake
        if world_context != null and world_context.has_method("is_in_lake"):
            if world_context.is_in_lake(pos.x, pos.z):
                violation.violations.append({
                    "type": "lake"
                })
        
        if violation.violations.size() > 0:
            violations.append(violation)
    
    return violations