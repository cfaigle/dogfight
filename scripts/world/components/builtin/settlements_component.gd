extends WorldComponentBase
class_name SettlementsComponent

func get_priority() -> int:
	return 60

func get_optional_params() -> Dictionary:
	return {
		"city_buildings": 600,
		"town_count": 5,
		"hamlet_count": 12,
	}

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	if ctx == null or ctx.settlement_generator == null:
		push_error("SettlementsComponent: missing ctx/settlement_generator")
		return

	print("🏘 SettlementsComponent: parametric_system = ", ctx.parametric_system)
	if ctx.parametric_system == null:
		push_warning("⚠️ SettlementsComponent: parametric_system is NULL - will use fallback boxes")
	else:
		print("✅ SettlementsComponent: parametric_system available, type = ", ctx.parametric_system.get_class())

	var infra_layer: Node3D = ctx.get_layer("Infrastructure")
	var out: Dictionary = ctx.settlement_generator.generate(infra_layer, params, rng, ctx.parametric_system)
	ctx.settlements = out.get("settlements", [])
	var groups: Array = out.get("prop_lod_groups", [])
	if groups.size() > 0:
		ctx.prop_lod_groups.append_array(groups)
