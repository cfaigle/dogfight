extends Node

# Particle system monitoring for GPU debugging
# Auto-updates to track active particle systems

var update_interval := 0.5  # Update every 0.5 seconds
var _timer := 0.0

var particle_counts := {
    "muzzle_flashes": 0,
    "impact_sparks": 0,
    "tracers": 0,
    "smoke": 0,
    "debris": 0,
    "bullet_hit_effects": 0,
    "total_particles": 0,
    "total_nodes": 0,
    "budget_exceeded_count": 0,  # Track budget violations
    "max_muzzle_flash_budget": 300,
    "max_impact_budget": 100,
    "total_budget": 8000
}

func _process(delta: float) -> void:
    _timer += delta
    if _timer >= update_interval:
        _timer = 0.0
        _update_counts()
        _print_stats()

func _update_counts() -> void:
    particle_counts.muzzle_flashes = get_tree().get_nodes_in_group("muzzle_flashes").size()
    particle_counts.impact_sparks = get_tree().get_nodes_in_group("impact_sparks").size()
    particle_counts.tracers = get_tree().get_nodes_in_group("tracers").size()
    particle_counts.bullet_hit_effects = get_tree().get_nodes_in_group("bullet_hit_effects").size()

    # Count total GPUParticles3D nodes
    var total_particles := 0
    var all_particles := []
    _find_particles(get_tree().root, all_particles)

    for p in all_particles:
        if p is GPUParticles3D and p.emitting:
            total_particles += p.amount

    particle_counts.total_particles = total_particles
    particle_counts.total_nodes = get_tree().get_node_count()

    # Load budgets from settings
    particle_counts.max_muzzle_flash_budget = Game.settings.get("max_active_muzzle_flashes", 300)
    particle_counts.max_impact_budget = Game.settings.get("max_active_impact_effects", 100)
    particle_counts.total_budget = Game.settings.get("max_total_particle_budget", 8000)

    # Check for budget violations
    if total_particles > particle_counts.total_budget:
        particle_counts.budget_exceeded_count += 1

func _find_particles(node: Node, result: Array) -> void:
    if node is GPUParticles3D:
        result.append(node)
    for child in node.get_children():
        _find_particles(child, result)

func _print_stats() -> void:
    var over_budget = particle_counts.total_particles > particle_counts.total_budget
    var warning = " ⚠️ OVER BUDGET!" if over_budget else ""

    print("=== GPU PARTICLE MONITOR ===")
    print("Muzzle flashes: ", particle_counts.muzzle_flashes, " / ", particle_counts.max_muzzle_flash_budget)
    print("Impact sparks: ", particle_counts.impact_sparks, " / ", particle_counts.max_impact_budget)
    print("Bullet hit effects: ", particle_counts.bullet_hit_effects)
    print("Tracers: ", particle_counts.tracers)
    print("Total active particles: ", particle_counts.total_particles, " / ", particle_counts.total_budget, warning)
    print("Budget violations: ", particle_counts.budget_exceeded_count)
    print("Total scene nodes: ", particle_counts.total_nodes)
    print("============================")

func get_counts() -> Dictionary:
    return particle_counts.duplicate()
