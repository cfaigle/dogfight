# AI Collaboration Notes - Modular World Builder

This repo now uses a **hard-switched** modular world generation pipeline built around `scripts/world/world_builder.gd`.

This document is for other AIs working on the project. It explains where to plug in new world-gen features, what conventions to follow, and what pitfalls to avoid so the game keeps compiling.

## Entry point

- `scripts/game/main.gd::_rebuild_world()` clears the old world nodes and calls:
  - `_world_builder.build_world(_world_root, world_seed, world_params)`
- The old monolithic helper functions still exist in `main.gd` for reference, but they are no longer called by default.

## Core architecture

- `scripts/world/world_builder.gd`
  - Creates/owns generator services (terrain, settlements, props, biomes, water bodies, zoning, roads)
  - Registers component scripts
  - Applies default params from components
  - Executes components in the default order

- `scripts/world/world_context.gd`
  - Shared mutable state used by components
  - Stores: terrain heightmap data, rivers, settlements, biome_map, lakes, roads, and layer roots

- `scripts/world/components/`
  - `world_component_base.gd` is the interface
  - Built-ins are in `components/builtin/`

## Default component pipeline

Order in `WorldBuilder._default_components`:

`heightmap -> lakes -> biomes -> ocean -> terrain_mesh -> runway -> rivers -> landmarks -> settlements -> zoning -> road_network -> farms -> decor -> forest`

This order matters because some components *modify inputs* for later ones (e.g. `lakes` carves into the heightmap before `terrain_mesh`).

## How to add or replace a component safely

1. Create a new script in `scripts/world/components/builtin/` (or elsewhere) that:
   - `extends WorldComponentBase`
   - Defines `generate(ctx, params, rng)`
   - Uses `ctx.get_layer("...")` to attach any nodes
   - Uses `get_optional_params()` to expose defaults

2. Register it in `WorldBuilder._register_default_components()`:

```gdscript
_component_registry.register_component("my_feature", preload("res://scripts/world/components/builtin/my_feature_component.gd"))
```

3. Add it to the default pipeline list in `WorldBuilder._default_components` in the position you want.

4. Keep compilation robust:
   - Prefer `has_method()` + `call()` when interacting with optional services.
   - Avoid strict type hints in shared state for custom classes (load-order issues can be painful).

## Conventions

- World layers:
  - All geometry should live under layers created by `ctx.get_layer()`:
    - `Terrain`, `Water`, `Infrastructure`, `Props`, `Debug`
  - Do not attach random nodes directly under `_world_root`.

- Performance:
  - Use `MultiMeshInstance3D` for repeated props (trees, houses, fields, crates, etc.).
  - Keep unique MeshInstance3Ds for low counts (e.g. 5–20 lakes).

- Terrain sampling:
  - `TerrainGenerator.get_height_at(x,z)` returns height in meters.
  - `TerrainGenerator.get_slope_at(x,z)` returns slope in **degrees**.
  - `TerrainGenerator.find_land_point(rng, min_height, max_slope_grad, prefer_coast)` expects the slope threshold as a **gradient**, not degrees.
    - Convert degrees to gradient using `tan(deg_to_rad(deg))`.

## Common pitfalls

- Calling a generator with the wrong signature (extra args). Use `has_method()` and keep `generate()` signatures consistent.
- Mixing degrees and slope gradients.
- Adding new required params without defaults (can break builds if main.gd does not set them).

## Quick sanity checklist

- In Godot, run `--import` and verify there are **no script parse errors**.
- Start a new game and ensure:
  - Terrain appears
  - Ocean renders
  - Settlements exist
  - Roads generate (if enabled)
  - No spammy runtime errors in the output log
