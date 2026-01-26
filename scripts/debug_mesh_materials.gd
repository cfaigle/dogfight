extends SceneTree

# Debug script to examine materials in external meshes

func _init():
    print("=== Mesh Materials Debug ===")
    
    var AssetLibraryScript = preload("res://scripts/util/asset_library.gd")
    var assets = AssetLibraryScript.new()
    
    # Test with external assets enabled
    assets.reload(true)
    
    var euro_meshes = assets.get_mesh_variants("euro_buildings")
    print("Examining euro building meshes...")
    
    for i in range(min(3, euro_meshes.size())):
        var mesh = euro_meshes[i]
        print("\n--- Mesh ", i, " ---")
        print("Type: ", mesh.get_class())
        print("Surface count: ", mesh.get_surface_count())
        
        for surf_idx in range(mesh.get_surface_count()):
            print("  Surface ", surf_idx, ":")
            
            # Get material for this surface
            var mat = mesh.surface_get_material(surf_idx)
            if mat:
                print("    Material: ", mat.get_class())
                if mat is StandardMaterial3D:
                    var std_mat = mat as StandardMaterial3D
                    print("      Albedo color: ", std_mat.albedo_color)
                    if std_mat.albedo_texture:
                        print("      Albedo texture: ", std_mat.albedo_texture.get_class(), " ", std_mat.albedo_texture.get_size())
                    else:
                        print("      Albedo texture: null")
                    if std_mat.normal_texture:
                        print("      Normal texture: ", std_mat.normal_texture.get_class(), " ", std_mat.normal_texture.get_size())
                    else:
                        print("      Normal texture: null")
                elif mat is ShaderMaterial:
                    print("      Shader material: ", (mat as ShaderMaterial).shader.get_class())
            else:
                print("    Material: null")
    
    quit()
