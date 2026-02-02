## Debug visualization tools for the collision system
## Provides visual feedback for collision shapes and system status

extends Node

## Reference to the collision manager
var collision_manager = null

## UI elements for the debug panel
var debug_panel: Control = null
var status_label: Label = null
var count_label: Label = null
var toggle_button: Button = null
var visualize_button: Button = null

## Visual indicators for collision shapes
var visualization_nodes: Array = []

func _ready() -> void:
    # Get reference to collision manager
    if Engine.has_singleton("CollisionManager"):
        collision_manager = Engine.get_singleton("CollisionManager")
    
    # Create debug UI
    _create_debug_ui()

## Create the debug UI panel
func _create_debug_ui() -> void:
    # Create a panel for the debug tools
    debug_panel = PanelContainer.new()
    debug_panel.name = "CollisionDebugPanel"
    
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
    title.text = "Collision System Debug"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(title)
    
    # Add status label
    status_label = Label.new()
    status_label.name = "StatusLabel"
    status_label.text = "Status: Active"
    vbox.add_child(status_label)
    
    # Add count label
    count_label = Label.new()
    count_label.name = "CountLabel"
    count_label.text = "Active Collisions: 0"
    vbox.add_child(count_label)
    
    # Add toggle button
    toggle_button = Button.new()
    toggle_button.name = "ToggleButton"
    toggle_button.text = "Disable Collisions"
    toggle_button.pressed.connect(_on_toggle_pressed)
    vbox.add_child(toggle_button)
    
    # Add visualize button
    visualize_button = Button.new()
    visualize_button.name = "VisualizeButton"
    visualize_button.text = "Visualize Shapes"
    visualize_button.pressed.connect(_on_visualize_pressed)
    vbox.add_child(visualize_button)
    
    # Add all elements to the panel
    debug_panel.add_child(vbox)
    
    # Position the panel in the top-right corner
    debug_panel.position = Vector2(10, 50)
    debug_panel.size = Vector2(250, 200)
    
    # Add the panel to the viewport
    var viewport = get_viewport()
    if viewport:
        viewport.gui_root.add_child(debug_panel)
        debug_panel.hide()  # Start hidden

## Toggle the debug panel visibility
func toggle_debug_panel(visible: bool) -> void:
    if debug_panel:
        debug_panel.visible = visible

## Update the debug info
func update_debug_info() -> void:
    if not collision_manager:
        status_label.text = "Status: Not Available"
        count_label.text = "Active Collisions: 0"
        return
    
    # Update status
    var enabled = collision_manager.collision_config.enabled
    status_label.text = "Status: %s" % ("Enabled" if enabled else "Disabled")
    
    # Update collision count
    var count = collision_manager.get_active_collision_count()
    count_label.text = "Active Collisions: %d" % count

## Called when the toggle button is pressed
func _on_toggle_pressed() -> void:
    if collision_manager:
        var current_enabled = collision_manager.collision_config.enabled
        collision_manager.set_collision_enabled(not current_enabled)
        
        # Update button text
        toggle_button.text = "%s Collisions" % ("Disable" if current_enabled else "Enable")
        
        # Update info
        update_debug_info()

## Called when the visualize button is pressed
func _on_visualize_pressed() -> void:
    if collision_manager:
        # Toggle visualization
        if visualization_nodes.size() > 0:
            # Remove existing visualization
            _remove_visualization()
        else:
            # Create visualization
            _create_visualization()

## Create visualization for collision shapes
func _create_visualization() -> void:
    # This would create visual representations of collision shapes
    # For now, we'll just add a placeholder
    visualize_button.text = "Hide Visualization"
    
    # In a real implementation, this would iterate through active collisions
    # and create visual representations of their shapes

## Remove visualization
func _remove_visualization() -> void:
    # Remove all visualization nodes
    for node in visualization_nodes:
        if node and is_instance_valid(node):
            if node.get_parent():
                node.get_parent().remove_child(node)
            node.queue_free()
    
    visualization_nodes.clear()
    visualize_button.text = "Visualize Shapes"

## Toggle visualization on/off
func toggle_visualization(active: bool) -> void:
    if active:
        _create_visualization()
    else:
        _remove_visualization()

## Get the current status of the collision system
func get_status() -> Dictionary:
    if collision_manager:
        return {
            "enabled": collision_manager.collision_config.enabled,
            "active_collisions": collision_manager.get_active_collision_count(),
            "distance_threshold": collision_manager.collision_config.distance_threshold
        }
    return {"enabled": false, "active_collisions": 0, "distance_threshold": 0.0}

## Update the visualization continuously (called from game loop)
func update_visualization() -> void:
    # Update visualization in real-time if needed
    # This would update the visual representations of collision shapes
    pass