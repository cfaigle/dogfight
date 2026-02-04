class_name BuildingTypeRegistry
extends Resource

## Unified Building Type Registry
## Provides consistent building classification and configuration across all generation systems
## Eliminates data mismatches and chaotic building generation

# Building classification system
enum BuildingCategory {
    RURAL,
    SUBURBAN,
    URBAN,
    COMMERCIAL,
    MILITARY,
    SPECIAL
}

enum BuildingStyle {
    RUSTIC,
    TRADITIONAL,
    MODERN,
    HISTORIC,
    INDUSTRIAL,
    AGRICULTURAL,
}

# Building configuration structure
class BuildingConfig:
    var building_type: String
    var category: int
    var style: int
    var preferred_template: String = ""
    var fallback_geometry: String = ""
    var density_class: String = "rural"
    var height_range: Vector2 = Vector2(4.0, 8.0)
    var has_gable_roof: bool = true
    var roof_type: String = "gable"
    var roof_pitch: float = 25.0
    var material_override: String = ""
    
    func _init(building_type: String, category: int, style: int):
        self.building_type = building_type
        self.category = category
        self.style = style
        
        # Apply building-specific configurations
        _apply_building_config()
    
    func _apply_building_config():
        # Rural cottages and houses
        if building_type in ["stone_cottage", "stone_cottage_new", "thatched_cottage", "cottage", "timber_cabin", "log_chalet", "rustic_cabin"]:
            preferred_template = building_type
            height_range = Vector2(3.5, 6.5)
            has_gable_roof = true
            density_class = "rural"
            roof_type = "gable"
            roof_pitch = 35.0 if building_type == "thatched_cottage" else 40.0
        
        # Farm and agricultural buildings
        elif building_type in ["barn", "stable", "farmhouse", "outbuilding", "granary"]:
            preferred_template = building_type if building_type == "barn" else "stone_cottage_classic"
            height_range = Vector2(4.0, 8.0)
            has_gable_roof = true
            density_class = "rural"
            roof_type = "gable"
            roof_pitch = 30.0
        
        # Industrial and commercial buildings
        elif building_type in ["factory", "industrial", "warehouse"]:
            preferred_template = "industrial_factory"
            height_range = Vector2(8.0, 20.0)
            has_gable_roof = true
            density_class = "urban"
            roof_type = "gable"
            roof_pitch = 20.0
        
        # Special and unique buildings
        elif building_type in ["windmill", "blacksmith"]:
            preferred_template = building_type
            height_range = Vector2(8.0, 15.0)
            has_gable_roof = true
            density_class = "rural"
            roof_type = "gable"
            roof_pitch = 25.0
        elif building_type in ["radio_tower"]:
            preferred_template = building_type
            height_range = Vector2(30.0, 60.0)  # Much taller than other buildings
            has_gable_roof = false  # No roof for radio tower
            density_class = "rural"
            roof_type = "none"
            roof_pitch = 0.0
        elif building_type in ["grain_silo"]:
            preferred_template = building_type
            height_range = Vector2(12.0, 18.0)  # Tall cylindrical structure
            has_gable_roof = false  # Dome top instead
            density_class = "rural"
            roof_type = "none"
            roof_pitch = 0.0
        elif building_type in ["corn_feeder"]:
            preferred_template = building_type
            height_range = Vector2(8.0, 12.0)  # Elevated bin on legs
            has_gable_roof = false  # Cone top instead
            density_class = "rural"
            roof_type = "none"
            roof_pitch = 0.0

        # Religious and civic buildings
        elif building_type in ["church", "temple", "cathedral"]:
            preferred_template = building_type if building_type == "church" else "medieval_castle"
            height_range = Vector2(10.0, 25.0)
            has_gable_roof = true
            density_class = "suburban"
            roof_type = "gable"
            roof_pitch = 35.0 if building_type == "church" else 40.0
        
        # Military and fortifications
        elif building_type in ["castle", "fortress", "tower"]:
            preferred_template = "medieval_castle"
            height_range = Vector2(12.0, 30.0)
            has_gable_roof = true
            density_class = "suburban"
            roof_type = "gable"
            roof_pitch = 30.0
        
        # Small utility buildings
        elif building_type in ["lighthouse", "fishing_hut", "shepherd_hut"]:
            preferred_template = building_type if building_type != "fishing_hut" else "stone_cottage_classic"
            height_range = Vector2(4.0, 8.0)
            has_gable_roof = true
            density_class = "rural"
            roof_type = "gable"
            roof_pitch = 40.0
        
        # Mixed density buildings (flexible placement)
        elif building_type in ["house", "residential", "white_stucco_house", "stone_farmhouse", "house_victorian", "house_colonial", "house_tudor"]:
            preferred_template = "stone_cottage_classic"
            height_range = Vector2(5.0, 15.0)
            density_class = "suburban"
            has_gable_roof = true
            roof_type = "gable"
            roof_pitch = 30.0
        
        # Default configuration
        else:
            preferred_template = "stone_cottage_classic"
            height_range = Vector2(4.0, 8.0)
            has_gable_roof = true
            density_class = "rural"
            roof_type = "gable"
            roof_pitch = 25.0

# Registry data
var _registry: Dictionary = {}

# Main registry class
static var _instance: Resource = null

static func get_instance():
    if _instance == null:
        _instance = new()
        _instance._initialize_registry()
    return _instance

func _init():
    # Ensure registry is initialized even when instantiated directly
    if _registry.is_empty():
        _initialize_registry()

func _initialize_registry():
    # Pre-populate common building configurations
    _registry = {}
    
    var building_types = [
        "stone_cottage", "stone_cottage_new", "thatched_cottage", "cottage", "timber_cabin", "log_chalet", "rustic_cabin",
        "barn", "stable", "farmhouse", "outbuilding", "granary", "fishing_hut", "shepherd_hut",
        "factory", "industrial", "warehouse", "windmill", "blacksmith", "radio_tower", "grain_silo", "corn_feeder",
        "church", "temple", "cathedral", "castle", "fortress", "tower",
        "lighthouse", "house", "residential", "white_stucco_house", "stone_farmhouse",
        "house_victorian", "house_colonial", "house_tudor"
    ]
    
    for building_type in building_types:
        var config = BuildingConfig.new(building_type, 0, 0)  # Use enum values as integers
        _registry[building_type] = config

func get_building_config(building_type: String) -> BuildingConfig:
    return _registry.get(building_type, _get_default_config())

func _get_default_config() -> BuildingConfig:
    var config = BuildingConfig.new("unknown", 0, 0)  # Use enum values as integers
    config.preferred_template = "stone_cottage_classic"
    config.height_range = Vector2(4.0, 8.0)
    config.density_class = "rural"
    config.has_gable_roof = true
    config.roof_type = "gable"
    config.roof_pitch = 25.0
    return config

func is_valid_building_type(building_type: String) -> bool:
    return building_type in _registry

func get_all_building_types() -> Array[String]:
    return _registry.keys()

func get_rural_types() -> Array[String]:
    var rural_types = []
    for building_type in _registry:
        var config = _registry[building_type]
        if config.density_class == "rural":
            rural_types.append(building_type)
    return rural_types

func get_suburban_types() -> Array[String]:
    var suburban_types = []
    for building_type in _registry:
        var config = _registry[building_type]
        if config.density_class == "suburban":
            suburban_types.append(building_type)
    return suburban_types

func get_urban_types() -> Array[String]:
    var urban_types = []
    for building_type in _registry:
        var config = _registry[building_type]
        if config.density_class == "urban":
            urban_types.append(building_type)
    return urban_types

func validate_registry():
    print("🔍 Validating building type registry...")
    
    var total_types = _registry.size()
    var valid_types = 0
    var invalid_configs = []
    
    for building_type in _registry:
        var config = _registry[building_type]
        
        # Check required fields
        if config.building_type != "":
            valid_types += 1
        else:
            invalid_configs.append(building_type)
    
    print("   ✓ Total building types: ", total_types)
    print("   ✓ Valid configurations: ", valid_types)
    
    if invalid_configs.size() > 0:
        print("   ❌ Invalid configurations: ", invalid_configs)
    else:
        print("   ✓ All building types valid")

func print_registry_stats():
    print("📊 Building Type Registry Statistics:")
    print("   📋 Total registered types: ", _registry.size())
    
    # Count by density class
    var density_counts = {}
    for building_type in _registry:
        var config = _registry[building_type]
        var density = config.density_class
        if not density_counts.has(density):
            density_counts[density] = 0
        density_counts[density] += 1
    
    for density in density_counts:
        print("   ", density, ": ", density_counts[density], " types")
    
    print("   🏗️ Registry ready for unified building generation")

func get_building_type_for_density(density_class: String, rng: RandomNumberGenerator) -> String:
    # Get all building types for the specified density class
    var matching_types = []
    
    for building_type in _registry:
        var config = _registry[building_type]
        if config.density_class == density_class:
            matching_types.append(building_type)
    
    # If no specific types found, use fallback types
    if matching_types.is_empty():
        match density_class:
            "rural":
                matching_types = ["stone_cottage", "thatched_cottage", "timber_cabin"]
            "suburban":
                matching_types = ["stone_farmhouse", "white_stucco_house", "house_victorian"]
            "urban":
                matching_types = ["shop", "bakery", "inn", "workshop"]
            "urban_core":
                matching_types = ["factory_building", "train_station", "church"]
            _:
                matching_types = ["stone_cottage"]  # Ultimate fallback
    
    # Randomly select from matching types
    if matching_types.size() > 0:
        return matching_types[rng.randi() % matching_types.size()]
    
    return "stone_cottage"  # Final fallback