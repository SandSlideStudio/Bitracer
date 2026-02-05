# ai_racer.gd
extends StaticBody2D
class_name AIRacer

# -----------------------------
# AI Navigation
# -----------------------------
var track: Node2D
var waypoints: Array = []
var current_waypoint_index: int = 0
const WAYPOINT_REACH_DISTANCE: float = 80.0  # Increased from 50 to 80
var last_distance_to_waypoint: float = INF

# AI Behavior
@export var difficulty: String = "medium"  # "easy", "medium", "hard"
var base_skill: float = 1.0
var reaction_delay: float = 0.0
var mistake_chance: float = 0.0
var aggression: float = 0.5

# Overtaking
var overtake_offset: float = 0.0  # -1 to 1 (left to right)
var overtake_timer: float = 0.0
const OVERTAKE_DISTANCE: float = 100.0
const DETECTION_RADIUS: float = 80.0
const CAR_WIDTH: float = 32.0

# Rubberbanding
var target_position: int = 5  # What position AI tries to maintain
var distance_to_player: float = 0.0
var rubberband_multiplier: float = 1.0

# -----------------------------
# Engine + Transmission
# -----------------------------
const IDLE_RPM: float = 900.0
const REDLINE_RPM: float = 7800.0
const RPM_RANGE: float = 6900.0
var rpm: float = IDLE_RPM
var gear: int = 0
const MIN_GEAR: int = -1
const MAX_GEAR: int = 6
const SHIFT_COOLDOWN: float = 0.2
var shift_timer: float = 0.0

const GEAR_RATIOS: Array[float] = [3.20, 1.0, 3.20, 2.10, 1.45, 1.10, 0.90, 0.78]

# -----------------------------
# Car handling
# -----------------------------
@export var wheel_scale: float = 0.0525
@export var friction: float = 150.0
@export var max_turn_speed: float = 180.0
@export var min_turn_speed: float = 120.0
@export var turn_slow_factor: float = 0.05

const ENGINE_FORCE_MULTIPLIER: float = 56.25
const BRAKE_FORCE: float = 600.0
const TURN_DRAG_FACTOR: float = 0.5
const BRAKE_TURN_FACTOR: float = 0.7
const SPEED_TURN_LERP: float = 0.5

var velocity: Vector2 = Vector2.ZERO

# AI Input simulation
var ai_throttle: bool = false
var ai_brake: bool = false
var ai_turn_input: float = 0.0

# -----------------------------
# Engine Sound
# -----------------------------
@onready var engine_sound: AudioStreamPlayer2D = $EngineSound

@export var min_pitch: float = 0.8
@export var max_pitch: float = 2.5
@export var pitch_smoothing: float = 5.0
const BASE_VOLUME: float = -8.0
const THROTTLE_VOLUME_BOOST: float = 3.0
var current_pitch: float = 1.0

# -----------------------------
# Torque curve
# -----------------------------
func get_torque(in_rpm: float) -> float:
	if in_rpm < 1500.0:
		return 0.2
	if in_rpm < 3000.0:
		return 0.55
	if in_rpm < 4500.0:
		return 0.85
	if in_rpm < 6500.0:
		return 1.0
	if in_rpm < REDLINE_RPM:
		return 0.7
	return 0.0

# -----------------------------
# READY
# -----------------------------

func _ready() -> void:
		# Reset AI waypoint state
	current_waypoint_index = 0
	last_distance_to_waypoint = INF
	overtake_offset = 0.0
	overtake_timer = 0.0
	# Wait for scene to be ready
	await get_tree().process_frame
	
	# Find RacingLine directly - it's a sibling of the track
	var racing_line = get_node_or_null("/root/Scene collection/RacingLine")
	
	if racing_line:
		print("AI CAR: Found RacingLine directly at scene root!")
		load_waypoints_from_node(racing_line)
	else:
		print("AI CAR ERROR: Could not find RacingLine")
		print("AI CAR: Trying alternative search...")
		# Try to find it in parent
		var parent = get_parent()
		if parent and parent.has_node("RacingLine"):
			racing_line = parent.get_node("RacingLine")
			print("AI CAR: Found RacingLine in parent!")
			load_waypoints_from_node(racing_line)
		else:
			print("AI CAR: Searching entire tree...")
			racing_line = find_node_by_name(get_tree().root, "RacingLine")
			if racing_line:
				print("AI CAR: Found RacingLine via tree search at: ", racing_line.get_path())
				load_waypoints_from_node(racing_line)
			else:
				print("AI CAR FATAL ERROR: Cannot find RacingLine anywhere!")
	
	# Set difficulty parameters
	setup_difficulty()
	print("AI CAR: Difficulty set to ", difficulty, " (skill: ", base_skill, ")")
	
	# Start in 1st gear
	gear = 1
	rpm = IDLE_RPM
	
	# DEBUG: Print starting info
	print("AI CAR READY - Gear: ", gear, " | Waypoints: ", waypoints.size(), " | Position: ", global_position)

# Helper function to find node by name recursively
func find_node_by_name(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var result = find_node_by_name(child, node_name)
		if result:
			return result
	return null

# Helper function to load waypoints from a RacingLine node
func load_waypoints_from_node(racing_line: Node) -> void:
	print("AI CAR: Loading waypoints from ", racing_line.name, " at path: ", racing_line.get_path())
	print("AI CAR: RacingLine has ", racing_line.get_child_count(), " children")
	
	for child in racing_line.get_children():
		waypoints.append(child)
		print("  Added waypoint: ", child.name, " (type: ", child.get_class(), ") at position ", child.global_position)
	
	print("AI CAR: Total waypoints loaded: ", waypoints.size())
	
	if waypoints.size() == 0:
		print("AI CAR WARNING: No waypoints found! RacingLine might be empty.")

func setup_difficulty():
	match difficulty:
		"easy":
			base_skill = 0.75
			reaction_delay = 0.3
			mistake_chance = 0.15
			aggression = 0.3
		"medium":
			base_skill = 0.9
			reaction_delay = 0.15
			mistake_chance = 0.05
			aggression = 0.6
		"hard":
			base_skill = 1.0
			reaction_delay = 0.05
			mistake_chance = 0.01
			aggression = 0.9

# -----------------------------
# MAIN PROCESS
# -----------------------------
func _process(delta: float) -> void:
	shift_timer -= delta
	overtake_timer -= delta
	
	# TEMP DEBUG: Force movement if no waypoints
	if waypoints.is_empty():
		# Only print once per second to avoid spam
		if Engine.get_process_frames() % 60 == 0:
			print("AI CAR: No waypoints - forcing forward | Gear: ", gear, " RPM: ", int(rpm), " Velocity: ", velocity.length())
		ai_throttle = true
		ai_brake = false
		ai_turn_input = 0.0
		
		# Still need to shift!
		ai_shifting_logic()
	else:
		# Normal AI logic
		ai_navigation_logic(delta)
		ai_shifting_logic()
		apply_rubberbanding()
	
	# -----------------------------
	# FORWARD VECTOR & SPEED
	# -----------------------------
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var forward_speed: float = velocity.dot(forward)
	
	# -----------------------------
	# CALCULATE RPM FROM WHEEL SPEED
	# -----------------------------
	var ratio: float = GEAR_RATIOS[gear + 1] if gear != 0 else 1.0
	var abs_speed: float = abs(forward_speed)
	
	# RPM BEHAVIOR
	if gear == 0:
		rpm = move_toward(rpm, REDLINE_RPM if ai_throttle else IDLE_RPM, 
						  (5000.0 if ai_throttle else 2000.0) * delta)
	else:
		rpm = max(abs_speed * abs(ratio) / wheel_scale, IDLE_RPM)
	
	rpm += randf_range(-30.0, 30.0)
	rpm = clamp(rpm, IDLE_RPM - 50.0, REDLINE_RPM + 50.0)
	
	# -----------------------------
	# ENGINE FORCE
	# -----------------------------
	var engine_force: float = get_torque(rpm) * abs(ratio) * ENGINE_FORCE_MULTIPLIER
	engine_force *= rubberband_multiplier  # Apply rubberbanding
	
	# -----------------------------
	# ACCELERATION & BRAKING
	# -----------------------------
	if gear == 0:
		forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	elif gear == -1:
		if ai_throttle:
			forward_speed -= engine_force * delta
			forward_speed = max(forward_speed, -(REDLINE_RPM * wheel_scale / abs(ratio)))
		elif ai_brake:
			forward_speed = move_toward(forward_speed, 0.0, BRAKE_FORCE * delta)
		else:
			forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	else:
		if ai_throttle:
			forward_speed += engine_force * delta
			var max_speed: float = REDLINE_RPM * wheel_scale / ratio
			forward_speed = min(forward_speed, max_speed)
		elif ai_brake:
			forward_speed = move_toward(forward_speed, 0.0, BRAKE_FORCE * delta)
		else:
			forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	
	# TURN SLOWING
	if ai_turn_input != 0.0 and abs_speed > 1.0 and gear != 0:
		forward_speed -= sign(forward_speed) * abs_speed * TURN_DRAG_FACTOR * abs(ai_turn_input) * delta
	
	velocity = forward * forward_speed
	
	# -----------------------------
	# TURNING
	# -----------------------------
	if abs_speed > 0.1:
		var speed_factor: float = clamp(abs_speed * ratio / (REDLINE_RPM * wheel_scale), 0.0, 1.0)
		var current_turn_speed: float = lerp(max_turn_speed, min_turn_speed, speed_factor * SPEED_TURN_LERP)
		
		if ai_brake and forward_speed > 0.0:
			current_turn_speed *= BRAKE_TURN_FACTOR
		
		var steering_factor: float = -1.0 if forward_speed < 0.0 else 1.0
		global_rotation += deg_to_rad(ai_turn_input * current_turn_speed * steering_factor * delta)
	
	# -----------------------------
	# MOVE CAR
	# -----------------------------
	var collision: KinematicCollision2D = move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(collision.get_normal()) * 0.5
		# React to collision - try to reverse
		if randf() < 0.5:
			overtake_offset = -overtake_offset
	
	# -----------------------------
	# UPDATE ENGINE SOUND
	# -----------------------------
	update_engine_sound(delta)

# -----------------------------
# AI NAVIGATION LOGIC
# -----------------------------
func ai_navigation_logic(delta: float) -> void:
	var target_waypoint = waypoints[current_waypoint_index]
	
	# -----------------------------
	# Smooth lookahead target
	# -----------------------------
	var target_pos: Vector2 = get_lookahead_target(3)  # looks at next 3 waypoints
	
	# Apply overtake offset (perpendicular to direction)
	if overtake_offset != 0.0:
		var forward_dir = (waypoints[(current_waypoint_index + 1) % waypoints.size()].global_position - global_position).normalized()
		var perpendicular = Vector2(-forward_dir.y, forward_dir.x)
		target_pos += perpendicular * overtake_offset * (CAR_WIDTH * 1.5)
	
	# Calculate steering
	var direction_to_target = (target_pos - global_position).normalized()
	var target_angle = direction_to_target.angle() + PI / 2  # Adjust for car's forward being UP
	var angle_diff = angle_difference(global_rotation, target_angle)
	
	# Smooth steering with skill-based precision
	var steering_strength = clamp(angle_diff * 2.0, -1.0, 1.0)
	ai_turn_input = lerp(ai_turn_input, steering_strength * base_skill, 10.0 * delta)
	
	# Slight wobble for realism
	if randf() < 0.1:
		ai_turn_input += randf_range(-0.05, 0.05) * (1.0 - base_skill)
	
	# Determine throttle/brake based on upcoming turn
	var nav_next_idx = (current_waypoint_index + 1) % waypoints.size()
	var nav_next_waypoint = waypoints[nav_next_idx]
	var turn_sharpness = calculate_turn_sharpness(target_waypoint, nav_next_waypoint)
	
	var target_speed_mult = 1.0
	if "speed_multiplier" in target_waypoint:
		target_speed_mult = target_waypoint.speed_multiplier
	
	if turn_sharpness > 60 or target_speed_mult < 0.7:
		ai_brake = true
		ai_throttle = false
	else:
		ai_brake = false
		ai_throttle = true
	
	# Random mistakes
	if randf() < mistake_chance * delta:
		make_mistake()
	
	# Check if reached waypoint
	check_waypoint_reached(target_waypoint)



func detect_and_overtake() -> void:
	if overtake_timer > 0.0:
		return  # Still in overtake maneuver
	
	# Get all cars in physics space
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = DETECTION_RADIUS
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = collision_mask
	
	var results = space_state.intersect_shape(query, 10)
	
	for result in results:
		var body = result.collider
		if body == self or not (body is StaticBody2D or body is CharacterBody2D):
			continue
		
		# Check if car is ahead of us
		var to_car = body.global_position - global_position
		var forward = Vector2.UP.rotated(global_rotation)
		var dot = to_car.normalized().dot(forward)
		
		if dot > 0.7 and to_car.length() < OVERTAKE_DISTANCE:
			# Car is directly ahead - initiate overtake
			initiate_overtake(body)
			break

func initiate_overtake(target_car: Node2D) -> void:
	overtake_timer = randf_range(2.0, 4.0)
	
	# Decide which side to overtake based on aggression and track position
	if randf() < aggression:
		# Aggressive - take inside line
		var ot_next_idx = (current_waypoint_index + 1) % waypoints.size()
		var ot_next_waypoint = waypoints[ot_next_idx]
		var to_next = (ot_next_waypoint.global_position - global_position).normalized()
		var to_car = (target_car.global_position - global_position).normalized()
		var cross = to_next.cross(to_car)
		overtake_offset = 1.0 if cross > 0 else -1.0
	else:
		# Defensive - go wide
		overtake_offset = randf_range(-1.0, 1.0)

func calculate_turn_sharpness(current_wp, next_wp) -> float:
	var prev_idx = (current_waypoint_index - 1 + waypoints.size()) % waypoints.size()
	var prev_wp = waypoints[prev_idx]
	
	var dir1 = (current_wp.global_position - prev_wp.global_position).normalized()
	var dir2 = (next_wp.global_position - current_wp.global_position).normalized()
	
	var angle = rad_to_deg(acos(clamp(dir1.dot(dir2), -1.0, 1.0)))
	return angle

func get_lookahead_target(lookahead: int = 3) -> Vector2:
	# Get a weighted target based on the next few waypoints
	var total_weight = 0.0
	var target = Vector2.ZERO
	for i in range(lookahead):
		var idx = (current_waypoint_index + i) % waypoints.size()
		var wp = waypoints[idx]
		var weight = 1.0 / (i + 1)  # closer waypoints matter more
		target += wp.global_position * weight
		total_weight += weight
	return target / total_weight

func check_waypoint_reached(waypoint: Node2D) -> void:
	var current_distance = global_position.distance_to(waypoint.global_position)

	# DEBUG: Print waypoint status every 60 frames
	if Engine.get_process_frames() % 60 == 0:
		print("AI WAYPOINT: Target WP", current_waypoint_index, 
			  " | Distance: ", int(current_distance), 
			  " | Last: ", int(last_distance_to_waypoint),
			  " | Velocity: ", int(velocity.length()))

	# Loop in case AI overshot multiple waypoints in one frame
	while current_distance < WAYPOINT_REACH_DISTANCE or current_distance > last_distance_to_waypoint:
		print("AI: REACHED waypoint ", current_waypoint_index, " at distance ", int(current_distance))
		advance_to_next_waypoint()
		
		if waypoints.size() == 0:
			break
		
		waypoint = waypoints[current_waypoint_index]
		current_distance = global_position.distance_to(waypoint.global_position)
		last_distance_to_waypoint = INF
		
		# Reset overtake when reaching waypoint
		if overtake_timer <= 0.0:
			overtake_offset = lerp(overtake_offset, 0.0, 0.3)

	# Update last distance for next frame
	last_distance_to_waypoint = current_distance

func advance_to_next_waypoint() -> void:
	var old_idx = current_waypoint_index
	current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
	print("AI: Advanced from WP", old_idx, " to WP", current_waypoint_index)

# -----------------------------
# AI SHIFTING LOGIC
# -----------------------------
func ai_shifting_logic() -> void:
	if shift_timer > 0.0:
		return
	
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var forward_speed: float = velocity.dot(forward)
	
	# Shift up at 85% of redline
	if rpm > REDLINE_RPM * 0.85 and gear < MAX_GEAR:
		gear += 1
		shift_timer = SHIFT_COOLDOWN
		if gear != 0:
			var new_ratio: float = GEAR_RATIOS[gear + 1]
			rpm = max(abs(forward_speed) * new_ratio / wheel_scale, IDLE_RPM)
	
	# Shift down if RPM too low
	elif rpm < IDLE_RPM * 2.0 and gear > 1 and abs(forward_speed) > 10.0:
		gear -= 1
		shift_timer = SHIFT_COOLDOWN
		if gear != 0:
			var new_ratio: float = GEAR_RATIOS[gear + 1]
			rpm = max(abs(forward_speed) * new_ratio / wheel_scale, IDLE_RPM)

# -----------------------------
# RUBBERBANDING - FIXED
# -----------------------------
func apply_rubberbanding() -> void:
	# Find player car - need to get the actual car from the wrapper
	var player_node = get_tree().get_first_node_in_group("local_player")
	
	if not player_node:
		# Try alternative - look for player group
		player_node = get_tree().get_first_node_in_group("player")
	
	if not player_node:
		rubberband_multiplier = 1.0
		return
	
	# If it's a wrapper node, get the actual car
	var player_car = player_node
	if player_node.get_script() and player_node.get_script().get_path().get_file() == "MultiplayerCarWrapper.gd":
		# The wrapper's parent is the actual car
		if player_node.has_method("get_parent"):
			player_car = player_node.get_parent()
	
	# Safety check - make sure we have a Node2D with global_position
	if not player_car is Node2D:
		rubberband_multiplier = 1.0
		return
	
	distance_to_player = global_position.distance_to(player_car.global_position)
	
	# If AI is far behind, boost them
	if distance_to_player > 500.0:
		rubberband_multiplier = lerp(rubberband_multiplier, 1.15, 0.01)
	# If AI is far ahead, slow them down
	elif distance_to_player < 200.0:
		rubberband_multiplier = lerp(rubberband_multiplier, 0.90, 0.01)
	else:
		rubberband_multiplier = lerp(rubberband_multiplier, 1.0, 0.02)
	
	rubberband_multiplier = clamp(rubberband_multiplier, 0.85, 1.20)

# -----------------------------
# MISTAKES
# -----------------------------
func make_mistake() -> void:
	var mistake_type = randi() % 3
	match mistake_type:
		0:  # Late brake
			ai_brake = false
		1:  # Oversteer
			ai_turn_input *= 1.5
		2:  # Miss apex
			overtake_offset = randf_range(-0.5, 0.5)

# -----------------------------
# ENGINE SOUND
# -----------------------------
func update_engine_sound(delta: float) -> void:
	if !engine_sound:
		return
	
	var rpm_normalized: float = (rpm - IDLE_RPM) / RPM_RANGE
	var target_pitch: float = lerp(min_pitch, max_pitch, rpm_normalized)
	current_pitch = lerp(current_pitch, target_pitch, pitch_smoothing * delta)
	engine_sound.pitch_scale = current_pitch
	
	engine_sound.volume_db = BASE_VOLUME + (THROTTLE_VOLUME_BOOST if (ai_throttle and gear > 0) else 0.0)

# -----------------------------
# DEBUG VISUALIZATION
# -----------------------------
func _draw() -> void:
	if OS.is_debug_build() and not waypoints.is_empty():
		var target = waypoints[current_waypoint_index]
		var local_target = to_local(target.global_position)
		
		# Draw line to target
		draw_line(Vector2.ZERO, local_target, Color.CYAN, 2.0)
		
		# Draw detection radius
		draw_arc(Vector2.ZERO, DETECTION_RADIUS, 0, TAU, 32, Color(1, 1, 0, 0.3))
		
		# Draw overtake offset indicator
		if overtake_offset != 0.0:
			var offset_indicator = Vector2(overtake_offset * 20, -40)
			draw_circle(offset_indicator, 5, Color.ORANGE)
		
		# Draw waypoint reach distance (bigger circle now)
		draw_circle(to_local(target.global_position), WAYPOINT_REACH_DISTANCE, Color(0, 1, 0, 0.2))

func _physics_process(_delta: float) -> void:
	queue_redraw()  # Update debug visualization
