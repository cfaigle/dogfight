class_name ArchitecturalTemplate
extends RefCounted

## Base architectural template system for creating authentic building designs
## Provides standardized patterns, proportions, and construction methods

# Architectural constants based on real building principles
const GOLDEN_RATIO: float = 1.618
const HUMAN_SCALE: float = 1.7  # Average human height for scale reference
const DOOR_WIDTH: float = 0.9   # Standard door width
const DOOR_HEIGHT: float = 2.1  # Standard door height
const WINDOW_WIDTH: float = 1.2 # Standard window width
const WINDOW_HEIGHT: float = 1.5 # Standard window height

# Material properties
enum MaterialType {
    STONE,
    TIMBER,
    BRICK,
    STUCCO,
    CLAPBOARD,
    THATCH,
    SLATE,
    METAL
}

# Architectural styles with their characteristic proportions
enum ArchitecturalStyle {
    RUSTIC_COTTAGE,
    TIMBER_FRAME,
    STONE_FARMHOUSE,
    VICTORIAN,
    CAPE_COD,
    LOG_CABIN,
    MEDITERRANEAN,
    COLONIAL
}

# Building component templates
class WallSegment:
    var start: Vector3
    var end: Vector3
    var height: float
    var thickness: float
    var material: MaterialType
    var has_opening: bool = false
    var opening_type: String = ""
    var opening_position: float = 0.5  # 0-1 along wall segment

class RoofSegment:
    var ridge_line: PackedVector3Array
    var eave_lines: Array[PackedVector3Array]
    var pitch: float  # Angle in degrees
    var material: MaterialType
    var overhang: float

class Opening:
    var type: String  # "door", "window", "chimney"
    var position: Vector3
    var width: float
    var height: float
    var frame_material: MaterialType
    var has_shutters: bool = false
    var has_lintel: bool = true

class Foundation:
    var footprint: PackedVector3Array
    var height: float
    var material: MaterialType
    var has_basement: bool = false

# Template data for different architectural styles
static var style_templates: Dictionary = {}

func _init():
    _initialize_style_templates()

static func _initialize_style_templates():
    # Rustic Cottage Template
    var cottage_template = {
        "proportions": {
            "width_to_depth": 1.2,
            "wall_to_roof_height": 0.6,
            "eave_overhang": 0.3,
            "foundation_height": 0.4
        },
        "materials": {
            "walls": MaterialType.STONE,
            "roof": MaterialType.THATCH,
            "foundation": MaterialType.STONE,
            "windows": MaterialType.TIMBER,
            "door": MaterialType.TIMBER
        },
        "characteristics": {
            "irregular_walls": true,
            "steep_roof": true,
            "prominent_chimney": true,
            "small_windows": true,
            "heavy_door": true,
            "stone_texture": true
        },
        "color_palette": {
            "stone": Color(0.6, 0.55, 0.45),
            "thatch": Color(0.8, 0.7, 0.4),
            "timber": Color(0.4, 0.3, 0.2),
            "mortar": Color(0.8, 0.8, 0.75)
        }
    }
    
    style_templates[ArchitecturalStyle.RUSTIC_COTTAGE] = cottage_template

static func get_template(style: ArchitecturalStyle) -> Dictionary:
    return style_templates.get(style, {})

static func create_authentic_dimensions(style: ArchitecturalStyle, lot_width: float, lot_depth: float) -> Dictionary:
    var template = get_template(style)
    var proportions = template.get("proportions", {})
    
    # Calculate authentic dimensions based on architectural principles
    var result = {
        "width": 0.0,
        "depth": 0.0,
        "wall_height": 0.0,
        "roof_height": 0.0,
        "foundation_height": 0.0,
        "eave_overhang": 0.0
    }
    
    # Base dimensions on human scale and lot constraints
    result.width = clamp(lot_width * 0.7, 4.0, 8.0)
    result.depth = clamp(lot_depth * 0.6, 3.5, 7.0)
    
    # Apply style proportions
    var width_to_depth = proportions.get("width_to_depth", 1.2)
    if result.width / result.depth > width_to_depth * 1.5:
        result.depth = result.width / width_to_depth
    elif result.width / result.depth < width_to_depth * 0.5:
        result.width = result.depth * width_to_depth
    
    # Wall height based on human scale and style
    result.wall_height = clamp(HUMAN_SCALE * 2.5, 3.0, 5.0)
    
    # Roof proportions
    var wall_to_roof = proportions.get("wall_to_roof_height", 0.5)
    result.roof_height = result.wall_height * wall_to_roof
    
    # Foundation and overhangs
    result.foundation_height = proportions.get("foundation_height", 0.3)
    result.eave_overhang = proportions.get("eave_overhang", 0.2)
    
    return result

static func create_wall_segments(dimensions: Dictionary, style: ArchitecturalStyle) -> Array[WallSegment]:
    var segments: Array[WallSegment] = []
    var template = get_template(style)
    var characteristics = template.get("characteristics", {})
    
    var hw = dimensions.width * 0.5
    var hd = dimensions.depth * 0.5
    var h = dimensions.wall_height
    
    # Define wall corners with potential irregularity for rustic styles
    var corners = [
        Vector3(-hw, 0, -hd),
        Vector3(hw, 0, -hd),
        Vector3(hw, 0, hd),
        Vector3(-hw, 0, hd)
    ]
    
    # Add irregularity for rustic styles
    if characteristics.get("irregular_walls", false):
        for i in range(corners.size()):
            corners[i].x += randf_range(-0.15, 0.15)
            corners[i].z += randf_range(-0.15, 0.15)
    
    # Create wall segments
    for i in range(4):
        var next = (i + 1) % 4
        var segment = WallSegment.new()
        segment.start = corners[i]
        segment.end = corners[next]
        segment.height = h
        segment.thickness = 0.3
        segment.material = template.get("materials", {}).get("walls", MaterialType.STONE)
        
        # Add openings based on wall position
        if i == 2:  # Front wall
            segment.has_opening = true
            segment.opening_type = "door"
            segment.opening_position = 0.3
        elif i == 0 or i == 3:  # Side walls
            if randf() > 0.3:  # 70% chance of window
                segment.has_opening = true
                segment.opening_type = "window"
                segment.opening_position = randf_range(0.2, 0.8)
        
        segments.append(segment)
    
    return segments

static func create_roof_structure(dimensions: Dictionary, style: ArchitecturalStyle) -> RoofSegment:
    var template = get_template(style)
    var characteristics = template.get("characteristics", {})
    
    var roof = RoofSegment.new()
    roof.material = template.get("materials", {}).get("roof", MaterialType.THATCH)
    roof.overhang = dimensions.eave_overhang
    
    # Roof pitch based on style
    if characteristics.get("steep_roof", false):
        roof.pitch = randf_range(35, 45)  # Very steep for rustic cottages
    else:
        roof.pitch = randf_range(20, 30)  # Moderate pitch
    
    # Create ridge line (simplified for gable roof)
    var hw = dimensions.width * 0.5
    var hd = dimensions.depth * 0.5
    var wall_height = dimensions.wall_height
    var roof_height = dimensions.roof_height
    
    roof.ridge_line = PackedVector3Array([
        Vector3(-hw * 0.8, wall_height + roof_height, -hd),
        Vector3(hw * 0.8, wall_height + roof_height, -hd)
    ])
    
    # Create eave lines
    roof.eave_lines = [
        PackedVector3Array([  # Front eave
            Vector3(-hw - roof.overhang, wall_height, hd + roof.overhang),
            Vector3(hw + roof.overhang, wall_height, hd + roof.overhang)
        ]),
        PackedVector3Array([  # Back eave
            Vector3(-hw - roof.overhang, wall_height, -hd - roof.overhang),
            Vector3(hw + roof.overhang, wall_height, -hd - roof.overhang)
        ])
    ]
    
    return roof

static func create_openings(segments: Array[WallSegment], style: ArchitecturalStyle) -> Array[Opening]:
    var openings: Array[Opening] = []
    var template = get_template(style)
    var characteristics = template.get("characteristics", {})
    
    for segment in segments:
        if not segment.has_opening:
            continue
        
        var opening = Opening.new()
        opening.type = segment.opening_type
        
        # Calculate position along wall
        var wall_vector = segment.end - segment.start
        var wall_length = wall_vector.length()
        var position_along_wall = segment.opening_position * wall_length
        var wall_direction = wall_vector.normalized()
        
        opening.position = segment.start + wall_direction * position_along_wall
        opening.position.y = 0.0  # Ground level
        
        # Set dimensions based on opening type
        if opening.type == "door":
            opening.width = DOOR_WIDTH
            opening.height = DOOR_HEIGHT
            opening.frame_material = MaterialType.TIMBER
        elif opening.type == "window":
            if characteristics.get("small_windows", false):
                opening.width = WINDOW_WIDTH * 0.7
                opening.height = WINDOW_HEIGHT * 0.8
            else:
                opening.width = WINDOW_WIDTH
                opening.height = WINDOW_HEIGHT
            opening.frame_material = MaterialType.TIMBER
            opening.has_shutters = characteristics.get("rustic_style", false)
        
        openings.append(opening)
    
    return openings

static func create_material_for_type(material_type: MaterialType, style: ArchitecturalStyle) -> StandardMaterial3D:
    var template = get_template(style)
    var color_palette = template.get("color_palette", {})
    
    var mat = StandardMaterial3D.new()
    
    match material_type:
        MaterialType.STONE:
            mat.albedo_color = color_palette.get("stone", Color(0.6, 0.55, 0.45))
            mat.roughness = 0.95
            mat.metallic = 0.0
            mat.normal_scale = 0.4
        MaterialType.THATCH:
            mat.albedo_color = color_palette.get("thatch", Color(0.8, 0.7, 0.4))
            mat.roughness = 0.9
            mat.metallic = 0.0
            mat.normal_scale = 0.6
        MaterialType.TIMBER:
            mat.albedo_color = color_palette.get("timber", Color(0.4, 0.3, 0.2))
            mat.roughness = 0.85
            mat.metallic = 0.0
            mat.normal_scale = 0.3
        MaterialType.BRICK:
            mat.albedo_color = Color(0.8, 0.4, 0.3)
            mat.roughness = 0.9
            mat.metallic = 0.0
            mat.normal_scale = 0.5
        _:
            mat.albedo_color = Color.GRAY
            mat.roughness = 0.8
            mat.metallic = 0.0
    
    return mat