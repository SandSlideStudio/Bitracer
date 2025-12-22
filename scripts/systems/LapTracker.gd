extends Area2D
# Attach this script directly to your Track's Area2D node

@onready var start_line: CollisionShape2D = $StartLine
@onready var mid_point: CollisionShape2D = $MidPoint

# Reference to the UI
var lap_timer_ui = null

# Multiplayer-friendly: Track lap state per car
var car_lap_states := {}  # Dictionary: car_instance_id -> lap_state

# Lap state structure
class LapState:
	var passed_start: bool = false
	var passed_mid: bool = false
	var lap_in_progress: bool = false
	var last_checkpoint: String = ""

func _ready() -> void:
	# Connect signals for Area2D entering
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	
	# Also connect body_entered for CharacterBody2D/RigidBody2D detection
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	print("Lap tracker ready! (Multiplayer-friendly)")
	print("StartLine found: ", start_line != null)
	print("MidPoint found: ", mid_point != null)
	
	# Find the lap timer UI in the scene tree
	lap_timer_ui = get_tree().current_scene.get_node_or_null("LapTimerUI")
	if lap_timer_ui == null:
		print("WARNING: LapTimerUI not found")
	else:
		print("LapTimerUI found!")

func _on_area_entered(area: Area2D) -> void:
	var car_node = _find_car_node(area)
	if car_node:
		_handle_checkpoint(car_node)

func _on_body_entered(body: Node2D) -> void:
	var car_node = _find_car_node(body)
	if car_node:
		_handle_checkpoint(car_node)

func _on_area_exited(area: Area2D) -> void:
	var car_node = _find_car_node(area)
	if car_node:
		_clear_last_checkpoint(car_node)

func _on_body_exited(body: Node2D) -> void:
	var car_node = _find_car_node(body)
	if car_node:
		_clear_last_checkpoint(car_node)

# ROBUST CAR DETECTION - Works with any car setup
func _find_car_node(node: Node) -> Node:
	# Start with the node itself
	var current = node
	
	# Check up to 3 levels up the tree to find the car root
	for i in range(3):
		if _is_car(current):
			return current
		
		if current.get_parent():
			current = current.get_parent()
		else:
			break
	
	return null

# Multiple ways to detect if a node is a car
func _is_car(node: Node) -> bool:
	if node == null:
		return false
	
	# Method 1: Check for "player" or "car" group (RECOMMENDED - add this to your cars!)
	if node.is_in_group("player") or node.is_in_group("car"):
		return true
	
	# Method 2: Check for Camera2D child
	if node.has_node("Camera2D"):
		return true
	
	# Method 3: Check name contains "car" (case insensitive)
	if "car" in node.name.to_lower():
		return true
	
	# Method 4: Check if it has specific car-related nodes
	if node.has_node("Wheels") or node.has_node("Body") or node.has_node("Sprite2D"):
		return true
	
	# Method 5: Check if it's a physics body with specific properties
	if node is CharacterBody2D or node is RigidBody2D:
		# Could be a car if it has certain children
		for child in node.get_children():
			if "wheel" in child.name.to_lower() or "camera" in child.name.to_lower():
				return true
	
	return false

func _get_lap_state(car: Node) -> LapState:
	var car_id = car.get_instance_id()
	if not car_lap_states.has(car_id):
		car_lap_states[car_id] = LapState.new()
	return car_lap_states[car_id]

func _clear_last_checkpoint(car: Node) -> void:
	var state = _get_lap_state(car)
	state.last_checkpoint = ""

func _handle_checkpoint(car: Node) -> void:
	print("Car detected: ", car.name)
	
	var state = _get_lap_state(car)
	
	# Determine which checkpoint was crossed based on distance
	var car_pos: Vector2 = car.global_position
	var start_pos: Vector2 = start_line.global_position
	var mid_pos: Vector2 = mid_point.global_position
	
	var dist_to_start: float = car_pos.distance_to(start_pos)
	var dist_to_mid: float = car_pos.distance_to(mid_pos)
	
	print("  Distance to start: ", dist_to_start, " | Distance to mid: ", dist_to_mid)
	
	# Determine which checkpoint is closer
	if dist_to_start < dist_to_mid:
		if state.last_checkpoint != "start":
			_on_start_line_crossed(car, state)
			state.last_checkpoint = "start"
	else:
		if state.last_checkpoint != "mid":
			_on_mid_point_crossed(car, state)
			state.last_checkpoint = "mid"

func _on_start_line_crossed(car: Node, state: LapState) -> void:
	print("START LINE CROSSED by ", car.name)
	
	if not state.lap_in_progress:
		# Starting a new lap
		state.passed_start = true
		state.passed_mid = false
		state.lap_in_progress = true
		
		# Only start UI timer for local player
		if _is_local_player(car) and lap_timer_ui:
			lap_timer_ui.start_timing()
			print("  Timer started!")
	
	elif state.passed_mid:
		# Completing a lap (crossed mid, now back at start)
		if _is_local_player(car) and lap_timer_ui:
			var lap_time: float = lap_timer_ui.stop_timing()
			print("  LAP COMPLETED! Time: ", lap_time)
		
		# Start new lap immediately
		state.passed_start = true
		state.passed_mid = false
		
		if _is_local_player(car) and lap_timer_ui:
			lap_timer_ui.start_timing()
			print("  New lap started!")

func _on_mid_point_crossed(car: Node, state: LapState) -> void:
	print("MIDPOINT CROSSED by ", car.name)
	
	if state.lap_in_progress and state.passed_start and not state.passed_mid:
		# Reached midpoint
		state.passed_mid = true
		print("  Midpoint registered!")

# Check if this car is the local player (for UI updates)
func _is_local_player(car: Node) -> bool:
	# For single player, always return true
	if not multiplayer.has_multiplayer_peer():
		return true
	
	# For multiplayer, check if this is the local player's car
	# You'll need to add multiplayer_authority or similar to your cars
	if car.has_method("is_multiplayer_authority"):
		return car.is_multiplayer_authority()
	
	# Fallback: check if car is in "local_player" group
	return car.is_in_group("local_player")
