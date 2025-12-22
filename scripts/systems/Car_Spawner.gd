extends Node2D

# Default car to spawn if none selected
const DEFAULT_CAR := preload("res://scenes/player/Car/Car_Arcade_Physics_with_rpm+gearshifts.tscn")

var spawned_cars := {}  # peer_id -> car_instance
var spawn_positions: Array[Marker2D] = []

# Draw spawn positions in editor for debugging
func _draw():
	if Engine.is_editor_hint():
		for i in range(spawn_positions.size()):
			var pos = spawn_positions[i]
			# Draw a circle at spawn position
			draw_circle(pos.position, 10, Color.GREEN)
			# Draw arrow showing rotation
			var dir = Vector2.from_angle(pos.rotation)
			draw_line(pos.position, pos.position + dir * 30, Color.RED, 2)

func _ready():
	print("=== CAR SPAWNER READY ===")
	print("Node name: ", name)
	print("Node type: ", get_class())
	print("Is multiplayer: ", GameGlobals.is_multiplayer)
	print("Has multiplayer peer: ", multiplayer.has_multiplayer_peer())
	
	# Find all spawn positions
	_find_spawn_positions()
	
	# Small delay to ensure everything is ready
	await get_tree().create_timer(0.1).timeout
	
	# Spawn cars based on mode
	# CRITICAL: Check is_multiplayer flag first, not just multiplayer peer
	# (peer can be leftover from previous session)
	if GameGlobals.is_multiplayer and GameManager.session_active:
		print("Spawning multiplayer cars...")
		_spawn_multiplayer_cars()
	else:
		print("Spawning single player car...")
		_spawn_single_player_car()

func _find_spawn_positions():
	print("=== SEARCHING FOR SPAWN POSITIONS ===")
	print("This node has ", get_child_count(), " children")
	
	# Search direct children
	for child in get_children():
		if child is Marker2D and child.name.begins_with("SpawnPosition"):
			spawn_positions.append(child)
			print("  ✓ ADDED: ", child.name, " at ", child.global_position)
	
	# Sort by name numerically
	spawn_positions.sort_custom(func(a, b): 
		var num_a = int(a.name.replace("SpawnPosition", ""))
		var num_b = int(b.name.replace("SpawnPosition", ""))
		return num_a < num_b
	)
	
	print("=== TOTAL SPAWN POSITIONS FOUND: ", spawn_positions.size(), " ===")
	
	if spawn_positions.size() == 0:
		push_error("NO SPAWN POSITIONS FOUND!")
	else:
		print("Spawn positions in order:")
		for i in range(spawn_positions.size()):
			var pos = spawn_positions[i]
			print("  [", i, "] ", pos.name, " at ", pos.global_position, " rotation ", pos.global_rotation_degrees, "°")

func _get_spawn_transform(index: int) -> Transform2D:
	if spawn_positions.size() == 0:
		push_error("No spawn positions available!")
		var fallback = Transform2D()
		fallback.origin = Vector2(index * 150, 0)
		return fallback
	
	if index < spawn_positions.size():
		var marker = spawn_positions[index]
		print("Using spawn position [", index, "]: ", marker.name)
		print("  Position: ", marker.global_position)
		print("  Rotation: ", marker.global_rotation_degrees, "°")
		
		# Return the marker's global transform
		return marker.global_transform
	
	# Fallback: offset from last position
	print("Not enough spawn positions, creating offset from last one")
	var last_spawn = spawn_positions[spawn_positions.size() - 1]
	var offset_distance = 150.0 * (index - spawn_positions.size() + 1)
	var direction = Vector2.from_angle(last_spawn.global_rotation)
	var perpendicular = direction.rotated(PI / 2)
	var offset = perpendicular * offset_distance
	
	var new_transform = Transform2D()
	new_transform.origin = last_spawn.global_position + offset
	new_transform = new_transform.rotated(last_spawn.global_rotation)
	return new_transform

func _spawn_single_player_car():
	print("=== SPAWNING SINGLE PLAYER CAR ===")
	
	var car_path = GameGlobals.selected_car_path
	var car_scene: PackedScene
	
	if car_path != "" and ResourceLoader.exists(car_path):
		car_scene = load(car_path)
		print("Loaded selected car: ", car_path)
	else:
		car_scene = DEFAULT_CAR
		print("Using default car")
	
	var car = car_scene.instantiate()
	print("Car instantiated: ", car.name)
	
	# Add car FIRST
	add_child(car)
	print("Car added to scene")
	
	# Then set transform
	var spawn_transform = _get_spawn_transform(0)
	car.global_transform = spawn_transform
	
	print("Final car position: ", car.global_position)
	print("Final car rotation: ", car.global_rotation_degrees, "°")
	
	# Check if car actually moved
	if car.global_position.distance_to(spawn_transform.origin) > 1.0:
		push_warning("WARNING: Car position doesn't match spawn position!")
		push_warning("  Expected: ", spawn_transform.origin)
		push_warning("  Actual: ", car.global_position)
		push_warning("  Difference: ", car.global_position - spawn_transform.origin)
	
	# Enable cameras
	var cameras = _find_cameras(car)
	if cameras.size() > 0:
		for camera in cameras:
			camera.enabled = true
			camera.make_current()
		print("Camera enabled")
	
	print("=== SPAWN COMPLETE ===")

func _find_cameras(node: Node) -> Array:
	var cameras = []
	for child in node.get_children():
		if child is Camera2D:
			cameras.append(child)
		if child.get_child_count() > 0:
			cameras.append_array(_find_cameras(child))
	return cameras

func _spawn_multiplayer_cars():
	print("=== SPAWNING MULTIPLAYER CARS ===")
	await get_tree().create_timer(0.2).timeout
	
	if GameManager.is_server():
		print("Server spawning cars...")
		var spawn_index = 0
		var sorted_peer_ids = GameManager.players.keys()
		sorted_peer_ids.sort()
		
		for peer_id in sorted_peer_ids:
			print("  Spawning peer ", peer_id, " at index ", spawn_index)
			_spawn_car_for_player.rpc(peer_id, spawn_index)
			spawn_index += 1
	else:
		print("Client waiting...")

@rpc("authority", "call_local", "reliable")
func _spawn_car_for_player(peer_id: int, spawn_index: int):
	print("=== SPAWN CAR FOR PLAYER ", peer_id, " ===")
	
	var player_info = GameManager.players.get(peer_id)
	if not player_info:
		push_error("No player info for peer: ", peer_id)
		return
	
	var car_path = player_info.get("car_path", "")
	var car_scene: PackedScene
	
	if car_path != "" and ResourceLoader.exists(car_path):
		car_scene = load(car_path)
	else:
		car_scene = DEFAULT_CAR
	
	var car = car_scene.instantiate()
	car.name = "Car_" + str(peer_id)
	car.set_multiplayer_authority(peer_id)
	
	add_child(car)
	
	var spawn_transform = _get_spawn_transform(spawn_index)
	car.global_transform = spawn_transform
	
	print("Car positioned at: ", car.global_position, " rotation: ", car.global_rotation_degrees, "°")
	
	if car.has_node("MultiplayerSync"):
		var sync_node = car.get_node("MultiplayerSync")
		if sync_node.has_method("set_player_authority"):
			sync_node.set_player_authority(peer_id)
	
	spawned_cars[peer_id] = car
	print("=== SPAWN COMPLETE ===")
