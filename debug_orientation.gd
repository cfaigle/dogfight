extends Node

# Debug script to verify player starting position and orientation
func _ready():
	print("=== PLAYER STARTING ORIENTATION DEBUG ===")
	
	# Wait a frame for everything to be set up
	await get_tree().process_frame
	
	var player = Game.player
	if not player:
		print("ERROR: No player found!")
		return
	
	print("Player position: ", player.global_position)
	print("Player rotation (degrees): ", player.global_rotation_degrees)
	print("Player basis vectors:")
	print("  Forward (-Z): ", -player.global_transform.basis.z)
	print("  Right (+X): ", player.global_transform.basis.x)
	print("  Up (+Y): ", player.global_transform.basis.y)
	
	# What direction is "right" from player's perspective?
	var player_right = player.global_transform.basis.x
	print("Player's right direction vector: ", player_right)
	
	# Check if there are more settlements on the right side
	var settlements = get_tree().get_nodes_in_group("settlements") if get_tree().has_group("settlements") else []
	print("Total settlements found: ", settlements.size())
	
	var right_count = 0
	var left_count = 0
	var front_count = 0
	var back_count = 0
	
	for settlement in settlements:
		var to_settlement = settlement.global_position - player.global_position
		var dot_right = to_settlement.normalized().dot(player_right)
		var dot_forward = to_settlement.normalized().dot(-player.global_transform.basis.z)
		
		if dot_right > 0:
			right_count += 1
		else:
			left_count += 1
			
		if dot_forward > 0:
			front_count += 1
		else:
			back_count += 1
	
	print("Settlement distribution relative to player:")
	print("  Right side: ", right_count)
	print("  Left side: ", left_count)
	print("  Front: ", front_count) 
	print("  Back: ", back_count)
	
	print("=== END DEBUG ===")
	
	# Clean up
	queue_free()
