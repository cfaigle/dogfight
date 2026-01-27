# AI Handoff: Modular World Builder (Hard-Switch)

This project is now **hard-switched** to the new modular world system.

## What’s already done (Step A + Step B)

### Step A — Hard switch to WorldBuilder
- `scripts/game/main.gd` no longer calls the legacy monolithic world generation.
- World generation is routed through:
  - `scripts/world/world_builder.gd` (orchestrator)
  - `scripts/world/world_context.gd` (shared state + layers)
  - `scripts/world/components/builtin/*` (replaceable generation stages)

### Step B — Replaceable component pipeline
The default pipeline is script-based and replaceable:

`heightmap → lakes → biomes → ocean → terrain_mesh → runway → rivers → landmarks → settlements → zoning → road_network → farms → decor → forest`

Each stage is a **component** (a script extending `WorldComponentBase`) registered in `WorldBuilder._register_default_components()`.

## Key files

- **Orchestrator**: `scripts/world/world_builder.gd`
- **Shared state + layers**: `scripts/world/world_context.gd`
- **Component base**: `scripts/world/components/world_component_base.gd`
- **Built-in components**: `scripts/world/components/builtin/*.gd`
- **Reusable generators/services**:
  - `scripts/world/generators/terrain_generator.gd`
  - `scripts/world/generators/settlement_generator.gd`
  - `scripts/world/generators/prop_generator.gd`
  - `scripts/world/generators/biome_generator.gd` (**now includes `classify()` + `generate_biome_map()`**)
  - `scripts/world/generators/water_bodies_generator.gd`
  - `scripts/world/generators/road_network_generator.gd`
  - `scripts/world/generators/zoning_generator.gd`
- **Road A* module**: `scripts/world/modules/road_module.gd`

## WorldContext conventions

`WorldContext` creates/owns named layers under the world root (e.g. `Terrain`, `Water`, `Infrastructure`, `Props`).

Components should:
- Use `ctx.get_layer("Props")` / `ctx.get_layer("Infrastructure")` etc.
- Store outputs back onto `ctx` if later stages depend on them:
  - `ctx.hmap`, `ctx.lakes`, `ctx.roads`, `ctx.settlements`, `ctx.biome_map`, etc.

## Biomes: contract used across components

`BiomeGenerator` provides two access patterns:
- **Fast query**: `get_biome_at(x,z) -> int` (enum)
- **Compatibility**: `classify(x,z) -> String` ("Ocean", "Beach", "Forest", …)

Some components/generators use `classify()` (trees, decor, farms). This is now implemented.

`BiomesComponent` calls:
- `BiomeGenerator.generate_biome_map(ctx, params) -> Image`

…then stores it on `ctx.biome_map` for debug/overlay use.

## Avoiding “Warnings treated as errors” (important)

This project has been run in environments where **GDScript warnings can be treated as build errors**.

Rule of thumb:
- Avoid `:=` when the RHS is a Variant-ish value (e.g. `dict.get(...)`, `node.get(...)`, `call(...)`).
  - Use `var x = dict.get("k", 0)` **instead of** `var x := dict.get("k", 0)`
  - Or explicitly type it: `var x: int = int(dict.get("k", 0))`

This reduces the chance of:
> “The variable type is being inferred from a Variant value … (Warning treated as error.)”

## Adding a new generation component

1) Create a script:
- `extends WorldComponentBase`
- Implement `get_optional_params()` and `generate()`.

2) Register it in `WorldBuilder._register_default_components()`:

```gdscript
_component_registry.register_component("my_feature", preload("res://scripts/world/components/builtin/my_feature_component.gd"))
_default_components.append("my_feature")
```

3) Prefer using `ctx` outputs instead of recomputing.

## Recommended next upgrades (good targets for the next AI)

1) **Roads become “smart”**
- Add highway vs. local road classes
- Add bridge meshes over water crossings
- Generate intersections + road-aligned plots

2) **Settlements become structured**
- Use zoning hints to place suburbs/industry blocks
- Add “main street” and blocks around it

3) **Terrain detail & textures**
- Add cliff/rock meshes driven by slope
- Add beach/shoreline foam decals
- Hook in external textures (manifest-based) via `scripts/util/asset_library.gd`

4) **Performance**
- Keep using MultiMesh where possible
- Prefer chunked generation and LOD toggles

