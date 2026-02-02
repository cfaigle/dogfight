## Script to add collision and damage capabilities to existing trees and buildings
## This will work with the MultiMesh-based trees that are already generated

extends Node

## Add collision shapes to MultiMesh-based trees
static func add_collision_to_multimesh_trees(multimesh_instance: MultiMeshInstance3D, tree_type: String = "tree") -> void:
    if not multimesh_instance:
        return

    # Get the multimesh to access instance transforms
    var mm = multimesh_instance.multimesh
    if not mm:
        return

    # Create collision bodies for each tree instance
    for i in range(min(mm.instance_count, 100)):  # Limit to first 100 for performance
        var transform = mm.get_instance_transform(i)

        # Create a StaticBody3D for collision
        var collision_body = StaticBody3D.new()
        collision_body.name = "TreeCollision_%d" % i

        # Set collision layers to ensure raycasts can detect this object
        collision_body.collision_layer = 1
        collision_body.collision_mask = 1  # Match the layer

        # Set position to match the tree instance
        collision_body.global_transform = transform

        # Create collision shape appropriate for tree type
        var collision_shape = CollisionShape3D.new()
        var shape: Shape3D

        match tree_type:
            "pine", "conifer", "tall":
                var capsule = CapsuleShape3D.new()
                capsule.radius = 1.2
                capsule.height = 8.0
                shape = capsule
            "broadleaf", "oak", "birch", "deciduous":
                var box = BoxShape3D.new()
                box.size = Vector3(2.5, 8.0, 2.5)
                shape = box
            "palm":
                var cylinder = CylinderShape3D.new()
                cylinder.radius = 0.8
                cylinder.height = 10.0
                shape = cylinder
            _:
                var capsule = CapsuleShape3D.new()
                capsule.radius = 1.0
                capsule.height = 7.0
                shape = capsule

        collision_shape.shape = shape
        collision_body.add_child(collision_shape)
        collision_shape.owner = collision_body

        # Add damageable component
        var damageable = DamageableComponent.new()
        damageable.object_type = tree_type
        damageable.max_health = _get_health_for_type(tree_type)
        damageable.current_health = damageable.max_health
        collision_body.add_child(damageable)
        damageable.owner = collision_body

        # Add to parent of the multimesh instance
        var parent = multimesh_instance.get_parent()
        if parent:
            parent.add_child(collision_body)
            collision_body.owner = parent

## Add collision to buildings
static func add_collision_to_buildings(building_node: MeshInstance3D, building_type: String = "building") -> void:
    if not building_node:
        return

    # Create a StaticBody3D for the building collision
    var collision_body = StaticBody3D.new()
    collision_body.name = building_node.name + "_Collision"

    # Set collision layers to ensure raycasts can detect this object
    collision_body.collision_layer = 1
    collision_body.collision_mask = 1  # Match the layer

    # Position at the same location as the building
    # Check if the node is in the tree before accessing global_position
    if building_node.is_inside_tree():
        collision_body.global_position = building_node.global_position
    else:
        # If not in tree yet, use the node's current transform
        collision_body.transform = building_node.transform

    # Create collision shape appropriate for building type
    var collision_shape = CollisionShape3D.new()
    var shape: Shape3D

    match building_type:
        "house", "cottage", "hut", "cabin":
            var box = BoxShape3D.new()
            var building_size = building_node.get_aabb().size
            box.size = Vector3(max(building_size.x, 3.0), max(building_size.y, 4.0), max(building_size.z, 3.0))
            shape = box
        "factory", "warehouse", "mill", "industrial":
            var box = BoxShape3D.new()
            var building_size = building_node.get_aabb().size
            box.size = Vector3(max(building_size.x, 6.0), max(building_size.y, 6.0), max(building_size.z, 6.0))
            shape = box
        "shop", "tavern", "inn", "pub":
            var box = BoxShape3D.new()
            var building_size = building_node.get_aabb().size
            box.size = Vector3(max(building_size.x, 4.0), max(building_size.y, 5.0), max(building_size.z, 4.0))
            shape = box
        _:
            var box = BoxShape3D.new()
            var building_size = building_node.get_aabb().size
            box.size = Vector3(max(building_size.x, 4.0), max(building_size.y, 5.0), max(building_size.z, 4.0))
            shape = box

    collision_shape.shape = shape
    collision_body.add_child(collision_shape)
    collision_shape.owner = collision_body

    # Add damageable component
    var damageable = DamageableComponent.new()
    damageable.object_type = building_type
    damageable.max_health = _get_health_for_type(building_type)
    damageable.current_health = damageable.max_health
    collision_body.add_child(damageable)
    damageable.owner = collision_body

    # Add to parent of the building
    var parent = building_node.get_parent()
    if parent:
        parent.add_child(collision_body)
        collision_body.owner = parent

## Get appropriate health for object type
static func _get_health_for_type(object_type: String) -> float:
    match object_type:
        "tree", "pine", "oak", "birch", "palm":
            return 25.0
        "house", "cottage", "hut", "cabin":
            return 100.0
        "factory", "warehouse", "mill", "industrial":
            return 200.0
        "shop", "tavern", "inn", "pub":
            return 120.0
        _:
            return 50.0

## Add collision to all trees in a scene
static func add_collision_to_all_trees_in_scene(scene_root: Node, tree_types: Array = ["tree"]) -> void:
    var trees = _find_all_trees_recursive(scene_root, tree_types)
    for tree in trees:
        if tree is MultiMeshInstance3D:
            add_collision_to_multimesh_trees(tree, "tree")
        elif tree is MeshInstance3D:
            # For individual tree meshes, we'd need to add collision differently
            # This is a simplified approach - in practice, you'd need to identify tree meshes specifically
            pass

## Find all tree objects in a scene recursively
static func _find_all_trees_recursive(node: Node, tree_types: Array) -> Array:
    var trees = []
    
    # Check if this node is a tree
    if _is_tree_node(node, tree_types):
        trees.append(node)
    
    # Recursively check all children
    for child in node.get_children():
        trees.append_array(_find_all_trees_recursive(child, tree_types))
    
    return trees

## Check if a node is a tree
static func _is_tree_node(node, tree_types: Array) -> bool:
    if node is MultiMeshInstance3D:
        # Check if this is a tree multimesh by name or other characteristics
        return node.name.to_lower().contains("tree") or node.name.to_lower().contains("forest")
    
    if node is MeshInstance3D:
        # Check if this is a tree mesh by name or other characteristics
        var node_name = node.name.to_lower()
        for tree_type in tree_types:
            if node_name.contains(tree_type):
                return true
    
    return false

## Add collision to a tree instance
static func add_collision_to_tree(tree_node: Node3D, tree_type: String = "tree") -> void:
    if not tree_node:
        return

    # Create a StaticBody3D for the tree collision
    var tree_collision_body = StaticBody3D.new()
    tree_collision_body.name = tree_node.name + "_Collision"

    # Set collision layers and masks to ensure raycasts can detect this object
    # Use layer 1 for static environment objects and make sure it can collide with raycasts
    tree_collision_body.collision_layer = 1  # Layer for static environment
    tree_collision_body.collision_mask = 1  # Match the layer (this is standard for environment objects)

    # Create a collision shape appropriate for the tree type
    var collision_shape = CollisionShape3D.new()
    var shape: Shape3D

    # Use different shapes based on tree type
    match tree_type:
        "pine", "conifer", "tall":
            # Use a capsule shape for tall trees
            var capsule = CapsuleShape3D.new()
            capsule.radius = 1.2  # Adjust based on tree size
            capsule.height = 8.0  # Adjust based on tree height
            shape = capsule
        "broadleaf", "oak", "birch", "deciduous":
            # Use a box shape for broader trees
            var box = BoxShape3D.new()
            box.size = Vector3(2.5, 8.0, 2.5)  # Adjust based on tree size
            shape = box
        "palm":
            # Use a cylinder for palm trees
            var cylinder = CylinderShape3D.new()
            cylinder.radius = 0.8
            cylinder.height = 10.0
            shape = cylinder
        _:
            # Default to capsule for unknown tree types
            var capsule = CapsuleShape3D.new()
            capsule.radius = 1.0
            capsule.height = 7.0
            shape = capsule

    collision_shape.shape = shape
    tree_collision_body.add_child(collision_shape)
    collision_shape.owner = tree_collision_body

    # Position the collision body at the same location as the tree
    # Check if the node is in the tree before accessing global_position
    if tree_node.is_inside_tree():
        tree_collision_body.global_position = tree_node.global_position
        print("DEBUG: Added collision body for tree '", tree_node.name, "' at position: ", tree_node.global_position)
    else:
        # If not in tree yet, use the node's current transform
        tree_collision_body.transform = tree_node.transform
        print("DEBUG: Added collision body for tree '", tree_node.name, "' with local transform")

    # Add the collision body to the scene
    var parent = tree_node.get_parent()
    if parent:
        parent.add_child(tree_collision_body)
        tree_collision_body.owner = parent
        print("DEBUG: Added collision body to parent: ", parent.name)
    else:
        # If no parent, add to the root
        var root = tree_node.get_tree().root
        root.add_child(tree_collision_body)
        tree_collision_body.owner = root
        print("DEBUG: Added collision body to root")

    # Add damageable component to make tree destructible
    var damageable = DamageableComponent.new()
    damageable.object_type = "tree"
    damageable.max_health = _get_health_for_type("tree")
    damageable.current_health = damageable.max_health
    tree_collision_body.add_child(damageable)
    damageable.owner = tree_collision_body

## Add collision to all buildings in a scene
static func add_collision_to_all_buildings_in_scene(scene_root: Node, building_types: Array = ["building"]) -> void:
    var buildings = _find_all_buildings_recursive(scene_root, building_types)
    for building in buildings:
        if building is MeshInstance3D:
            var building_type = _get_building_type_from_name(building.name)
            add_collision_to_buildings(building, building_type)

## Find all building objects in a scene recursively
static func _find_all_buildings_recursive(node: Node, building_types: Array) -> Array:
    var buildings = []
    
    # Check if this node is a building
    if _is_building_node(node, building_types):
        buildings.append(node)
    
    # Recursively check all children
    for child in node.get_children():
        buildings.append_array(_find_all_buildings_recursive(child, building_types))
    
    return buildings

## Check if a node is a building
static func _is_building_node(node, building_types: Array) -> bool:
    if node is MeshInstance3D:
        # Check if this is a building by name or other characteristics
        var node_name = node.name.to_lower()
        for building_type in building_types:
            if node_name.contains(building_type):
                return true
    
    return false

## Get building type from name
static func _get_building_type_from_name(name: String) -> String:
    var lower_name = name.to_lower()
    
    if lower_name.contains("house") or lower_name.contains("cottage") or lower_name.contains("hut") or lower_name.contains("cabin"):
        return "house"
    elif lower_name.contains("factory") or lower_name.contains("warehouse") or lower_name.contains("mill") or lower_name.contains("industrial"):
        return "factory"
    elif lower_name.contains("shop") or lower_name.contains("tavern") or lower_name.contains("inn") or lower_name.contains("pub"):
        return "shop"
    else:
        return "building"