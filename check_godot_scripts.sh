#!/bin/bash

# Define the path to the Godot executable
GODOT_EXECUTABLE="/Applications/Godot.app/Contents/MacOS/Godot"

# Check if the Godot executable exists
if [ ! -f "$GODOT_EXECUTABLE" ]; then
    echo "Error: Godot executable not found at $GODOT_EXECUTABLE"
    exit 1
fi

# Use find to locate .gd and .tscn files and execute the command on each
find . -type f \( -name "*.gd" -o -name "*.tscn" \) -print0 | while IFS= read -r -d '' file; do
    echo "Checking file: $file"
    "$GODOT_EXECUTABLE"  --check-only --script "$file"
    # Optional: Check the exit status of the Godot command
    if [ $? -ne 0 ]; then
        echo "Error checking file $file"
    fi
done

echo "Script check complete."
