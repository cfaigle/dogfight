class_name WindowComponent
extends BuildingComponentBase

## Generates windows with various styles and details
## Supports square, arched, bay windows with optional shutters and trim

func get_required_params() -> Array[String]:
    return ["footprint", "height", "floors", "window_style"]

func get_optional_params() -> Dictionary:
    return {
        "floor_height": 3.0,
        "window_width": 1.2,
        "window_height": 1.6,
        "window_spacing": 2.5,
        "window_depth": 0.15,
        "window_proportion": 0.4,  # Windows per unit width
        "add_shutters": false,
        "add_trim": false,
        "add_window_boxes": false,
        "skip_ground_floor": false
    }

func generate(st: SurfaceTool, params: Dictionary, materials: Dictionary) -> void:
    var footprint: PackedVector2Array = params["footprint"]
    var height: float = params["height"]
    var floors: int = params["floors"]
    var floor_height: float = params.get("floor_height", height / float(floors))
    var window_style: String = params["window_style"]

    var window_width: float = params["window_width"]
    var window_height: float = params["window_height"]
    var window_spacing: float = params["window_spacing"]
    var window_depth: float = params["window_depth"]
    var skip_ground_floor: bool = params["skip_ground_floor"]

    var add_shutters: bool = params["add_shutters"]
    var add_trim: bool = params["add_trim"]
    var add_window_boxes: bool = params["add_window_boxes"]

    # Iterate through each wall segment
    var point_count = footprint.size()
    for i in range(point_count):
        var p0 = footprint[i]
        var p1 = footprint[(i + 1) % point_count]

        var wall_vector = Vector3(p1.x - p0.x, 0, p1.y - p0.y)
        var wall_length = wall_vector.length()
        var wall_dir = wall_vector.normalized()

        # Calculate number of windows for this wall
        var window_count = max(1, int(wall_length / window_spacing))

        # Iterate through each floor
        var start_floor = 1 if skip_ground_floor else 0
        for floor in range(start_floor, floors):
            var floor_y = floor * floor_height + floor_height * 0.5 - window_height * 0.5

            # Place windows along wall
            for j in range(window_count):
                var t = (j + 1.0) / (window_count + 1.0)  # Position along wall
                var window_x = lerp(0.0, wall_length, t)

                # Calculate window center position
                var wall_start = Vector3(p0.x, 0, p0.y)
                var window_center = wall_start + wall_dir * window_x
                window_center.y = floor_y + window_height * 0.5

                # Calculate wall normal (perpendicular to wall direction)
                var wall_normal = Vector3(-wall_dir.z, 0, wall_dir.x)

                # Generate window based on style
                match window_style:
                    "square":
                        _create_square_window(st, window_center, wall_dir, wall_normal,
                                              window_width, window_height, window_depth)
                    "arched":
                        _create_arched_window(st, window_center, wall_dir, wall_normal,
                                              window_width, window_height, window_depth)
                    "bay":
                        _create_bay_window(st, window_center, wall_dir, wall_normal,
                                           window_width, window_height, window_depth)
                    "divided":
                        _create_divided_window(st, window_center, wall_dir, wall_normal,
                                               window_width, window_height, window_depth)
                    _:
                        _create_square_window(st, window_center, wall_dir, wall_normal,
                                              window_width, window_height, window_depth)

                # Add optional details
                if add_trim:
                    _add_window_trim(st, window_center, wall_dir, wall_normal,
                                     window_width, window_height, window_depth)

                if add_shutters:
                    _add_shutters(st, window_center, wall_dir, wall_normal,
                                  window_width, window_height, window_depth)

                if add_window_boxes and floor > 0:  # Only on upper floors
                    _add_window_box(st, window_center, wall_dir, wall_normal,
                                    window_width, window_depth)

## Create a square window with frame and glass
func _create_square_window(st: SurfaceTool, center: Vector3, wall_dir: Vector3,
                           wall_normal: Vector3, width: float, height: float,
                           depth: float) -> void:
    # Window is recessed into wall
    var recess = depth * 0.5

    # Calculate corners
    var right = wall_dir
    var up = Vector3.UP

    var half_w = width * 0.5
    var half_h = height * 0.5

    # Frame corners (at wall surface)
    var tl_frame = center + up * half_h - right * half_w
    var tr_frame = center + up * half_h + right * half_w
    var bl_frame = center - up * half_h - right * half_w
    var br_frame = center - up * half_h + right * half_w

    # Glass corners (recessed)
    var tl_glass = tl_frame - wall_normal * recess
    var tr_glass = tr_frame - wall_normal * recess
    var bl_glass = bl_frame - wall_normal * recess
    var br_glass = br_frame - wall_normal * recess

    # Create glass pane
    add_quad(st, bl_glass, br_glass, tr_glass, tl_glass,
             Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

    # Create window frame (sides of recess)
    var frame_thickness = 0.05

    # Top frame
    add_quad(st, tl_frame, tr_frame, tr_glass, tl_glass)

    # Bottom frame
    add_quad(st, bl_glass, br_glass, br_frame, bl_frame)

    # Left frame
    add_quad(st, bl_frame, tl_frame, tl_glass, bl_glass)

    # Right frame
    add_quad(st, tr_glass, tr_frame, br_frame, br_glass)

## Create an arched window
func _create_arched_window(st: SurfaceTool, center: Vector3, wall_dir: Vector3,
                           wall_normal: Vector3, width: float, height: float,
                           depth: float) -> void:
    # Lower portion is square
    var square_height = height * 0.6
    var arch_height = height * 0.4

    var square_center = center - Vector3.UP * arch_height * 0.5
    _create_square_window(st, square_center, wall_dir, wall_normal,
                          width, square_height, depth)

    # Upper portion is arched
    var arch_center = center + Vector3.UP * square_height * 0.5
    var recess = depth * 0.5

    var right = wall_dir
    var half_w = width * 0.5

    # Create arch with segments
    var segments = 8
    for i in range(segments):
        var angle1 = PI + (i / float(segments)) * PI
        var angle2 = PI + ((i + 1) / float(segments)) * PI

        var x1 = cos(angle1) * half_w
        var y1 = sin(angle1) * half_w
        var x2 = cos(angle2) * half_w
        var y2 = sin(angle2) * half_w

        var p1_frame = arch_center + right * x1 + Vector3.UP * y1
        var p2_frame = arch_center + right * x2 + Vector3.UP * y2
        var p1_glass = p1_frame - wall_normal * recess
        var p2_glass = p2_frame - wall_normal * recess

        # Create a thin quad segment
        add_quad(st, p1_glass, p2_glass, p2_frame, p1_frame)

## Create a bay window (projects outward)
func _create_bay_window(st: SurfaceTool, center: Vector3, wall_dir: Vector3,
                        wall_normal: Vector3, width: float, height: float,
                        depth: float) -> void:
    var bay_depth = width * 0.3
    var bay_angle = deg_to_rad(30)

    var right = wall_dir
    var half_w = width * 0.5

    # Center panel
    _create_square_window(st, center + wall_normal * bay_depth * 0.5,
                          wall_dir, wall_normal, width * 0.5, height, depth * 0.5)

    # Left panel (angled)
    var left_center = center - right * half_w * 0.75 + wall_normal * bay_depth * 0.25
    var left_normal = wall_normal.rotated(Vector3.UP, bay_angle)
    var left_dir = wall_dir.rotated(Vector3.UP, bay_angle)
    _create_square_window(st, left_center, left_dir, left_normal,
                          width * 0.35, height, depth * 0.5)

    # Right panel (angled)
    var right_center = center + right * half_w * 0.75 + wall_normal * bay_depth * 0.25
    var right_normal = wall_normal.rotated(Vector3.UP, -bay_angle)
    var right_dir = wall_dir.rotated(Vector3.UP, -bay_angle)
    _create_square_window(st, right_center, right_dir, right_normal,
                          width * 0.35, height, depth * 0.5)

## Create a divided window with multiple panes
func _create_divided_window(st: SurfaceTool, center: Vector3, wall_dir: Vector3,
                            wall_normal: Vector3, width: float, height: float,
                            depth: float) -> void:
    # Create 4 small windows in a 2x2 grid
    var pane_width = width * 0.45
    var pane_height = height * 0.45
    var gap = width * 0.1

    var offsets = [
        Vector3(-gap * 0.5 - pane_width * 0.5, gap * 0.5 + pane_height * 0.5, 0),
        Vector3(gap * 0.5 + pane_width * 0.5, gap * 0.5 + pane_height * 0.5, 0),
        Vector3(-gap * 0.5 - pane_width * 0.5, -gap * 0.5 - pane_height * 0.5, 0),
        Vector3(gap * 0.5 + pane_width * 0.5, -gap * 0.5 - pane_height * 0.5, 0)
    ]

    for offset in offsets:
        var pane_center = center + wall_dir * offset.x + Vector3.UP * offset.y
        _create_square_window(st, pane_center, wall_dir, wall_normal,
                              pane_width, pane_height, depth)

## Add decorative trim around window
func _add_window_trim(st: SurfaceTool, center: Vector3, wall_dir: Vector3,
                      wall_normal: Vector3, width: float, height: float,
                      depth: float) -> void:
    var trim_width = 0.1
    var trim_depth = 0.05

    var right = wall_dir
    var up = Vector3.UP

    var half_w = width * 0.5 + trim_width
    var half_h = height * 0.5 + trim_width

    # Create trim frame projecting slightly from wall
    var tl = center + up * half_h - right * half_w + wall_normal * trim_depth
    var tr = center + up * half_h + right * half_w + wall_normal * trim_depth
    var bl = center - up * half_h - right * half_w + wall_normal * trim_depth
    var br = center - up * half_h + right * half_w + wall_normal * trim_depth

    var tl_inner = center + up * (half_h - trim_width) - right * (half_w - trim_width)
    var tr_inner = center + up * (half_h - trim_width) + right * (half_w - trim_width)
    var bl_inner = center - up * (half_h - trim_width) - right * (half_w - trim_width)
    var br_inner = center - up * (half_h - trim_width) + right * (half_w - trim_width)

    # Top trim
    add_quad(st, tl_inner, tr_inner, tr, tl)
    # Bottom trim
    add_quad(st, bl, br, br_inner, bl_inner)
    # Left trim
    add_quad(st, bl, tl, tl_inner, bl_inner)
    # Right trim
    add_quad(st, tr_inner, tr, br, br_inner)

## Add shutters beside window
func _add_shutters(st: SurfaceTool, center: Vector3, wall_dir: Vector3,
                   wall_normal: Vector3, width: float, height: float,
                   depth: float) -> void:
    var shutter_width = width * 0.3
    var shutter_thickness = 0.05

    var right = wall_dir
    var up = Vector3.UP

    var half_h = height * 0.5

    # Left shutter
    var left_center = center - right * (width * 0.5 + shutter_width * 0.5)
    _create_shutter_panel(st, left_center, wall_dir, wall_normal,
                          shutter_width, height, shutter_thickness)

    # Right shutter
    var right_center = center + right * (width * 0.5 + shutter_width * 0.5)
    _create_shutter_panel(st, right_center, wall_dir, wall_normal,
                          shutter_width, height, shutter_thickness)

func _create_shutter_panel(st: SurfaceTool, center: Vector3, wall_dir: Vector3,
                            wall_normal: Vector3, width: float, height: float,
                            thickness: float) -> void:
    var right = wall_dir
    var up = Vector3.UP

    var half_w = width * 0.5
    var half_h = height * 0.5

    var tl = center + up * half_h - right * half_w + wall_normal * thickness
    var tr = center + up * half_h + right * half_w + wall_normal * thickness
    var bl = center - up * half_h - right * half_w + wall_normal * thickness
    var br = center - up * half_h + right * half_w + wall_normal * thickness

    add_quad(st, bl, br, tr, tl)

## Add window box (planter below window)
func _add_window_box(st: SurfaceTool, center: Vector3, wall_dir: Vector3,
                     wall_normal: Vector3, width: float, depth: float) -> void:
    var box_width = width * 1.1
    var box_depth = 0.3
    var box_height = 0.2

    var right = wall_dir
    var half_w = box_width * 0.5

    var box_center = center - Vector3.UP * 0.5 + wall_normal * box_depth * 0.5

    # Simple box geometry
    var corners = [
        box_center - right * half_w - Vector3.UP * box_height * 0.5 + wall_normal * box_depth * 0.5,
        box_center + right * half_w - Vector3.UP * box_height * 0.5 + wall_normal * box_depth * 0.5,
        box_center + right * half_w + Vector3.UP * box_height * 0.5 + wall_normal * box_depth * 0.5,
        box_center - right * half_w + Vector3.UP * box_height * 0.5 + wall_normal * box_depth * 0.5,
        box_center - right * half_w - Vector3.UP * box_height * 0.5 - wall_normal * box_depth * 0.5,
        box_center + right * half_w - Vector3.UP * box_height * 0.5 - wall_normal * box_depth * 0.5,
        box_center + right * half_w + Vector3.UP * box_height * 0.5 - wall_normal * box_depth * 0.5,
        box_center - right * half_w + Vector3.UP * box_height * 0.5 - wall_normal * box_depth * 0.5
    ]

    # Front face
    add_quad(st, corners[0], corners[1], corners[2], corners[3])
    # Top face
    add_quad(st, corners[3], corners[2], corners[6], corners[7])
    # Left face
    add_quad(st, corners[4], corners[0], corners[3], corners[7])
    # Right face
    add_quad(st, corners[1], corners[5], corners[6], corners[2])
