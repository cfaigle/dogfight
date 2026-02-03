# Dogfight: 1940 (Godot 4.6)

A self-contained arcade 3D dogfight game:
- Procedural fighter meshes (no external assets)
- Guns (hitscan + tracers + muzzle flashes + hit markers)
- Homing missiles (lock + smoke trail + satisfying pops)
- Enemy AI (lead pursuit + evasive rolls)
- Waves + score + HUD (target brackets, lock ring, lead pip, debug)

## Requirements
- Godot **4.5.1 stable** (or newer in the 4.5 line).

## How to run
1. Import this folder as a Godot project.
2. Press **Play** (F5).

## Controls
- **Pitch**: W / S
- **Roll**: A / D
- **Yaw**: Q / E
- **Throttle**: R / F (incremental)
- **Afterburner**: Shift
- **Guns**: Left Mouse (or Space)
- **Missile**: Right Mouse (or Ctrl)
- **Hold lock**: Alt (build lock if target is in cone)
- **Next target**: Tab
- **Pause**: Esc
- **Regenerate world (new seed)**: F2
- **Regenerate world (same seed)**: F3
- **Toggle Peaceful Mode (no enemies)**: F4

## Extending it
Data-driven tuning lives in `res://resources/defs/`:
- `plane_defs.tres` (player/enemy stats + colors)
- `weapon_defs.tres` (gun + missile stats)

Architecture:
- `Plane` base class + `PlayerPlane` / `EnemyPlane`
- Separate weapon components (`Gun`, `MissileLauncher`, `Missile`)
- `GameEvents` autoload for decoupled signals
