@tool
extends EditorScript

func _run():
    print("🔄 Reimporting all external assets after material enhancement...")
    
    # Reimport all FBX files to extract materials with new settings
    var fbx_files = []
    var dir = DirAccess.open("res://assets/external/packs")
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if file_name.ends_with(".fbx"):
                var full_path = "res://assets/external/packs/" + file_name
                fbx_files.append(full_path)
            file_name = dir.get_next()
        dir.list_dir_end()
    
    # Also search subdirectories
    for pack_dir in ["kenney_city-kit-suburban", "kenney_city-kit-industrial", "kenney_nature-kit", "kenney_city-kit-roads"]:
        var pack_path = "res://assets/external/packs/" + pack_dir + "/Models/FBX format/"
        if DirAccess.dir_exists_absolute(pack_path):
            var dir2 = DirAccess.open(pack_path)
            if dir2:
                dir2.list_dir_begin()
                var file_name = dir2.get_next()
                while file_name != "":
                    if file_name.ends_with(".fbx"):
                        var full_path = pack_path + file_name
                        fbx_files.append(full_path)
                    file_name = dir2.get_next()
                dir2.list_dir_end()
    
    # Reimport all FBX files
    var reimported = 0
    for fbx_path in fbx_files:
        EditorInterface.get_resource_filesystem().reimport_files([fbx_path])
        reimported += 1
        if reimported % 10 == 0:
            print("Reimported ", reimported, " files...")
    
    # Reimport texture files for good measure
    var texture_files = []
    var tex_dir = "res://assets/external/textures"
    if DirAccess.dir_exists_absolute(tex_dir):
        var dir3 = DirAccess.open(tex_dir)
        if dir3:
            dir3.list_dir_begin()
            var file_name = dir3.get_next()
            while file_name != "":
                if file_name.ends_with(".jpg") or file_name.ends_with(".png"):
                    var full_path = tex_dir + "/" + file_name
                    texture_files.append(full_path)
                file_name = dir3.get_next()
            dir3.list_dir_end()
    
    for tex_path in texture_files:
        EditorInterface.get_resource_filesystem().reimport_files([tex_path])
    
    print("✅ Material enhancement complete!")
    print("   📦 Reimported ", reimported, " FBX files")
    print("   🎨 Reimported ", texture_files.size(), " texture files")
    print("\n🎉 Your game should now look dramatically more awesome!")
    print("   External meshes will use high-quality PBR materials")
    print("   Terrain textures will be more visible")
    print("   All assets have optimized import settings")
