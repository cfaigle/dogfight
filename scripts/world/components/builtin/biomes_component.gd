extends WorldComponentBase
class_name BiomesComponent

## Builds a coarse biome map that other components can query.
##
## This component does not add geometry; it only populates:
##  - ctx.biome_generator (service)
##  - ctx.biome_map (Image)

func get_priority() -> int:
    return 8

func get_optional_params() -> Dictionary:
    return {
        "biome_map_res": 256,
        "biome_debug": false,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("BiomesComponent: missing ctx/terrain_generator")
        return
    if ctx.biome_generator == null:
        # Optional feature
        return
    var gen: RefCounted = ctx.biome_generator
    if not gen.has_method("generate_biome_map"):
        push_error("BiomesComponent: biome_generator missing generate_biome_map")
        return

    ctx.biome_map = gen.call("generate_biome_map", ctx, params)

    # Optional: spawn a hidden debug plane (for future toggle)
    if bool(params.get("biome_debug", false)) and ctx.biome_map != null:
        var tex := ImageTexture.create_from_image(ctx.biome_map)
        var mi := MeshInstance3D.new()
        mi.name = "BiomeDebug"
        var pm := PlaneMesh.new()
        pm.size = Vector2(float(params.get("terrain_size", 18000.0)), float(params.get("terrain_size", 18000.0)))
        mi.mesh = pm
        mi.position = Vector3(0.0, Game.sea_level + 0.25, 0.0)
        var m := StandardMaterial3D.new()
        m.albedo_texture = tex
        m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        m.albedo_color = Color(1, 1, 1, 0.45)
        mi.material_override = m
        mi.visible = true
        ctx.get_layer("Debug").add_child(mi)
