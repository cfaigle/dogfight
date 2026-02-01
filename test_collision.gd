extends Node

# Test script to investigate collision issues
func _ready():
    print("=== COLLISION INVESTIGATION ===")
    
    # Check if singletons are available
    print("CollisionManager available: ", Engine.has_singleton("CollisionManager"))
    print("CollisionAdder available: ", Engine.has_singleton("CollisionAdder"))
    
    if Engine.has_singleton("CollisionManager"):
        var cm = Engine.get_singleton("CollisionManager")
        print("CollisionManager enabled: ", cm.collision_config.enabled)
        print("CollisionManager active collisions: ", cm.get_active_collision_count())
        
        # Check collision config
        var config = cm.get_config()
        print("Collision config: ", config)
    
    # Test raycast manually
    var space_state = get_world_3d().direct_space_state
    if space_state:
        var query = PhysicsRayQueryParameters3D.create(
            Vector3(0, 10, 0),
            Vector3(0, -10, 0)
        )
        query.collision_mask = 1
        query.collide_with_areas = true
        query.collide_with_bodies = true
        
        var result = space_state.intersect_ray(query)
        print("Manual raycast result: ", result)
    
    # Check what's in the scene tree
    _inspect_scene_tree(get_tree().root, 0)
    
    print("=== END INVESTIGATION ===")

func _inspect_scene_tree(node: Node, depth: int):
    if depth > 3:  # Limit depth to avoid spam
        return
        
    var indent = "  ".repeat(depth)
    var node_name = node.name
    var node_type = node.get_class()
    
    # Look for collision bodies
    if node is StaticBody3D:
        print(indent, "🎯 COLLISION BODY: ", node_name, " (", node_type, ")")
        print(indent, "    Layer: ", node.collision_layer, " Mask: ", node.collision_mask)
        if node.get_parent():
            print(indent, "    Parent: ", node.get_parent().name)
    
    # Look for mesh instances
    elif node is MeshInstance3D:
        print(indent, "🔷 MESH: ", node_name, " (", node_type, ")")
        if node.mesh:
            print(indent, "    Has mesh: ", node.mesh.get_class())
    
    # Look for multi-mesh instances
    elif node is MultiMeshInstance3D:
        print(indent, "🌲 MULTIMESH: ", node_name, " (", node_type, ")")
        var mm = node.multimesh
        if mm:
            print(indent, "    Instance count: ", mm.instance_count)
            if mm.mesh:
                print(indent, "    Mesh: ", mm.mesh.get_class())
    
    # Check children
    for child in node.get_children():
        _inspect_scene_tree(child, depth + 1)
