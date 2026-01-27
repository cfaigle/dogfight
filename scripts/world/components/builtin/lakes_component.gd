extends WorldComponentBase
class_name LakesComponent

## Carves lakes into the heightmap and spawns simple lake meshes.
##
## Runs after `heightmap` and before `terrain_mesh`.

func get_priority() -> int:
	return 5

func get_optional_params() -> Dictionary:
	return {
		"lake_count": 8,
		"lake_min_radius": 160.0,
		"lake_max_radius": 520.0,
		"lake_depth_min": 10.0,
		"lake_depth_max": 45.0,
		"lake_min_height": Game.sea_level + 35.0,
		# Degrees (converted internally to slope gradient)
		"lake_max_slope": 10.0,
	}

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	if ctx == null or ctx.terrain_generator == null:
		push_error("LakesComponent: missing ctx/terrain_generator")
		return
	if ctx.water_bodies_generator == null:
		# Optional feature; no lakes
		return
	if ctx.hmap.is_empty() or ctx.hmap_res <= 0:
		push_warning("LakesComponent: heightmap missing, skipping")
		return

	var gen: RefCounted = ctx.water_bodies_generator
	if not gen.has_method("carve_lakes"):
		push_error("LakesComponent: water_bodies_generator missing carve_lakes")
		return

	var lakes: Array = gen.call("carve_lakes", ctx, params, rng)
	ctx.lakes = lakes

	# Heightmap was modified in-place; make sure terrain generator sees it.
	ctx.terrain_generator.set_heightmap_data(ctx.hmap, ctx.hmap_res, ctx.hmap_step, ctx.hmap_half)

	# Visualize lakes (simple discs). Ocean is still a global plane at sea level.
	if lakes.is_empty():
		return

	var water_layer: Node3D = ctx.get_layer("Water")
	var root_node := Node3D.new()
	root_node.name = "Lakes"
	water_layer.add_child(root_node)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.12, 0.18, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.18
	mat.metallic = 0.0

	for lk in lakes:
		if not (lk is Dictionary):
			continue
		var d := lk as Dictionary
		var center: Vector3 = d.get("center", Vector3.ZERO)
		var radius: float = float(d.get("radius", 200.0))
		var water_y: float = float(d.get("water_level", Game.sea_level + 2.0))

		var mi := MeshInstance3D.new()
		mi.name = "Lake"
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 0.6
		cyl.radial_segments = 48
		cyl.rings = 1
		mi.mesh = cyl
		mi.material_override = mat
		mi.position = Vector3(center.x, water_y + 0.12, center.z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root_node.add_child(mi)
