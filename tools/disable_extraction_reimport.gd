@tool
extends EditorScript

func _run():
    print("🔄 Reimporting external assets after material extraction disabled...")
    
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
    
    # Reimport all FBX files in smaller batches to avoid timeouts
    var batch_size = 50
    var reimported = 0
    
    for i in range(0, fbx_files.size(), batch_size):
        var batch_end = mini(i + batch_size, fbx_files.size())
        var batch = []
        for j in range(i, batch_end):
            batch.append(fbx_files[j])
        
        if batch.size() > 0:
            EditorInterface.get_resource_filesystem().reimport_files(batch)
            reimported += batch.size()
            print("Reimported batch of ", batch.size(), " files (total: ", reimported, "/", fbx_files.size(), ")")
    
    print("✅ Material extraction disabled and reimport complete!")
    print("\n🎉 White squares should now be GONE!")
    print("Buildings will use embedded Kenney materials instead of broken extracted ones.")
