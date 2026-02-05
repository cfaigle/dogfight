# Particle Effects Table for Dogfight: 1940

| Effect Type | Generated From | Quantity Per Event | Lifetime | Emission Rate | Cleanup Method | Cleanup Delay | Notes |
|-------------|----------------|-------------------|----------|---------------|----------------|---------------|-------|
| Muzzle Flash | Gun firing | 8 particles | 0.3s | Per shot (2 guns per plane) | Timer: lifetime * 1.2 (0.36s) | 0.36s after emission | Added to "muzzle_flashes" group, subject to 300 max budget |
| Missile Trail | Missile active | 120 particles | 0.55s | Continuous while missile alive | When missile destroyed | Immediate when missile freed | Continuous emission, not one-shot |
| Impact Spark | Bullet hit | 50 particles | 1.0s | Per impact | Timer: lifetime + 0.5 (1.5s) | 1.5s after emission | Added to "impact_sparks" group, subject to 100 max budget |
| Explosion | Missile hit | 100-155 particles | 0.85s (based on intensity) | One-shot per explosion | Auto-destruct script | After lifetime (1.0s default) | Amount varies with intensity |
| Bullet Hit Effects | Various materials | Varies | 0.95-3.0s | Per impact | Timer: lifetime + 0.5s | After lifetime + 0.5s | Different scenes for metal/wood/stone/natural |
| Smoke Trail | Bullet hit (terrain) | 30 particles | 1.5s | Per impact | Timer: 2.5s | 2.5s after emission | Subject to "enable_smoke_trails" setting |
| Building Fire | Building damage | 30 particles | 1.5s | Per damage event | Timer: lifetime + 0.5s | After lifetime + 0.5s | Different amounts for different building types |
| Building Smoke | Building damage | 50 particles | 3.0s (reduced to 0.8s in some cases) | Per damage event | Timer: lifetime + 0.5s | After lifetime + 0.5s | Different amounts for different building types |
| Building Explosion | Building destroyed | 10 particles | 0.5s | Per destruction | Timer: lifetime + 0.5s | After lifetime + 0.5s | Small explosion burst |
| Tree Destruction | Tree hit | 8-10 particles | 0.6-0.8s | Per tree destruction | Timer: lifetime + 0.5s | After lifetime + 0.5s | Different effects for fire/smoke |
| Boat Effects | Boat damage/destruction | Varies | Varies | Per damage/destruction | Timer: lifetime + 0.5s | After lifetime + 0.5s | Multiple effects: fire, smoke, splash, explosion |
| Dust Particles | Ground impact | 100 particles total (2 sets of 50) | 0.3s each set | Per ground impact | Timer: lifetime + 0.5s | After lifetime + 0.5s | Two separate particle systems |
| Wood Debris | Wood impact | 30 particles | 1.0s | Per wood impact | Timer: lifetime + 0.5s | After lifetime + 0.5s | For wooden structures |
| Sparks | Metal impact | 100 particles | 1.2s | Per metal impact | Timer: lifetime + 0.5s | After lifetime + 0.5s | For metal surfaces |
| Leaves | Natural impact | 30 particles | 1.0s | Per natural surface impact | Timer: lifetime + 0.5s | After lifetime + 0.5s | For trees and vegetation |
| Bark Debris | Tree impact | 30 particles | 0.6s | Per tree impact | Timer: lifetime + 0.5s | After lifetime + 0.5s | For tree impacts |

## Key Observations:

1. **Missile Trail Particles** are the most concerning as they continuously emit 120 particles with a 0.55s lifetime while the missile is active. If missiles get stuck or don't properly despawn, these could accumulate indefinitely.

2. **Muzzle Flash Particles** are limited by the budget system to 300 active at any time, which helps prevent accumulation.

3. **Impact Spark Particles** are also limited by budget to 100 active at any time.

4. Most particles use a cleanup delay of either their lifetime or lifetime + 0.5 seconds to ensure they finish their animation before being removed.

5. Many particle effects have been optimized from their original values to reduce GPU load (e.g., muzzle flash particles reduced from 80 to 8 particles per shot).