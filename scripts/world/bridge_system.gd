class_name BridgeSystem
extends RefCounted

## Advanced bridge system with four bridge types: short, medium, long, and spanning

var terrain_generator = null
var world_context = null

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen

func set_world_context(world_ctx) -> void:
    world_context = world_ctx

## Create appropriate bridge based on distance
func create_bridge(start_pos: Vector3, end_pos: Vector3, width: float, material: Material = null) -> MeshInstance3D:
    var distance: float = start_pos.distance_to(end_pos)
    
    if distance <= 100.0:
        return create_short_bridge(start_pos, end_pos, width, material)
    elif distance <= 300.0:
        return create_medium_bridge(start_pos, end_pos, width, material)
    elif distance <= 800.0:
        return create_long_bridge(start_pos, end_pos, width, material)
    else:
        return create_spanning_bridge(start_pos, end_pos, width, material)

## Create short bridge (up to 100m) - Simple beam bridge
func create_short_bridge(start_pos: Vector3, end_pos: Vector3, width: float, material: Material = null) -> MeshInstance3D:
    var bridge_mesh: MeshInstance3D = _create_basic_beam_bridge(start_pos, end_pos, width, 8.0, material)
    _add_simple_pillars(bridge_mesh, start_pos, end_pos, width, 8.0)
    return bridge_mesh

## Create medium bridge (100-300m) - Arch bridge with central support
func create_medium_bridge(start_pos: Vector3, end_pos: Vector3, width: float, material: Material = null) -> MeshInstance3D:
    var bridge_mesh: MeshInstance3D = _create_arch_bridge(start_pos, end_pos, width, 12.0, material)
    _add_arch_support_pillars(bridge_mesh, start_pos, end_pos, width, 12.0)
    return bridge_mesh

## Create long bridge (300-800m) - Suspension bridge with towers
func create_long_bridge(start_pos: Vector3, end_pos: Vector3, width: float, material: Material = null) -> MeshInstance3D:
    var bridge_mesh: MeshInstance3D = _create_suspension_bridge(start_pos, end_pos, width, 15.0, material)
    _add_suspension_towers(bridge_mesh, start_pos, end_pos, width, 15.0)
    return bridge_mesh

## Create spanning bridge (800m+) - Cable-stayed bridge with multiple towers
func create_spanning_bridge(start_pos: Vector3, end_pos: Vector3, width: float, material: Material = null) -> MeshInstance3D:
    var bridge_mesh: MeshInstance3D = _create_cable_stayed_bridge(start_pos, end_pos, width, 20.0, material)
    _add_cable_stayed_towers(bridge_mesh, start_pos, end_pos, width, 20.0)
    return bridge_mesh

## Basic beam bridge implementation
func _create_basic_beam_bridge(start_pos: Vector3, end_pos: Vector3, width: float, clearance: float, material: Material) -> MeshInstance3D:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    # Calculate direction and perpendicular vectors
    var direction: Vector3 = (end_pos - start_pos).normalized()
    var right: Vector3 = direction.cross(Vector3.UP).normalized() * width * 0.5
    
    # Calculate water level to determine deck height
    var water_level: float = _get_water_level_at(start_pos, end_pos)
    var deck_height: float = water_level + clearance
    
    # Create bridge deck
    var start_deck_left: Vector3 = Vector3(start_pos.x, deck_height, start_pos.z) - right
    var start_deck_right: Vector3 = Vector3(start_pos.x, deck_height, start_pos.z) + right
    var end_deck_left: Vector3 = Vector3(end_pos.x, deck_height, end_pos.z) - right
    var end_deck_right: Vector3 = Vector3(end_pos.x, deck_height, end_pos.z) + right
    
    # Add deck surface
    st.set_normal(Vector3.UP)
    st.add_vertex(start_deck_left)
    st.add_vertex(end_deck_right)
    st.add_vertex(start_deck_right)
    
    st.set_normal(Vector3.UP)
    st.add_vertex(start_deck_left)
    st.add_vertex(end_deck_left)
    st.add_vertex(end_deck_right)
    
    # Add simple railings
    var rail_height: float = 1.2
    var start_rail_left_top: Vector3 = start_deck_left + Vector3.UP * rail_height
    var start_rail_right_top: Vector3 = start_deck_right + Vector3.UP * rail_height
    var end_rail_left_top: Vector3 = end_deck_left + Vector3.UP * rail_height
    var end_rail_right_top: Vector3 = end_deck_right + Vector3.UP * rail_height
    
    # Left railing
    var left_normal: Vector3 = -right.normalized()
    st.set_normal(left_normal)
    st.add_vertex(start_deck_left)
    st.add_vertex(start_rail_left_top)
    st.add_vertex(end_rail_left_top)
    
    st.set_normal(left_normal)
    st.add_vertex(start_deck_left)
    st.add_vertex(end_rail_left_top)
    st.add_vertex(end_deck_left)
    
    # Right railing
    var right_normal: Vector3 = right.normalized()
    st.set_normal(right_normal)
    st.add_vertex(start_deck_right)
    st.add_vertex(end_rail_right_top)
    st.add_vertex(start_rail_right_top)
    
    st.set_normal(right_normal)
    st.add_vertex(start_deck_right)
    st.add_vertex(end_deck_right)
    st.add_vertex(end_rail_right_top)
    
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = st.commit()
    if material != null:
        mesh_instance.material_override = material
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    
    return mesh_instance

## Arch bridge implementation
func _create_arch_bridge(start_pos: Vector3, end_pos: Vector3, width: float, clearance: float, material: Material) -> MeshInstance3D:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    # Calculate direction and perpendicular vectors
    var direction: Vector3 = (end_pos - start_pos).normalized()
    var right: Vector3 = direction.cross(Vector3.UP).normalized() * width * 0.5
    
    # Calculate water level to determine deck height
    var water_level: float = _get_water_level_at(start_pos, end_pos)
    var deck_height: float = water_level + clearance
    var arch_height: float = clearance * 0.7  # Arch height is 70% of clearance
    
    # Calculate center point for arch
    var center_pos: Vector3 = start_pos.lerp(end_pos, 0.5)
    var center_deck: Vector3 = Vector3(center_pos.x, deck_height + arch_height, center_pos.z)
    
    # Create bridge deck with arch support
    var start_deck_left: Vector3 = Vector3(start_pos.x, deck_height, start_pos.z) - right
    var start_deck_right: Vector3 = Vector3(start_pos.x, deck_height, start_pos.z) + right
    var end_deck_left: Vector3 = Vector3(end_pos.x, deck_height, end_pos.z) - right
    var end_deck_right: Vector3 = Vector3(end_pos.x, deck_height, end_pos.z) + right
    
    # Create deck segments
    var segments: int = 10
    for i in range(segments):
        var t0: float = float(i) / float(segments)
        var t1: float = float(i + 1) / float(segments)
        
        var pos0: Vector3 = start_pos.lerp(end_pos, t0)
        var pos1: Vector3 = start_pos.lerp(end_pos, t1)
        
        # Calculate arch height at this point (parabolic arch)
        var arch_factor: float = 4.0 * t0 * (1.0 - t0)  # Parabolic curve
        var deck_y0: float = deck_height + arch_factor * arch_height
        var deck_y1: float = deck_height + 4.0 * t1 * (1.0 - t1) * arch_height
        
        var deck_left0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) - right
        var deck_right0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) + right
        var deck_left1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) - right
        var deck_right1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) + right
        
        # Add deck surface
        st.set_normal(Vector3.UP)
        st.add_vertex(deck_left0)
        st.add_vertex(deck_right1)
        st.add_vertex(deck_right0)
        
        st.set_normal(Vector3.UP)
        st.add_vertex(deck_left0)
        st.add_vertex(deck_left1)
        st.add_vertex(deck_right1)
    
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = st.commit()
    if material != null:
        mesh_instance.material_override = material
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    
    return mesh_instance

## Suspension bridge implementation
func _create_suspension_bridge(start_pos: Vector3, end_pos: Vector3, width: float, clearance: float, material: Material) -> MeshInstance3D:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    # Calculate direction and perpendicular vectors
    var direction: Vector3 = (end_pos - start_pos).normalized()
    var right: Vector3 = direction.cross(Vector3.UP).normalized() * width * 0.5
    
    # Calculate water level to determine deck height
    var water_level: float = _get_water_level_at(start_pos, end_pos)
    var deck_height: float = water_level + clearance
    
    # Create main bridge deck
    var start_deck_left: Vector3 = Vector3(start_pos.x, deck_height, start_pos.z) - right
    var start_deck_right: Vector3 = Vector3(start_pos.x, deck_height, start_pos.z) + right
    var end_deck_left: Vector3 = Vector3(end_pos.x, deck_height, end_pos.z) - right
    var end_deck_right: Vector3 = Vector3(end_pos.x, deck_height, end_pos.z) + right
    
    # Create deck segments with cable support effect
    var segments: int = 20
    for i in range(segments):
        var t0: float = float(i) / float(segments)
        var t1: float = float(i + 1) / float(segments)
        
        var pos0: Vector3 = start_pos.lerp(end_pos, t0)
        var pos1: Vector3 = start_pos.lerp(end_pos, t1)
        
        # Slight sag in the middle for suspension effect
        var sag_factor: float = 0.2
        var sag0: float = -sag_factor * 4.0 * t0 * (1.0 - t0)  # Parabolic sag
        var sag1: float = -sag_factor * 4.0 * t1 * (1.0 - t1)  # Parabolic sag
        
        var deck_y0: float = deck_height + sag0
        var deck_y1: float = deck_height + sag1
        
        var deck_left0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) - right
        var deck_right0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) + right
        var deck_left1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) - right
        var deck_right1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) + right
        
        # Add deck surface
        st.set_normal(Vector3.UP)
        st.add_vertex(deck_left0)
        st.add_vertex(deck_right1)
        st.add_vertex(deck_right0)
        
        st.set_normal(Vector3.UP)
        st.add_vertex(deck_left0)
        st.add_vertex(deck_left1)
        st.add_vertex(deck_right1)
    
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = st.commit()
    if material != null:
        mesh_instance.material_override = material
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    
    return mesh_instance

## Cable-stayed bridge implementation
func _create_cable_stayed_bridge(start_pos: Vector3, end_pos: Vector3, width: float, clearance: float, material: Material) -> MeshInstance3D:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    # Calculate direction and perpendicular vectors
    var direction: Vector3 = (end_pos - start_pos).normalized()
    var right: Vector3 = direction.cross(Vector3.UP).normalized() * width * 0.5
    
    # Calculate water level to determine deck height
    var water_level: float = _get_water_level_at(start_pos, end_pos)
    var deck_height: float = water_level + clearance
    var tower_height: float = clearance * 1.5  # Towers are 1.5x the clearance
    
    # Create main bridge deck
    var start_deck_left: Vector3 = Vector3(start_pos.x, deck_height, start_pos.z) - right
    var start_deck_right: Vector3 = Vector3(start_pos.x, deck_height, start_pos.z) + right
    var end_deck_left: Vector3 = Vector3(end_pos.x, deck_height, end_pos.z) - right
    var end_deck_right: Vector3 = Vector3(end_pos.x, deck_height, end_pos.z) + right
    
    # Create deck segments
    var segments: int = 30
    for i in range(segments):
        var t0: float = float(i) / float(segments)
        var t1: float = float(i + 1) / float(segments)
        
        var pos0: Vector3 = start_pos.lerp(end_pos, t0)
        var pos1: Vector3 = start_pos.lerp(end_pos, t1)
        
        var deck_y0: float = deck_height
        var deck_y1: float = deck_height
        
        var deck_left0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) - right
        var deck_right0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) + right
        var deck_left1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) - right
        var deck_right1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) + right
        
        # Add deck surface
        st.set_normal(Vector3.UP)
        st.add_vertex(deck_left0)
        st.add_vertex(deck_right1)
        st.add_vertex(deck_right0)
        
        st.set_normal(Vector3.UP)
        st.add_vertex(deck_left0)
        st.add_vertex(deck_left1)
        st.add_vertex(deck_right1)
    
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = st.commit()
    if material != null:
        mesh_instance.material_override = material
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    
    return mesh_instance

## Add simple pillars for short bridges
func _add_simple_pillars(bridge_parent: MeshInstance3D, start_pos: Vector3, end_pos: Vector3, width: float, clearance: float) -> void:
    var water_level: float = _get_water_level_at(start_pos, end_pos)
    var deck_height: float = water_level + clearance
    
    # Add pillars at start and end
    _add_pillar(bridge_parent, start_pos.x, start_pos.z, water_level, deck_height, width * 0.1, bridge_parent.material_override)
    _add_pillar(bridge_parent, end_pos.x, end_pos.z, water_level, deck_height, width * 0.1, bridge_parent.material_override)

## Add arch support pillars for medium bridges
func _add_arch_support_pillars(bridge_parent: MeshInstance3D, start_pos: Vector3, end_pos: Vector3, width: float, clearance: float) -> void:
    var water_level: float = _get_water_level_at(start_pos, end_pos)
    var deck_height: float = water_level + clearance
    
    # Add pillars at start, center, and end
    _add_pillar(bridge_parent, start_pos.x, start_pos.z, water_level, deck_height, width * 0.15, bridge_parent.material_override)
    _add_pillar(bridge_parent, end_pos.x, end_pos.z, water_level, deck_height, width * 0.15, bridge_parent.material_override)

    # Add central support pillar
    var center_pos: Vector3 = start_pos.lerp(end_pos, 0.5)
    _add_pillar(bridge_parent, center_pos.x, center_pos.z, water_level, deck_height + clearance * 0.7, width * 0.2, bridge_parent.material_override)

## Add suspension towers for long bridges
func _add_suspension_towers(bridge_parent: MeshInstance3D, start_pos: Vector3, end_pos: Vector3, width: float, clearance: float) -> void:
    var water_level: float = _get_water_level_at(start_pos, end_pos)
    var deck_height: float = water_level + clearance
    var tower_height: float = clearance * 1.2
    
    # Add towers at start and end
    _add_tower(bridge_parent, start_pos.x, start_pos.z, deck_height, deck_height + tower_height, width * 0.3, bridge_parent.material_override)
    _add_tower(bridge_parent, end_pos.x, end_pos.z, deck_height, deck_height + tower_height, width * 0.3, bridge_parent.material_override)

## Add cable-stayed towers for spanning bridges
func _add_cable_stayed_towers(bridge_parent: MeshInstance3D, start_pos: Vector3, end_pos: Vector3, width: float, clearance: float) -> void:
    var water_level: float = _get_water_level_at(start_pos, end_pos)
    var deck_height: float = water_level + clearance
    var tower_height: float = clearance * 1.5
    
    # Add towers at start, end, and intermediate positions
    _add_tower(bridge_parent, start_pos.x, start_pos.z, deck_height, deck_height + tower_height, width * 0.25, bridge_parent.material_override)
    _add_tower(bridge_parent, end_pos.x, end_pos.z, deck_height, deck_height + tower_height, width * 0.25, bridge_parent.material_override)

    # Add intermediate towers based on distance
    var distance: float = start_pos.distance_to(end_pos)
    var num_intermediate: int = max(1, int(distance / 400.0))  # One tower every 400m

    for i in range(1, num_intermediate + 1):
        var t: float = float(i) / float(num_intermediate + 1)
        var pos: Vector3 = start_pos.lerp(end_pos, t)
        _add_tower(bridge_parent, pos.x, pos.z, deck_height, deck_height + tower_height * 0.8, width * 0.2, bridge_parent.material_override)

## Add a single pillar
func _add_pillar(parent: MeshInstance3D, x: float, z: float, bottom_y: float, top_y: float, width: float, material: Material = null) -> void:
    if terrain_generator == null:
        return
    
    var height: float = top_y - bottom_y
    if height <= 0.0:
        return
    
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var hw: float = width * 0.5
    var hd: float = width * 0.5

    # Create a simple rectangular pillar
    var base_corners: Array[Vector3] = [
        Vector3(x - hw, bottom_y, z - hd),  # 0: back-left
        Vector3(x + hw, bottom_y, z - hd),  # 1: back-right
        Vector3(x + hw, bottom_y, z + hd),  # 2: front-right
        Vector3(x - hw, bottom_y, z + hd),  # 3: front-left
    ]

    var top_corners: Array[Vector3] = [
        Vector3(x - hw, top_y, z - hd),  # 4: back-left
        Vector3(x + hw, top_y, z - hd),  # 5: back-right
        Vector3(x + hw, top_y, z + hd),  # 6: front-right
        Vector3(x - hw, top_y, z + hd),  # 7: front-left
    ]

    # Create 4 side faces
    var face_normals: Array[Vector3] = [
        Vector3(0, 0, -1),  # Back face
        Vector3(1, 0, 0),   # Right face
        Vector3(0, 0, 1),   # Front face
        Vector3(-1, 0, 0),  # Left face
    ]

    for side in range(4):
        var next_side: int = (side + 1) % 4
        var b0: Vector3 = base_corners[side]
        var b1: Vector3 = base_corners[next_side]
        var t0: Vector3 = top_corners[side]
        var t1: Vector3 = top_corners[next_side]
        var normal: Vector3 = face_normals[side]

        # Two triangles per face
        st.set_normal(normal)
        st.add_vertex(b0)
        st.set_normal(normal)
        st.add_vertex(t1)
        st.set_normal(normal)
        st.add_vertex(t0)

        st.set_normal(normal)
        st.add_vertex(b0)
        st.set_normal(normal)
        st.add_vertex(b1)
        st.set_normal(normal)
        st.add_vertex(t1)

    # Top cap
    st.set_normal(Vector3.UP)
    st.add_vertex(top_corners[0])
    st.set_normal(Vector3.UP)
    st.add_vertex(top_corners[2])
    st.set_normal(Vector3.UP)
    st.add_vertex(top_corners[1])

    st.set_normal(Vector3.UP)
    st.add_vertex(top_corners[0])
    st.set_normal(Vector3.UP)
    st.add_vertex(top_corners[3])
    st.set_normal(Vector3.UP)
    st.add_vertex(top_corners[2])

    var pillar_mesh := MeshInstance3D.new()
    pillar_mesh.mesh = st.commit()
    if material != null:
        pillar_mesh.material_override = material
    pillar_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    
    parent.add_child(pillar_mesh)

## Add a single tower
func _add_tower(parent: MeshInstance3D, x: float, z: float, bottom_y: float, top_y: float, width: float, material: Material = null) -> void:
    # For now, create a taller, thinner pillar as a tower
    _add_pillar(parent, x, z, bottom_y, top_y, width * 0.5, material)

## Get water level between two points (minimum of both)
func _get_water_level_at(pos1: Vector3, pos2: Vector3) -> float:
    if terrain_generator == null:
        return 20.0  # Default sea level

    var h1: float = terrain_generator.get_height_at(pos1.x, pos1.z)
    var h2: float = terrain_generator.get_height_at(pos2.x, pos2.z)

    # Check if either point is below sea level (water)
    var sea_level: float = 20.0
    if world_context and world_context.has_method("get_sea_level"):
        sea_level = float(world_context.get_sea_level())
    elif world_context and world_context.has_method("get"):
        var sea_level_val = world_context.get("sea_level")
        if sea_level_val != null:
            sea_level = float(sea_level_val)

    # Only consider as water crossing if the terrain is significantly below sea level
    # and likely represents an actual water body
    var water_threshold: float = 0.5
    var is_pos1_water: bool = (h1 < sea_level - water_threshold) and _is_point_over_water(pos1, h1, sea_level)
    var is_pos2_water: bool = (h2 < sea_level - water_threshold) and _is_point_over_water(pos2, h2, sea_level)

    if is_pos1_water or is_pos2_water:
        return sea_level

    # Return the lower of the two terrain heights as the water level
    return min(h1, h2)

## Check if a point is over actual water
func _is_point_over_water(point: Vector3, terrain_height: float, sea_level: float) -> bool:
    if terrain_generator == null:
        return false

    # Check if nearby terrain heights are also near sea level (indicating a continuous water body)
    var sample_distance: float = 10.0  # Distance to sample around the point
    var sample_points: int = 8  # Number of points to sample around
    var water_threshold: float = 0.5  # How close to sea level indicates water

    var water_samples: int = 0
    var total_samples: int = 0

    for i in range(sample_points):
        var angle: float = (TAU * i) / sample_points
        var sample_x: float = point.x + cos(angle) * sample_distance
        var sample_z: float = point.z + sin(angle) * sample_distance

        var sample_height: float = terrain_generator.get_height_at(sample_x, sample_z)

        # If sample is close to sea level, consider it water
        if abs(sample_height - sea_level) <= water_threshold:
            water_samples += 1
        total_samples += 1

    # If most samples around the point are at water level, it's likely a water body
    var water_ratio: float = float(water_samples) / float(total_samples)
    return water_ratio >= 0.6  # At least 60% of samples must be water level