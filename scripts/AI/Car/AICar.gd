# ai_racer.gd
extends RigidBody2D
class_name AIRacer

# -----------------------------
# AI Navigation
# -----------------------------
var track: Node2D
var waypoints: Array = []
var current_waypoint_index: int = 0
const WAYPOINT_REACH_DISTANCE: float = 80.0
var last_distance_to_waypoint: float = INF

var overtake_cooldown := 0.0
const OVERTAKE_COOLDOWN_TIME := 1.0

# AI Behavior
@export var difficulty: String = "medium"
var base_skill: float = 1.0
var reaction_delay: float = 0.0
var mistake_chance: float = 0.0
var aggression: float = 0.5

# Overtaking
var overtake_offset: float = 0.0
var overtake_timer: float = 0.0
const OVERTAKE_DISTANCE: float = 100.0
const DETECTION_RADIUS: float = 80.0
const CAR_WIDTH: float = 32.0

enum OvertakeState { NONE, COMMIT, REJOIN }

var overtake_state: int = OvertakeState.NONE
var overtake_target: Node2D = null
var overtake_side: float = 0.0 # -1 = left, +1 = right
const OVERTAKE_LATERAL_DISTANCE := 42.0
const SAFE_REJOIN_DISTANCE := 55.0

# Rubberbanding
var target_position: int = 5
var distance_to_player: float = 0.0
var rubberband_multiplier: float = 1.0

# Engine + Transmission
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

# Car handling
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

# AI Input simulation
var ai_throttle: bool = false
var ai_brake: bool = false
var ai_turn_input: float = 0.0

# Initialization flag
var initialized: bool = false

# Stuck detection
var stuck_timer: float = 0.0
var last_position: Vector2 = Vector2.ZERO
var stuck_threshold: float = 2.0  # If moved less than this in 1 second, we're stuck
const STUCK_CHECK_INTERVAL: float = 1.0
var is_stuck: bool = false
var stuck_recovery_timer: float = 0.0
const STUCK_RECOVERY_TIME: float = 2.0

# Engine Sound
@onready var engine_sound: AudioStreamPlayer2D = $EngineSound

@export var min_pitch: float = 0.8
@export var max_pitch: float = 2.5
@export var pitch_smoothing: float = 5.0
const BASE_VOLUME: float = -8.0
const THROTTLE_VOLUME_BOOST: float = 3.0
var current_pitch: float = 1.0

# -----------------------------
# AI Detection / Avoidance Constants
# -----------------------------
const BASE_WALL_DETECT_RADIUS: float = 150.0   # Increased from 120 - see walls earlier
const WALL_AVOID_FORCE: float = 1.5           # Increased from 0.8 - much stronger wall avoidance

const BASE_CAR_DETECT_RADIUS: float = 80.0    # Increased from 55 - see cars earlier  
const OBSTACLE_AVOID_FORCE: float = 1.2       # Increased from 0.7 - stronger car avoidance

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
	# CRITICAL: Configure RigidBody2D physics
	gravity_scale = 0.0  # Disable gravity for top-down racing
	lock_rotation = false  # Allow rotation for steering
	freeze = false  # Ensure not frozen
	
	# Set physics properties
	linear_damp = 0.0  # NO damping - we handle friction manually like player car
	angular_damp = 2.0  # Dampen rotation
	
	# Add to "cars" group for detection
	add_to_group("cars")
	
	current_waypoint_index = 0
	last_distance_to_waypoint = INF
	overtake_offset = 0.0
	overtake_timer = 0.0
	
	# Wait for scene to be ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	var racing_line = get_node_or_null("/root/Scene collection/RacingLine")
	if racing_line:
		load_waypoints_from_node(racing_line)
	else:
		var parent = get_parent()
		if parent and parent.has_node("RacingLine"):
			racing_line = parent.get_node("RacingLine")
			load_waypoints_from_node(racing_line)
		else:
			racing_line = find_node_by_name(get_tree().root, "RacingLine")
			if racing_line:
				load_waypoints_from_node(racing_line)
	
	setup_difficulty()
	gear = 1
	rpm = IDLE_RPM
	
	# Initialize physics state
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	last_position = global_position  # Initialize for stuck detection
	
	# Mark as initialized
	initialized = true
	
	if waypoints.size() > 0:
		print("AI Racer initialized: ", name, " with ", waypoints.size(), " waypoints")
	else:
		print("WARNING: AI Racer ", name, " has NO waypoints - will drive straight!")

func find_node_by_name(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var result = find_node_by_name(child, node_name)
		if result:
			return result
	return null

func load_waypoints_from_node(racing_line: Node) -> void:
	waypoints.clear()
	for child in racing_line.get_children():
		waypoints.append(child)

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
# PHYSICS PROCESS (USE THIS INSTEAD OF _process FOR RIGIDBODY)
# -----------------------------
func _physics_process(delta: float) -> void:
	if not initialized:
		return
		
	shift_timer -= delta
	overtake_timer -= delta
	
	# -----------------------------
	# STUCK DETECTION
	# -----------------------------
	stuck_timer += delta
	if stuck_timer >= STUCK_CHECK_INTERVAL:
		var distance_moved = global_position.distance_to(last_position)
		if distance_moved < stuck_threshold and ai_throttle:
			# We're stuck!
			is_stuck = true
			stuck_recovery_timer = STUCK_RECOVERY_TIME
		else:
			is_stuck = false
		
		last_position = global_position
		stuck_timer = 0.0
	
	# Handle stuck recovery
	if stuck_recovery_timer > 0.0:
		stuck_recovery_timer -= delta
		is_stuck = true

	if waypoints.is_empty():
		ai_throttle = true
		ai_brake = false
		ai_turn_input = 0.0
	else:
		ai_navigation_logic(delta)
		apply_rubberbanding()
	
	ai_shifting_logic()

	# -----------------------------
	# Physics & Movement
	# -----------------------------
	var forward: Vector2 = -transform.y
	var right: Vector2 = transform.x

	var forward_speed: float = forward.dot(linear_velocity)
	var lateral_speed: float = right.dot(linear_velocity)
	var abs_speed: float = linear_velocity.length()

	# Calculate engine force
	var ratio: float = GEAR_RATIOS[gear + 1] if gear != 0 else 1.0
	var engine_force: float = get_torque(rpm) * abs(ratio) * ENGINE_FORCE_MULTIPLIER
	engine_force *= rubberband_multiplier
	
	# Debug every 60 frames (about once per second at 60fps)
	if Engine.get_process_frames() % 60 == 0 and gear > 0:
		var max_speed_this_gear = REDLINE_RPM * wheel_scale / ratio
		print(name, " | Gear: ", gear, " | Speed: ", int(abs_speed), "/", int(max_speed_this_gear), 
			  " | RPM: ", int(rpm), "/", int(REDLINE_RPM), 
			  " | Force: ", int(engine_force), " | Torque: ", get_torque(rpm))

	# Apply forward/backward acceleration
	if gear == 0:
		linear_velocity = linear_velocity.move_toward(Vector2.ZERO, friction * delta)
	elif gear == -1:
		if ai_throttle:
			apply_central_force(-forward * engine_force)
			# Cap reverse speed
			var max_reverse_speed = REDLINE_RPM * wheel_scale / abs(ratio)
			if abs(forward_speed) > max_reverse_speed:
				linear_velocity = forward * -max_reverse_speed
		elif ai_brake:
			linear_velocity = linear_velocity.move_toward(Vector2.ZERO, BRAKE_FORCE * delta)
		else:
			linear_velocity = linear_velocity.move_toward(Vector2.ZERO, friction * delta)
	else:
		if ai_throttle:
			apply_central_force(forward * engine_force)
			# Cap max speed based on current gear (like player car)
			var max_speed = REDLINE_RPM * wheel_scale / ratio
			if forward_speed > max_speed:
				linear_velocity = forward * max_speed
		elif ai_brake:
			linear_velocity = linear_velocity.move_toward(Vector2.ZERO, BRAKE_FORCE * delta)
		else:
			linear_velocity = linear_velocity.move_toward(Vector2.ZERO, friction * delta)

	# -----------------------------
	# Drift / lateral friction
	# -----------------------------
	var drift_factor: float = 0.15
	linear_velocity -= right * lateral_speed * drift_factor
	
	# -----------------------------
	# Air resistance (speed-squared drag) - only when coasting
	# -----------------------------
	if not ai_throttle and abs_speed > 50.0:
		var drag_coefficient: float = 0.002  # Small coefficient for realistic drag
		var drag_force: float = drag_coefficient * abs_speed * abs_speed
		var drag_direction: Vector2 = -linear_velocity.normalized()
		apply_central_force(drag_direction * drag_force)

	# -----------------------------
	# Steering / Angular velocity
	# -----------------------------
	if abs(forward_speed) > 10:
		var speed_factor: float = clamp(abs(forward_speed) / 400.0, 0.0, 1.0)
		var turn_strength: float = ai_turn_input * 3.0 * speed_factor
		angular_velocity = turn_strength
	else:
		angular_velocity = 0.0

	# -----------------------------
	# RPM calculation
	# -----------------------------
	if gear == 0:
		rpm = move_toward(rpm, REDLINE_RPM if ai_throttle else IDLE_RPM, (5000.0 if ai_throttle else 2000.0) * delta)
	else:
		var current_ratio: float = abs(GEAR_RATIOS[gear + 1])
		rpm = max(abs(forward_speed) * current_ratio / wheel_scale, IDLE_RPM)

	rpm += randf_range(-30.0, 30.0)
	rpm = clamp(rpm, IDLE_RPM - 50.0, REDLINE_RPM + 50.0)

# -----------------------------
# SEPARATE _process FOR NON-PHYSICS UPDATES
# -----------------------------
func _process(delta: float) -> void:
	update_engine_sound(delta)


func ai_navigation_logic(delta: float) -> void:
	overtake_cooldown = max(0.0, overtake_cooldown - delta)
	if waypoints.is_empty():
		return

	# -----------------------------
	# STUCK RECOVERY - REVERSE AND TURN
	# -----------------------------
	if is_stuck:
		ai_throttle = false
		ai_brake = false
		# Shift to reverse if not already
		if gear > -1:
			gear = -1
			shift_timer = SHIFT_COOLDOWN
		
		# Reverse and turn away from obstacle
		ai_throttle = true
		ai_turn_input = randf_range(-1.0, 1.0)  # Random turn direction
		return  # Skip normal navigation while stuck

	var target_wp: Node2D = waypoints[current_waypoint_index]

	# -------------------------------------------------
	# BASE WAYPOINT + RACING LINE DIRECTION
	# -------------------------------------------------
	var wp_position: Vector2 = target_wp.global_position

	var to_next_wp := Vector2.ZERO
	var next_wp_index := (current_waypoint_index + 1) % waypoints.size()

	if waypoints.size() > 1:
		to_next_wp = (waypoints[next_wp_index].global_position - wp_position).normalized()
	else:
		to_next_wp = (wp_position - global_position).normalized()

	var perpendicular := Vector2(-to_next_wp.y, to_next_wp.x)

	# -------------------------------------------------
	# LATERAL OFFSET / OVERTAKE LOGIC
	# -------------------------------------------------
	var lateral_offset := 0.0

	if overtake_state == OvertakeState.COMMIT:
		lateral_offset = overtake_side * 42.0

	elif overtake_state == OvertakeState.REJOIN:
		lateral_offset = lerp(overtake_side * 42.0, 0.0, delta * 2.5)

	else:
		# normal racing-line variation
		var car_id_hash = hash(get_instance_id())
		lateral_offset = (car_id_hash % 5 - 2) * 15.0

	wp_position += perpendicular * lateral_offset

	# -------------------------------------------------
	# STEERING TOWARDS TARGET
	# -------------------------------------------------
	var dir: Vector2 = (wp_position - global_position).normalized()
	var target_angle := dir.angle() + PI / 2
	var angle_diff := angle_difference(global_rotation, target_angle)

	ai_turn_input = clamp(angle_diff * 2.0, -1.0, 1.0)

	# -------------------------------------------------
	# THROTTLE / BRAKE
	# -------------------------------------------------
	var distance_to_wp = global_position.distance_to(target_wp.global_position)
	
	if distance_to_wp > WAYPOINT_REACH_DISTANCE:
		ai_throttle = true
		ai_brake = false
	else:
		ai_throttle = false
		ai_brake = false

	# -------------------------------------------------
	# ENVIRONMENT AWARENESS (STRONGER AVOIDANCE)
	# -------------------------------------------------
	detect_walls_with_raycasts(delta)
	avoid_other_cars(delta)

	# -------------------------------------------------
	# OVERTAKE COMPLETION CHECK
	# -------------------------------------------------
	if overtake_state == OvertakeState.COMMIT and overtake_target:
		if not is_instance_valid(overtake_target):
			overtake_state = OvertakeState.REJOIN
			overtake_target = null
		else:
			var forward := Vector2.UP.rotated(global_rotation)
			var to_target := overtake_target.global_position - global_position
			var forward_gap := to_target.dot(forward)

			# target safely behind us
			if forward_gap < -55.0:
				overtake_state = OvertakeState.REJOIN
				overtake_cooldown = OVERTAKE_COOLDOWN_TIME

	if overtake_state == OvertakeState.REJOIN:
		if abs(lateral_offset) < 3.0:
			overtake_state = OvertakeState.NONE
			overtake_target = null

	# -------------------------------------------------
	# WAYPOINT PROGRESSION
	# -------------------------------------------------
	check_waypoint_reached(target_wp, distance_to_wp)


# Raycast-based wall detection for better accuracy
func detect_walls_with_raycasts(delta: float) -> void:
	var space_state = get_world_2d().direct_space_state
	var forward := Vector2.UP.rotated(global_rotation)
	var wall_detect_distance := BASE_WALL_DETECT_RADIUS

	var ray_angles = [0.0, -30.0, 30.0, -60.0, 60.0]
	var ray_weights = [1.5, 1.2, 1.2, 0.6, 0.6]

	var wall_avoid_dir := Vector2.ZERO
	var wall_detected := false

	for i in range(ray_angles.size()):
		var angle = deg_to_rad(ray_angles[i])
		var ray_dir = forward.rotated(angle)
		var ray_end = global_position + ray_dir * wall_detect_distance

		var query = PhysicsRayQueryParameters2D.create(global_position, ray_end)
		query.exclude = [self]
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.collision_mask = 0b1111

		var result = space_state.intersect_ray(query)
		if not result:
			continue

		var hit = result.collider
		if hit is AIRacer or hit is CharacterBody2D:
			continue

		var distance = global_position.distance_to(result.position)
		var proximity = 1.0 - (distance / wall_detect_distance)
		proximity = clamp(proximity, 0.0, 1.0)

		wall_detected = true
		wall_avoid_dir += (global_position - result.position).normalized() * proximity * ray_weights[i]

	if not wall_detected or wall_avoid_dir == Vector2.ZERO:
		return

	wall_avoid_dir = wall_avoid_dir.normalized()
	var avoid_angle = wall_avoid_dir.angle() + PI / 2
	var angle_diff = angle_difference(global_rotation, avoid_angle)

	# Wall avoidance always strong - safety first!
	var wall_strength := WALL_AVOID_FORCE
	if overtake_state != OvertakeState.NONE:
		wall_strength *= 0.7  # Still reduce during overtake but not as much

	ai_turn_input = lerp(
		ai_turn_input,
		clamp(angle_diff * 2.5, -1.0, 1.0),  # Increased multiplier for sharper turns
		wall_strength
	)


# Separate car detection (smaller radius)
func avoid_other_cars(delta: float) -> void:
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var right: Vector2 = Vector2.RIGHT.rotated(global_rotation)
	var my_forward_speed: float = forward.dot(linear_velocity)
	var my_position: Vector2 = global_position

	var avoid_dir: Vector2 = Vector2.ZERO
	var nearby_cars: int = 0
	var closest_distance: float = 999999.0

	# Iterate over all AI and player cars in the scene
	for car in get_tree().get_nodes_in_group("cars"):
		if car == self:
			continue
		if not is_instance_valid(car):
			continue
		if not car is Node2D:
			continue

		var other_pos: Vector2 = car.global_position
		var to_car: Vector2 = other_pos - my_position
		var distance: float = to_car.length()
		if distance <= 1.0:
			continue

		closest_distance = min(closest_distance, distance)

		var to_car_norm: Vector2 = to_car.normalized()
		var forward_dot: float = forward.dot(to_car_norm)
		
		# Consider cars both ahead AND to the sides
		if forward_dot < 0.3:  # Widened from 0.6 to detect cars beside us
			continue

		var other_velocity: Vector2 = Vector2.ZERO
		if "linear_velocity" in car:
			other_velocity = car.linear_velocity
		elif "velocity" in car:
			other_velocity = car.velocity
			
		var other_forward_speed: float = forward.dot(other_velocity)
		var relative_speed: float = my_forward_speed - other_forward_speed

		# -------------------------
		# SLOW DOWN IF TOO CLOSE
		# -------------------------
		if distance < 40.0 and forward_dot > 0.7:
			ai_throttle = false
			ai_brake = true

		# -------------------------
		# OVERTAKE START
		# -------------------------
		if (
			overtake_state == OvertakeState.NONE
			and overtake_cooldown <= 0.0
			and relative_speed > 10.0
			and distance < OVERTAKE_DISTANCE
			and distance > 30.0  # Don't overtake if too close - avoid first
		):
			overtake_state = OvertakeState.COMMIT
			overtake_target = car
			overtake_side = sign(randf() - 0.5)
			if overtake_side == 0.0:
				overtake_side = 1.0
			overtake_timer = 1.2
			return  # commit overtake this frame

		# -------------------------
		# NORMAL AVOIDANCE - STRONGER
		# -------------------------
		var proximity: float = 1.0 - (distance / BASE_CAR_DETECT_RADIUS)
		proximity = clamp(proximity, 0.0, 1.0)
		var closing_speed: float = max(0.0, relative_speed / 30.0)  # More sensitive
		proximity *= (1.0 + closing_speed)  # Stronger proximity multiplier

		# Avoid the car laterally
		avoid_dir -= to_car_norm * proximity * 2.0  # 2x stronger avoidance
		nearby_cars += 1

	# -------------------------
	# APPLY STEERING
	# -------------------------
	if avoid_dir != Vector2.ZERO and nearby_cars > 0:
		avoid_dir = avoid_dir.normalized()
		var avoid_angle: float = avoid_dir.angle() + PI / 2
		var angle_diff: float = angle_difference(global_rotation, avoid_angle)

		# Strong steering to avoid cars
		var steering_strength: float = OBSTACLE_AVOID_FORCE
		if overtake_state != OvertakeState.NONE:
			steering_strength *= 0.6  # Reduced less during overtake

		ai_turn_input = lerp(
			ai_turn_input,
			clamp(angle_diff * 3.0, -1.0, 1.0),  # Increased from 2.0 - sharper avoidance turns
			steering_strength
		)


func check_waypoint_reached(waypoint: Node2D, distance: float) -> void:
	if distance <= WAYPOINT_REACH_DISTANCE:
		# Progress to next waypoint
		var old_index = current_waypoint_index
		current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
		last_distance_to_waypoint = INF
	else:
		# Update last distance to detect if we're getting closer
		if distance < last_distance_to_waypoint:
			last_distance_to_waypoint = distance
		elif distance > last_distance_to_waypoint + 50.0:
			# We're moving away from waypoint - might have missed it
			current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
			last_distance_to_waypoint = INF

func ai_shifting_logic() -> void:
	if shift_timer > 0.0:
		return
	
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var forward_speed: float = linear_velocity.dot(forward)
	var abs_speed: float = abs(forward_speed)
	
	# Shift at 83% of redline - achievable with current engine power
	# At 162 speed in gear 2: 162 * 2.10 / 0.0525 = 6480 RPM
	var shift_up_rpm = REDLINE_RPM * 0.83  # 6474 RPM
	var shift_down_rpm = IDLE_RPM * 2.0     # 1800 RPM
	
	# SHIFT UP
	if rpm > shift_up_rpm and gear < MAX_GEAR:
		var old_gear = gear
		gear += 1
		shift_timer = SHIFT_COOLDOWN
		# Recalculate RPM for new gear immediately (like player car does)
		if gear != 0:
			var new_ratio: float = GEAR_RATIOS[gear + 1]
			rpm = max(abs_speed * new_ratio / wheel_scale, IDLE_RPM)
		print(name, " shifted UP from ", old_gear, " to ", gear, " at speed ", abs_speed, " | Old RPM: ", int(shift_up_rpm), " New RPM: ", int(rpm))
	
	# SHIFT DOWN - prevent money shifting
	elif gear > 1:
		var target_gear: int = gear - 1
		if target_gear != 0:
			# Calculate what RPM would be in lower gear
			var new_ratio: float = GEAR_RATIOS[target_gear + 1]
			var predicted_rpm: float = abs_speed * new_ratio / wheel_scale
			
			# Only downshift if it won't over-rev AND we're below downshift threshold
			if predicted_rpm <= REDLINE_RPM and rpm < shift_down_rpm:
				gear = target_gear
				shift_timer = SHIFT_COOLDOWN
				rpm = max(predicted_rpm, IDLE_RPM)
				print(name, " shifted DOWN to gear ", gear, " at speed ", abs_speed, " RPM: ", rpm)

# -----------------------------
# RUBBERBANDING
# -----------------------------
func apply_rubberbanding() -> void:
	var player_node = get_tree().get_first_node_in_group("local_player")
	if not player_node:
		player_node = get_tree().get_first_node_in_group("player")
	if not player_node:
		rubberband_multiplier = 1.0
		return
	
	var player_car = player_node
	if player_node.get_script() and player_node.get_script().get_path().get_file() == "MultiplayerCarWrapper.gd":
		if player_node.has_method("get_parent"):
			player_car = player_node.get_parent()
	
	if not player_car is Node2D:
		rubberband_multiplier = 1.0
		return
	
	distance_to_player = global_position.distance_to(player_car.global_position)
	if distance_to_player > 500.0:
		rubberband_multiplier = lerp(rubberband_multiplier, 1.15, 0.01)
	elif distance_to_player < 200.0:
		rubberband_multiplier = lerp(rubberband_multiplier, 0.90, 0.01)
	else:
		rubberband_multiplier = lerp(rubberband_multiplier, 1.0, 0.02)
	
	rubberband_multiplier = clamp(rubberband_multiplier, 0.85, 1.20)

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
