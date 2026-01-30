@tool
class_name MaterialDefinitions
extends Resource

@export var wall_material: StandardMaterial3D
@export var roof_material: StandardMaterial3D
@export var window_material: StandardMaterial3D
@export var door_material: StandardMaterial3D
@export var detail_material: StandardMaterial3D

# Create default materials if not set
func _init():
    if wall_material == null:
        wall_material = _create_stone_material()
    if roof_material == null:
        roof_material = _create_roof_material()
    if window_material == null:
        window_material = _create_glass_material()
    if door_material == null:
        door_material = _create_wood_material()
    if detail_material == null:
        detail_material = _create_detail_material()

func _create_stone_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.6, 0.55, 0.45)
    mat.roughness = 0.95
    mat.metallic = 0.0
    mat.normal_scale = 0.3
    return mat

func _create_roof_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.2, 0.15)
    mat.roughness = 0.9
    mat.metallic = 0.0
    return mat

func _create_glass_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.7, 0.8, 0.9)
    mat.roughness = 0.1
    mat.metallic = 0.0
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.alpha_scissor_threshold = 0.1
    return mat

func _create_wood_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.3, 0.2)
    mat.roughness = 0.8
    mat.metallic = 0.0
    return mat

func _create_detail_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.25, 0.2)
    mat.roughness = 0.85
    mat.metallic = 0.0
    return mat