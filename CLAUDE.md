# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dogfight: 1940 is a 3D arcade dogfighting game built with **Godot 4.5.x** and **GDScript**. All visuals are procedurally generated—no external 3D models required. The game features wave-based combat with guns, homing missiles, and AI enemies.

## Development Commands

**Run the game:**
- Press F5 in Godot editor, or run `godot --play` from CLI

**Export builds:**
- Use Godot's export dialog (Project > Export)

**Optional asset fetching:**
```bash
python3 tools/fetch_assets.py
```

There is no unit test framework configured—testing is done via manual playtesting.

Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs
Always use spaces never tabs

## Architecture

### Autoload Singletons (defined in project.godot)
- **Game** (`scripts/game/game.gd`): Global settings dictionary, camera reference, pause state, player reference
- **GameEvents** (`scripts/game/game_events.gd`): Decoupled signal hub for cross-system communication (score, wave, player health, enemy spawning)

### Core Systems

| System | File | Purpose |
|--------|------|---------|
| Main Loop | `scripts/game/main.gd` | World generation, wave spawning, LOD updates |
| Flight Physics | `scripts/actors/plane/plane.gd` | Hybrid arcade/realistic aerodynamic simulation (~700 lines) |
| Enemy AI | `scripts/actors/plane/enemy_plane.gd` | Lead pursuit, evasive maneuvers, throttle management |
| Weapons | `scripts/actors/weapons/gun.gd`, `missile.gd` | Hitscan guns with tracers, homing missiles with lock-on |
| HUD | `scripts/ui/hud.gd` | Procedurally-built UI (speed, altitude, targeting, radar) |

### Data-Driven Tuning
All gameplay parameters live in `.tres` resource files:
- `resources/defs/plane_defs.tres`: Player/enemy stats (speed, thrust, drag, lift, hp, color)
- `resources/defs/weapon_defs.tres`: Gun/missile stats (damage, cooldown, range, lock-on)

Access via: `plane_defs.player` / `plane_defs.enemy` dicts in GDScript.

### Flight Physics Model
The flight model (`plane.gd`) uses:
- Alpha/beta angles computed from velocity relative to aircraft orientation
- Lift/drag coefficients with stall clamp (CL_max = 1.35)
- PD controller on attitude rates for control moments
- Dynamic pressure scaling for speed-dependent control effectiveness

### Component Pattern
- **Health** (`scripts/components/health.gd`): Reusable damage/death component
- **AutoDestruct** (`scripts/components/auto_destruct.gd`): Cleanup on death

## Game Settings

100+ configurable parameters in `Game.gd`, persisted to `user://dogfight_settings.cfg`:
- Flight physics: `speed_scale`, `turn_scale`, `stall_deg`, `aoa_lift_slope`
- Camera: `camera_distance`, `camera_height`, `camera_lag`, `fov_base`
- World gen: `terrain_size`, `terrain_amp`, `tree_count`, `town_count`
- Difficulty: `difficulty` (0.6..1.6 multiplier on enemy AI)

## In-Game Debug Keys

- **F2/F3**: Regenerate world
- **F4**: Toggle peaceful mode (no enemies)
- **ESC**: Pause

## Engine Configuration

- Physics engine: Jolt Physics
- Resolution: 1280x720 (windowed)
- Rendering: MSAA 2x + FXAA
