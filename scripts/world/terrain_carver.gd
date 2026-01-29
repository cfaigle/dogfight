class_name TerrainCarver
extends RefCounted

## Modifies terrain beneath roads to create realistic road beds and proper integration

var terrain_generator = null

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen

## Carve terrain along a road path
func carve_road_terrain(waypoints: PackedVector3Array, width: float, depth: float = 0.5, 
                       shoulder_width: float = 2.0, shoulder_depth: float = 0.2) -> void:
    if waypoints.size() < 2 or terrain_generator == null:
        return
    
    # Calculate carving parameters
    var half_width: float = width / 2.0
    var half_total_width: float = half_width + shoulder_width
    var total_width: float = width + (shoulder_width * 2)
    
    # Process each segment of the road
    for i in range(waypoints.size() - 1):
        var start_point: Vector3 = waypoints[i]
        var end_point: Vector3 = waypoints[i + 1]
        
        # Calculate direction and perpendicular vectors
        var direction: Vector3 = (end_point - start_point).normalized()
        var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()
        
        # Carve along the segment
        _carve_road_segment(start_point, end_point, direction, perpendicular, 
                           half_width, depth, shoulder_width, shoulder_depth)

## Carve a single road segment
func _carve_road_segment(start: Vector3, end: Vector3, direction: Vector3, perpendicular: Vector3,
                         half_road_width: float, road_depth: float, 
                         shoulder_width: float, shoulder_depth: float) -> void:
    # Calculate the length of this segment
    var segment_length: float = start.distance_to(end)
    var num_samples: int = max(5, int(segment_length / 5.0))  # Sample every 5m or 5 samples minimum
    
    # Sample along the segment
    for i in range(num_samples + 1):
        var t: float = float(i) / float(num_samples)
        var center_point: Vector3 = start.lerp(end, t)
        
        # Carve the road bed
        _carve_elliptical_hole(center_point, half_road_width, road_depth, 0.0)
        
        # Carve shoulders on both sides
        var left_shoulder_center: Vector3 = center_point - perpendicular * (half_road_width + shoulder_width/2.0)
        var right_shoulder_center: Vector3 = center_point + perpendicular * (half_road_width + shoulder_width/2.0)
        
        _carve_elliptical_hole(left_shoulder_center, shoulder_width/2.0, shoulder_depth, 0.3)  # Less deep with more smoothing
        _carve_elliptical_hole(right_shoulder_center, shoulder_width/2.0, shoulder_depth, 0.3)

## Carve an elliptical hole in the terrain
func _carve_elliptical_hole(center: Vector3, radius: float, depth: float, smoothing: float = 0.5) -> void:
    if terrain_generator == null or not terrain_generator.has_method("get_height_at") or not terrain_generator.has_method("set_height_at"):
        return
    
    # Determine the area to modify
    var cell_size = 10.0  # Default cell size if not available
    if terrain_generator.has_method("get_cell_size"):
        cell_size = terrain_generator.get_cell_size()
    
    var min_x: int = int(floor((center.x - radius) / cell_size))
    var max_x: int = int(ceil((center.x + radius) / cell_size))
    var min_z: int = int(floor((center.z - radius) / cell_size))
    var max_z: int = int(ceil((center.z + radius) / cell_size))
    
    # Iterate through the affected area
    for x in range(min_x, max_x + 1):
        for z in range(min_z, max_z + 1):
            var world_x: float = float(x) * cell_size
            var world_z: float = float(z) * cell_size
            
            # Calculate distance from center
            var dist: float = sqrt(pow(world_x - center.x, 2) + pow(world_z - center.z, 2))
            
            if dist <= radius:
                # Calculate the influence based on distance and smoothing
                var normalized_dist: float = dist / radius
                var influence: float = 1.0 - pow(normalized_dist, 2)  # Quadratic falloff
                influence = lerp(influence, 0.0, smoothing)  # Apply smoothing
                
                # Calculate new height
                var current_height: float = terrain_generator.get_height_at(world_x, world_z)
                var target_height: float = center.y - depth
                var new_height: float = lerp(current_height, target_height, influence)
                
                # Set the new height
                terrain_generator.set_height_at(x, z, new_height)

## Smooth terrain transitions around roads
func smooth_road_transitions(waypoints: PackedVector3Array, width: float, transition_distance: float = 10.0) -> void:
    if waypoints.size() < 2 or terrain_generator == null:
        return
    
    var half_width: float = width / 2.0
    var total_half_width: float = half_width + transition_distance
    
    for i in range(waypoints.size() - 1):
        var start_point: Vector3 = waypoints[i]
        var end_point: Vector3 = waypoints[i + 1]
        
        var direction: Vector3 = (end_point - start_point).normalized()
        var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()
        
        var segment_length: float = start_point.distance_to(end_point)
        var num_samples: int = max(5, int(segment_length / 15.0))
        
        for j in range(num_samples + 1):
            var t: float = float(j) / float(num_samples)
            var center_point: Vector3 = start_point.lerp(end_point, t)
            
            # Smooth the terrain in the transition zone
            _smooth_transition_area(center_point, perpendicular, half_width, transition_distance)

## Smooth a transition area around the road
func _smooth_transition_area(center: Vector3, perpendicular: Vector3, road_half_width: float, 
                             transition_distance: float) -> void:
    if terrain_generator == null or not terrain_generator.has_method("get_height_at") or not terrain_generator.has_method("set_height_at"):
        return
    
    var cell_size = 10.0  # Default cell size if not available
    if terrain_generator.has_method("get_cell_size"):
        cell_size = terrain_generator.get_cell_size()
    
    var total_half_width: float = road_half_width + transition_distance
    var min_x: int = int(floor((center.x - total_half_width) / cell_size))
    var max_x: int = int(ceil((center.x + total_half_width) / cell_size))
    var min_z: int = int(floor((center.z - total_half_width) / cell_size))
    var max_z: int = int(ceil((center.z + total_half_width) / cell_size))
    
    # Collect heights in a larger area to compute averages
    var height_samples: Array = []
    
    for x in range(max(min_x, 0), min(max_x, 1000)):  # Using 1000 as a large number, should be replaced with actual terrain size
        for z in range(max(min_z, 0), min(max_z, 1000)):
            var world_x: float = float(x) * cell_size
            var world_z: float = float(z) * cell_size
            var height: float = terrain_generator.get_height_at(world_x, world_z)
            height_samples.append(height)
    
    if height_samples.size() > 0:
        # Calculate average height
        var avg_height: float = 0.0
        for h in height_samples:
            avg_height += h
        avg_height /= float(height_samples.size())
        
        # Apply smoothing gradually from road edge outward
        for x in range(max(min_x, 0), min(max_x, 1000)):
            for z in range(max(min_z, 0), min(max_z, 1000)):
                var world_x: float = float(x) * cell_size
                var world_z: float = float(z) * cell_size
                
                var to_point: Vector3 = Vector3(world_x - center.x, 0, world_z - center.z)
                var dist_from_center_line: float = abs(perpendicular.dot(to_point))
                var dist_from_road_edge: float = abs(dist_from_center_line - road_half_width)
                
                if dist_from_road_edge <= transition_distance:
                    var influence: float = 1.0 - (dist_from_road_edge / transition_distance)
                    influence = pow(influence, 2)  # Quadratic falloff for smoother transition
                    
                    var current_height: float = terrain_generator.get_height_at(world_x, world_z)
                    var new_height: float = lerp(current_height, avg_height, influence * 0.3)  # Gentle smoothing
                    terrain_generator.set_height_at(x, z, new_height)