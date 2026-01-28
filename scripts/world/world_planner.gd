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


## Step 1: Strategic settlement placement
func _plan_settlement_locations() -> void:
	planned_settlements.clear()

	var terrain_size: float = float(Game.settings.get("terrain_size", 6000.0))
	var city_count: int = int(world_params.get("city_count", 1))
	var town_count: int = int(world_params.get("town_count", 6))
	var hamlet_count: int = int(world_params.get("hamlet_count", 12))

	print("   📍 Planning %d cities, %d towns, %d hamlets" % [city_count, town_count, hamlet_count])

	# CITY: Central location, flat terrain, large radius
	for _i in range(city_count):
		var location: Vector3 = _find_good_settlement_location("city", 800.0, 0.35)
		if location != Vector3.ZERO:
			var city_radius: float = rng.randf_range(520.0, 820.0)
			var city_population: int = rng.randi_range(800, 1500)

			planned_settlements.append({
				"type": "city",
				"center": location,
				"radius": city_radius,
				"population": city_population,
				"priority": 1
			})

	# TOWNS: Spread around map, good land
	for _i in range(town_count):
		var location: Vector3 = _find_good_settlement_location("town", 1200.0, 0.55)
		if location != Vector3.ZERO:
			var town_radius: float = rng.randf_range(300.0, 520.0)
			var town_population: int = rng.randi_range(300, 800)

			planned_settlements.append({
				"type": "town",
				"center": location,
				"radius": town_radius,
				"population": town_population,
				"priority": 2
			})

	# HAMLETS: Rural areas, can tolerate slopes
	for _i in range(hamlet_count):
		var location: Vector3 = _find_good_settlement_location("hamlet", 650.0, 0.65)
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
			continue

		# Must have acceptable slope
		if slope > max_slope:
			continue

		# Must not be too close to existing settlements
		if _too_close_to_settlements(location, min_spacing):
			continue

		# Valid location found!
		location.y = height
		return location

	# Failed to find location
	push_warning("WorldPlanner: Could not find valid location for %s after %d attempts" % [type, max_attempts])
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
