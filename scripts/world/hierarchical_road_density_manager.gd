class_name HierarchicalRoadDensityManager
extends RefCounted

## Manages hierarchical road density through recursive subdivision

var terrain_generator: TerrainGenerator = null
var world_context: WorldContext = null

# Density parameters
var max_highway_density: float = 0.3    # Highway density factor
var max_arterial_density: float = 0.8   # Arterial road density factor  
var max_local_density: float = 2.0      # Local road density factor

# Settlement classification thresholds
var major_city_threshold: int = 500     # Population threshold for major cities
var medium_town_threshold: int = 200    # Population threshold for medium towns
var small_settlement_threshold: int = 50 # Population threshold for small settlements

# Recursive subdivision parameters
var min_cell_size: float = 200.0        # Minimum cell size for subdivision
var max_depth: int = 4                  # Maximum recursion depth
var density_reduction_factor: float = 0.6 # Factor by which density reduces at each level

func set_terrain_generator(terrain_gen: TerrainGenerator) -> void:
    terrain_generator = terrain_gen

func set_world_context(world_ctx: WorldContext) -> void:
    world_context = world_ctx

## Calculate density score for a given area based on settlements and terrain
func calculate_area_density(center: Vector3, size: float, settlements: Array) -> Dictionary:
    var density_info: Dictionary = {
        "raw_score": 0.0,
        "population_score": 0.0,
        "terrain_score": 0.0,
        "accessibility_score": 0.0,
        "final_density": 0.0,
        "density_type": "wilderness"  # wilderness, rural, suburban, urban
    }
    
    if settlements.is_empty():
        return density_info
    
    # Calculate population-based density
    var total_pop: int = 0
    var nearby_settlements: Array = []
    
    for settlement in settlements:
        var settlement_pos: Vector3 = settlement.get("center", Vector3.ZERO)
        var dist: float = center.distance_to(settlement_pos)
        
        if dist <= size:
            nearby_settlements.append(settlement)
            total_pop += settlement.get("population", 0)
    
    density_info.population_score = float(total_pop) / (size * size / 10000.0)  # Normalize by area
    
    # Calculate terrain suitability score
    if terrain_generator != null:
        var avg_slope: float = 0.0
        var samples: int = 0
        
        # Sample terrain across the area
        var sample_step: float = max(size / 10.0, 50.0)
        for x in range(int(-size/2), int(size/2), int(sample_step)):
            for z in range(int(-size/2), int(size/2), int(sample_step)):
                var pos: Vector3 = Vector3(center.x + x, 0, center.z + z)
                var h: float = terrain_generator.get_height_at(pos.x, pos.z)
                
                # Only count if not underwater
                if world_context != null:
                    var sea_level_temp: float = world_context.get("sea_level")
                    if  sea_level_temp == null:
                        sea_level_temp = 20.0
                    var sea_level: float = float(sea_level_temp)
                    if h >= sea_level:
                        var slope: float = terrain_generator.get_slope_at(pos.x, pos.z)
                        avg_slope += slope
                        samples += 1
                else:
                    var slope: float = terrain_generator.get_slope_at(pos.x, pos.z)
                    avg_slope += slope
                    samples += 1
        
        if samples > 0:
            avg_slope /= float(samples)
            # Lower scores for steeper terrain (more difficult to build roads)
            density_info.terrain_score = max(0.0, 1.0 - (avg_slope / 30.0))  # Assuming 30° is very steep
        else:
            density_info.terrain_score = 0.0
    
    # Calculate accessibility score based on existing road network (if available)
    # This would check how well connected the area is to the broader road network
    density_info.accessibility_score = _calculate_accessibility_score(center, size, nearby_settlements)
    
    # Combine scores
    density_info.raw_score = (
        density_info.population_score * 0.6 + 
        density_info.terrain_score * 0.2 + 
        density_info.accessibility_score * 0.2
    )
    
    # Determine density type and final density value
    if density_info.raw_score > 5.0:
        density_info.density_type = "urban"
        density_info.final_density = min(density_info.raw_score, max_local_density)
    elif density_info.raw_score > 2.0:
        density_info.density_type = "suburban" 
        density_info.final_density = min(density_info.raw_score * 0.7, max_arterial_density)
    elif density_info.raw_score > 0.5:
        density_info.density_type = "rural"
        density_info.final_density = min(density_info.raw_score * 0.5, max_highway_density)
    else:
        density_info.density_type = "wilderness"
        density_info.final_density = 0.1  # Minimal road density
    
    return density_info

## Calculate accessibility score based on connection to existing infrastructure
func _calculate_accessibility_score(center: Vector3, size: float, nearby_settlements: Array) -> float:
    # This would typically check how well this area connects to the broader road network
    # For now, we'll use a simplified approach based on settlement clustering
    
    if nearby_settlements.size() < 2:
        return 0.2  # Low accessibility if isolated
    
    # Calculate how clustered the settlements are
    var centroid: Vector3 = Vector3.ZERO
    for settlement in nearby_settlements:
        centroid += settlement.get("center", Vector3.ZERO)
    centroid /= float(nearby_settlements.size())
    
    var avg_distance_to_centroid: float = 0.0
    for settlement in nearby_settlements:
        var pos: Vector3 = settlement.get("center", Vector3.ZERO)
        avg_distance_to_centroid += centroid.distance_to(pos)
    avg_distance_to_centroid /= float(nearby_settlements.size())
    
    # More clustered settlements = better accessibility
    var max_expected_distance: float = size / 2.0
    var clustering_factor: float = 1.0 - min(avg_distance_to_centroid / max_expected_distance, 1.0)
    
    return clustering_factor

## Perform recursive subdivision to determine road density hierarchy
func perform_recursive_subdivision(area_center: Vector3, area_size: float, settlements: Array, current_depth: int = 0) -> Array:
    var sub_areas: Array = []
    
    # Base case: if area is too small or max depth reached
    if area_size < min_cell_size or current_depth >= max_depth:
        var density_info: Dictionary = calculate_area_density(area_center, area_size, settlements)
        sub_areas.append({
            "center": area_center,
            "size": area_size,
            "density_info": density_info,
            "depth": current_depth
        })
        return sub_areas
    
    # Calculate density for current area
    var current_density_info: Dictionary = calculate_area_density(area_center, area_size, settlements)
    
    # If density is low, no need to subdivide further
    if current_density_info.final_density < 0.3:
        sub_areas.append({
            "center": area_center,
            "size": area_size,
            "density_info": current_density_info,
            "depth": current_depth
        })
        return sub_areas
    
    # Subdivide area into 4 quadrants
    var half_size: float = area_size / 2.0
    var quarter_size: float = area_size / 4.0
    
    var quadrants: Array[Vector3] = [
        Vector3(area_center.x - quarter_size, 0, area_center.z - quarter_size),  # Top-left
        Vector3(area_center.x + quarter_size, 0, area_center.z - quarter_size),  # Top-right
        Vector3(area_center.x - quarter_size, 0, area_center.z + quarter_size),  # Bottom-left
        Vector3(area_center.x + quarter_size, 0, area_center.z + quarter_size)   # Bottom-right
    ]
    
    for quadrant_center in quadrants:
        var quadrant_sub_areas: Array = perform_recursive_subdivision(
            quadrant_center, half_size, settlements, current_depth + 1
        )
        sub_areas.append_array(quadrant_sub_areas)
    
    return sub_areas

## Determine road type based on density and settlement characteristics
func determine_road_type(density_info: Dictionary, distance_to_nearest_settlement: float = INF) -> String:
    if density_info.density_type == "urban" or density_info.final_density > 3.0:
        return "highway"
    elif density_info.density_type == "suburban" or density_info.final_density > 1.5:
        return "arterial"
    elif density_info.density_type == "rural" or density_info.final_density > 0.5:
        return "local"
    else:
        return "access"  # Minimal access road for wilderness areas

## Generate road density map for an area
func generate_density_map(area_center: Vector3, area_size: float, settlements: Array) -> Dictionary:
    var subdivision_result: Array = perform_recursive_subdivision(area_center, area_size, settlements)
    
    var density_map: Dictionary = {
        "cells": [],
        "stats": {
            "total_cells": 0,
            "urban_cells": 0,
            "suburban_cells": 0, 
            "rural_cells": 0,
            "wilderness_cells": 0
        }
    }
    
    for cell in subdivision_result:
        density_map.cells.append(cell)
        
        # Update stats
        density_map.stats.total_cells += 1
        match cell.density_info.density_type:
            "urban":
                density_map.stats.urban_cells += 1
            "suburban":
                density_map.stats.suburban_cells += 1
            "rural":
                density_map.stats.rural_cells += 1
            "wilderness":
                density_map.stats.wilderness_cells += 1
    
    return density_map

## Get recommended road density for a specific location
func get_recommended_density(location: Vector3, settlements: Array) -> Dictionary:
    # Find the most appropriate subdivision cell for this location
    var closest_cell: Dictionary = {}
    var min_distance: float = INF
    
    # This would normally use a spatial data structure for efficiency
    # For now, we'll calculate on demand
    var dummy_map: Dictionary = generate_density_map(location, 2000.0, settlements)
    
    for cell in dummy_map.cells:
        var dist: float = location.distance_to(cell.center)
        if dist < min_distance:
            min_distance = dist
            closest_cell = cell
    
    if closest_cell != null:
        return closest_cell.density_info
    else:
        # Return default wilderness density
        return {
            "raw_score": 0.1,
            "population_score": 0.0,
            "terrain_score": 0.5,
            "accessibility_score": 0.0,
            "final_density": 0.1,
            "density_type": "wilderness"
        }