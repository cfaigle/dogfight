class_name ZoningGenerator
extends RefCounted

## Annotates settlements with zoning / districts.
##
## Output: each settlement dict gets a `zones` dictionary.

func generate(ctx: WorldContext, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx.settlements.is_empty():
        return

    for s in ctx.settlements:
        var sd: Dictionary = s as Dictionary
        var center: Vector3 = sd.get("center", Vector3.ZERO)
        var radius: float = float(sd.get("radius", 1200.0))
        var typ: String = String(sd.get("type", "town"))
        if center == Vector3.ZERO:
            continue

        var core: float = radius * (0.35 if typ == "city" else 0.25)
        var suburb: float = radius * (0.85 if typ == "city" else 0.70)

        # Simple directional industry lobe
        var ang: float = rng.randf_range(0.0, TAU)
        var ind_dir: Vector3 = Vector3(cos(ang), 0.0, sin(ang))
        var ind_center: Vector3 = center + ind_dir * (radius * rng.randf_range(0.55, 0.90))
        ind_center.y = center.y

        sd["zones"] = {
            "core_radius": core,
            "suburb_radius": suburb,
            "industry_center": ind_center,
            "industry_radius": radius * 0.35,
        }
