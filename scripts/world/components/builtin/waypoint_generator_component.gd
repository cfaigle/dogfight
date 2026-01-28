extends WorldComponentBase
class_name WaypointGeneratorComponent

## Identifies interesting terrain features (valleys, plateaus, coasts) that roads should connect
## Priority: 54 (after landmarks, before roads)

func get_priority() -> int:
	return 54

func get_dependencies() -> Array[String]:
	return ["heightmap", "biomes"]

func get_optional_params() -> Dictionary:
	return {
		"waypoint_count": 250,
		"waypoint_coastal_count": 30,
		"waypoint_min_spacing": 400.0,
	}

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	if ctx == null or ctx.terrain_generator == null:
		push_error("WaypointGeneratorComponent: missing ctx/terrain_generator")
		return

	var terrain_size: int = int(params.get("terrain_size", 6000))
	print("   📍 WaypointGenerator: terrain_size = ", terrain_size)
	var sample_spacing: float = 200.0  # Sample every 200m

	# Sample terrain features on coarse grid
	var samples := _sample_terrain_features(terrain_size, sample_spacing, params)

	# Identify different waypoint types
	var valley_waypoints := _identify_valleys(samples, terrain_size)
	var plateau_waypoints := _identify_plateaus(samples)
	var mountain_waypoints := _identify_mountains(samples, terrain_size)  # NEW!
	var coastal_waypoints := _identify_coastal_nodes(terrain_size, params)
	var transition_waypoints := _identify_biome_transitions(samples, terrain_size)

	# Combine and score all waypoints
	var all_waypoints: Array = []
	all_waypoints.append_array(valley_waypoints)
	all_waypoints.append_array(plateau_waypoints)
	all_waypoints.append_array(mountain_waypoints)
	all_waypoints.append_array(coastal_waypoints)
	all_waypoints.append_array(transition_waypoints)

	print("   ⛰️ Found %d valleys, %d mountains, %d plateaus" % [
		valley_waypoints.size(), mountain_waypoints.size(), plateau_waypoints.size()
	])

	# Add player spawn as high-priority waypoint
	var player_spawn := ctx.runway_spawn
	if player_spawn != Vector3.ZERO:
		all_waypoints.append({
			"position": player_spawn,
			"type": "spawn",
			"priority": 100,
			"biome": "grassland",
			"buildability_score": 1.0
		})

	# Filter by minimum spacing and select top waypoints
	var min_spacing: float = float(params.get("waypoint_min_spacing", 500.0))
	var target_count: int = int(params.get("waypoint_count", 30))
	var filtered_waypoints := _filter_by_spacing(all_waypoints, min_spacing, target_count)

	ctx.set_data("waypoints", filtered_waypoints)
	print("WaypointGenerator: Generated ", filtered_waypoints.size(), " waypoints")

func _sample_terrain_features(terrain_size: int, spacing: float, params: Dictionary) -> Array:
	var samples: Array = []
	var sea_level: float = float(params.get("sea_level", 20.0))

	# Terrain is centered at origin, so sample from -half to +half
	var half: float = terrain_size * 0.5
	for x in range(-int(half), int(half), int(spacing)):
		for z in range(-int(half), int(half), int(spacing)):
			var pos := Vector3(x, 0, z)
			var height := ctx.terrain_generator.get_height_at(x, z)

			if height < sea_level + 1.0:
				continue  # Skip underwater points

			pos.y = height
			var slope := ctx.terrain_generator.get_slope_at(x, z)
			var curvature := _calculate_curvature(x, z, spacing * 0.5)
			var biome := _sample_biome(x, z, terrain_size)

			samples.append({
				"position": pos,
				"height": height,
				"slope": slope,
				"curvature": curvature,
				"biome": biome
			})

	return samples

func _identify_valleys(samples: Array, terrain_size: int) -> Array:
	var waypoints: Array = []
	var sea_level: float = float(ctx.params.get("sea_level", 20.0))
	var terrain_amp: float = float(ctx.params.get("terrain_amp", 100.0))
	var valley_threshold := sea_level + (terrain_amp * 0.3)  # 30% above sea level

	for sample in samples:
		# Valleys: lower than surroundings, gentle slope
		if sample.slope < 25.0 and sample.height < valley_threshold:  # More permissive slope
			var is_local_min := _is_local_minimum(sample.position, 400.0)
			if is_local_min:
				var buildability := _calculate_buildability(sample.slope, sample.height)
				if buildability > 0.2:  # More permissive buildability
					waypoints.append({
						"position": sample.position,
						"type": "valley",
						"priority": 8,
						"biome": sample.biome,
						"buildability_score": buildability
					})

	return waypoints

func _identify_plateaus(samples: Array) -> Array:
	var waypoints: Array = []

	for sample in samples:
		# Plateaus have low slope and low curvature (flat areas)
		if sample.slope < 20.0 and abs(sample.curvature) < 0.5:  # More permissive
			var buildability := _calculate_buildability(sample.slope, sample.height)
			if buildability > 0.3:  # Much more permissive
				waypoints.append({
					"position": sample.position,
					"type": "plateau",
					"priority": 10,
					"biome": sample.biome,
					"buildability_score": buildability
				})

	return waypoints

func _identify_mountains(samples: Array, terrain_size: int) -> Array:
	var waypoints: Array = []

	# Sort samples by height to find high points
	var sorted_samples := samples.duplicate()
	sorted_samples.sort_custom(func(a, b): return a.height > b.height)

	# Take top 10% as potential mountain candidates
	var mountain_candidates := sorted_samples.slice(0, max(40, sorted_samples.size() / 10))

	for sample in mountain_candidates:
		# Mountains: highest points with moderate slope
		if sample.slope < 35.0:
			var is_local_max := _is_local_maximum(sample.position, terrain_size, 400.0)
			if is_local_max:
				var buildability := _calculate_buildability(sample.slope, sample.height)
				if buildability > 0.2:  # Can tolerate steeper slopes
					waypoints.append({
						"position": sample.position,
						"type": "mountain",
						"priority": 9,  # High priority
						"biome": sample.biome,
						"buildability_score": buildability
					})

	return waypoints

func _identify_coastal_nodes(terrain_size: int, params: Dictionary) -> Array:
	var waypoints: Array = []
	var sea_level: float = float(params.get("sea_level", 20.0))
	var target_count: int = int(params.get("waypoint_coastal_count", 10))
	var step := terrain_size / maxi(target_count, 4)

	# Sample perimeter of terrain
	for i in range(0, terrain_size, step):
		var positions := [
			Vector2(i, 0),
			Vector2(i, terrain_size - 1),
			Vector2(0, i),
			Vector2(terrain_size - 1, i)
		]

		for pos_2d in positions:
			var height := ctx.terrain_generator.get_height_at(pos_2d.x, pos_2d.y)
			if height > sea_level + 1.0 and height < sea_level + 20.0:
				var slope := ctx.terrain_generator.get_slope_at(pos_2d.x, pos_2d.y)
				if slope < 25.0:
					waypoints.append({
						"position": Vector3(pos_2d.x, height, pos_2d.y),
						"type": "coast",
						"priority": 7,
						"biome": "coast",
						"buildability_score": 0.8
					})

	return waypoints

func _identify_biome_transitions(samples: Array, terrain_size: int) -> Array:
	var waypoints: Array = []

	for sample in samples:
		# Check if different biomes exist within radius
		var has_transition := _check_biome_variety(sample.position, 100.0, terrain_size)
		if has_transition and sample.slope < 20.0:
			var buildability := _calculate_buildability(sample.slope, sample.height)
			if buildability > 0.5:
				waypoints.append({
					"position": sample.position,
					"type": "transition",
					"priority": 6,
					"biome": sample.biome,
					"buildability_score": buildability
				})

	return waypoints

func _filter_by_spacing(waypoints: Array, min_spacing: float, target_count: int) -> Array:
	# Sort by priority descending
	waypoints.sort_custom(func(a, b): return a.priority > b.priority)

	var filtered: Array = []
	var min_spacing_sq := min_spacing * min_spacing

	for wp in waypoints:
		var too_close := false
		for existing in filtered:
			if wp.position.distance_squared_to(existing.position) < min_spacing_sq:
				too_close = true
				break

		if not too_close:
			filtered.append(wp)
			if filtered.size() >= target_count:
				break

	return filtered

func _calculate_curvature(x: float, z: float, radius: float) -> float:
	# 2nd derivative approximation
	var h_center := ctx.terrain_generator.get_height_at(x, z)
	var h_right := ctx.terrain_generator.get_height_at(x + radius, z)
	var h_left := ctx.terrain_generator.get_height_at(x - radius, z)

	var d2h := (h_right + h_left - 2.0 * h_center) / (radius * radius)
	return d2h

func _is_local_minimum(pos: Vector3, radius: float) -> bool:
	var h_center := pos.y
	var samples := 8
	for i in range(samples):
		var angle := (i / float(samples)) * TAU
		var offset := Vector2(cos(angle), sin(angle)) * radius
		var sample_h := ctx.terrain_generator.get_height_at(pos.x + offset.x, pos.z + offset.y)
		if sample_h < h_center:
			return false
	return true

func _is_local_maximum(pos: Vector3, terrain_size: int, radius: float) -> bool:
	var h_center := pos.y
	var samples := 8
	for i in range(samples):
		var angle := (i / float(samples)) * TAU
		var offset := Vector2(cos(angle), sin(angle)) * radius
		var sample_h := ctx.terrain_generator.get_height_at(pos.x + offset.x, pos.z + offset.y)
		if sample_h > h_center:
			return false
	return true

func _calculate_buildability(slope: float, height: float) -> float:
	var sea_level: float = float(ctx.params.get("sea_level", 20.0))
	var slope_score: float = clamp(1.0 - slope / 30.0, 0.0, 1.0)
	var height_score: float = 1.0 if height > sea_level + 0.5 else 0.0
	return slope_score * height_score

func _sample_biome(x: float, z: float, terrain_size: int) -> String:
	if ctx.biome_map == null:
		return "grassland"

	var biome_res := ctx.biome_map.get_width()
	var px := clampi(int(x / terrain_size * biome_res), 0, biome_res - 1)
	var pz := clampi(int(z / terrain_size * biome_res), 0, biome_res - 1)
	var color := ctx.biome_map.get_pixel(px, pz)
	var biome_idx := int(color.r * 7.999)
	var biome_names := ["ocean", "beach", "grassland", "forest", "desert", "mountain", "snow", "tundra"]
	return biome_names[biome_idx]

func _check_biome_variety(pos: Vector3, radius: float, terrain_size: int) -> bool:
	var center_biome := _sample_biome(pos.x, pos.z, terrain_size)
	var samples := 8
	for i in range(samples):
		var angle := (i / float(samples)) * TAU
		var offset := Vector2(cos(angle), sin(angle)) * radius
		var sample_biome := _sample_biome(pos.x + offset.x, pos.z + offset.y, terrain_size)
		if sample_biome != center_biome:
			return true
	return false
