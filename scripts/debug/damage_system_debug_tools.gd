## Debug tools for the damage system
## Allows testing different configurations and viewing object states

class_name DamageSystemDebugTools
extends Node

## Reference to the damage manager
var damage_manager = null

## UI elements for the debug panel
var debug_panel: Control = null
var health_label: Label = null
var set_label: Label = null
var stage_label: Label = null
var config_selector: OptionButton = null
var damage_slider: HSlider = null
var damage_button: Button = null

func _ready() -> void:
    # Get reference to damage manager
    if Engine.has_singleton("DamageManager"):
        damage_manager = Engine.get_singleton("DamageManager")
    
    # Create debug UI
    _create_debug_ui()

## Create the debug UI panel
func _create_debug_ui() -> void:
    # Create a panel for the debug tools
    debug_panel = PanelContainer.new()
    debug_panel.name = "DamageSystemDebugPanel"
    
    # Set panel properties
    var panel_style = StyleBoxFlat.new()
    panel_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
    panel_style.border_width_left = 1
    panel_style.border_width_right = 1
    panel_style.border_width_top = 1
    panel_style.border_width_bottom = 1
    panel_style.set_border_color(Color(0.5, 0.5, 0.5, 1))
    debug_panel.add_theme_stylebox_override("panel", panel_style)
    
    # Create a VBoxContainer for layout
    var vbox = VBoxContainer.new()
    vbox.name = "DebugVBox"
    
    # Add title
    var title = Label.new()
    title.text = "Damage System Debug Tools"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(title)
    
    # Add health label
    health_label = Label.new()
    health_label.name = "HealthLabel"
    health_label.text = "Health: N/A"
    vbox.add_child(health_label)
    
    # Add set label
    set_label = Label.new()
    set_label.name = "SetLabel"
    set_label.text = "Set: N/A"
    vbox.add_child(set_label)
    
    # Add stage label
    stage_label = Label.new()
    stage_label.name = "StageLabel"
    stage_label.text = "Stage: N/A"
    vbox.add_child(stage_label)
    
    # Add config selector
    config_selector = OptionButton.new()
    config_selector.name = "ConfigSelector"
    config_selector.add_item("Industrial")
    config_selector.add_item("Residential")
    config_selector.add_item("Natural")
    config_selector.select(0)  # Default to Industrial
    vbox.add_child(config_selector)
    
    # Add damage slider
    damage_slider = HSlider.new()
    damage_slider.name = "DamageSlider"
    damage_slider.min_value = 1.0
    damage_slider.max_value = 50.0
    damage_slider.value = 10.0
    damage_slider.step = 1.0
    vbox.add_child(damage_slider)
    
    # Add damage button
    damage_button = Button.new()
    damage_button.name = "DamageButton"
    damage_button.text = "Apply Damage"
    damage_button.pressed.connect(_on_damage_button_pressed)
    vbox.add_child(damage_button)
    
    # Add a button to reload configs
    var reload_button = Button.new()
    reload_button.name = "ReloadButton"
    reload_button.text = "Reload Configs"
    reload_button.pressed.connect(_on_reload_configs_pressed)
    vbox.add_child(reload_button)
    
    # Add all elements to the panel
    debug_panel.add_child(vbox)
    
    # Position the panel in the top-left corner
    debug_panel.position = Vector2(10, 10)
    debug_panel.size = Vector2(250, 300)
    
    # Add the panel to the viewport
    var viewport = get_viewport()
    if viewport:
        viewport.gui_root.add_child(debug_panel)
        debug_panel.hide()  # Start hidden

## Toggle the debug panel visibility
func toggle_debug_panel(visible: bool) -> void:
    if debug_panel:
        debug_panel.visible = visible

## Update the debug info for an object
func update_debug_info(object) -> void:
    if not object:
        health_label.text = "Health: N/A"
        set_label.text = "Set: N/A"
        stage_label.text = "Stage: N/A"
        return
    
    # Update health info
    if object.has_method("get_health") and object.has_method("get_max_health"):
        var current_health = object.get_health()
        var max_health = object.get_max_health()
        health_label.text = "Health: %.1f / %.1f" % [current_health, max_health]
    
    # Update set info
    if object.has_method("get_object_set"):
        var object_set = object.get_object_set()
        set_label.text = "Set: %s" % object_set
    
    # Update stage info
    if object.has_method("get_destruction_stage"):
        var stage = object.get_destruction_stage()
        var stage_names = ["Intact", "Damaged", "Ruined", "Destroyed"]
        var stage_name = "Unknown"
        if stage >= 0 and stage < stage_names.size():
            stage_name = stage_names[stage]
        stage_label.text = "Stage: %s (%d)" % [stage_name, stage]

## Called when the damage button is pressed
func _on_damage_button_pressed() -> void:
    if not damage_manager:
        print("DamageManager not available")
        return
    
    # This would apply damage to the selected object
    # For now, we'll just print the action
    var selected_set = config_selector.get_item_text(config_selector.selected)
    var damage_amount = damage_slider.value
    print("Applying %.1f damage to %s set objects" % [damage_amount, selected_set])
    
    # In a real implementation, we would apply damage to selected objects
    # For now, we'll just update the UI
    update_debug_info(null)

## Called when the reload configs button is pressed
func _on_reload_configs_pressed() -> void:
    if not damage_manager:
        print("DamageManager not available")
        return
    
    # Reload the configuration
    var config_path = "res://resources/configs/object_sets_config.tres"
    var new_config = load(config_path)
    if new_config:
        damage_manager.update_config(new_config)
        print("Reloaded object sets configuration")
    else:
        print("Could not load configuration from %s" % config_path)

## Apply damage to a specific object
func apply_damage_to_object(object, damage_amount: float) -> void:
    if damage_manager:
        damage_manager.apply_damage_to_object(object, damage_amount, "debug_test")

## Get the current selected object set from the UI
func get_selected_object_set() -> String:
    return config_selector.get_item_text(config_selector.selected)

## Get the current damage amount from the UI
func get_selected_damage_amount() -> float:
    return damage_slider.value

## Enable/disable debug drawing
func set_debug_drawing(enabled: bool) -> void:
    # This would enable visual indicators for damageable objects
    # In a real implementation, this might draw outlines around damageable objects
    pass