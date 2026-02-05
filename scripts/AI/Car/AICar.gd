# ai_racer.gd
extends StaticBody2D
class_name AIRacer

# -----------------------------
# AI Navigation
# -----------------------------
var track: Node2D
var waypoints: Array = []
var current_waypoint_index: int = 0
const WAYPOINT_REACH_DISTANCE: float = 50.0
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
const DETECTION_RADIUS: float = 150.0
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
	# Find track and waypoints
	track = get_tree().get_first_node_in_group("track")
	if track and track.has_node("RacingLine"):
		for child in track.get_node("RacingLine").get_children():
			waypoints.append(child)
	
	# Set difficulty parameters
	setup_difficulty()
	
	# Start in 1st gear
	gear = 1

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
	
	if waypoints.is_empty():
		return
	
	# AI Decision Making
	ai_navigation_logic(delta)
	ai_shifting_logic()
	
	# Apply rubberbanding
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
	
	# Calculate target position with overtake offset
	var waypoint_pos: Vector2 = target_waypoint.global_position
	var target_pos: Vector2 = waypoint_pos
	
	# Apply overtake offset (perpendicular to direction)
	if overtake_offset != 0.0:
		var next_idx = (current_waypoint_index + 1) % waypoints.size()
		var next_waypoint = waypoints[next_idx]
		var direction = (next_waypoint.global_position - waypoint_pos).normalized()
		var perpendicular = Vector2(-direction.y, direction.x)
		target_pos += perpendicular * overtake_offset * (CAR_WIDTH * 1.5)
	
	# Detect cars ahead for overtaking
	detect_and_overtake()
	
	# Calculate steering
	var direction_to_target = (target_pos - global_position).normalized()
	var target_angle = direction_to_target.angle() + PI / 2  # Adjust for car's forward being UP
	var angle_diff = angle_difference(global_rotation, target_angle)
	
	# Smooth steering with skill-based precision
	var steering_strength = clamp(angle_diff * 2.0, -1.0, 1.0)
	ai_turn_input = lerp(ai_turn_input, steering_strength * base_skill, 10.0 * delta)
	
	# Add slight random wobble for realism
	if randf() < 0.1:
		ai_turn_input += randf_range(-0.05, 0.05) * (1.0 - base_skill)
	
	# Determine throttle/brake based on upcoming turn
	var next_idx = (current_waypoint_index + 1) % waypoints.size()
	var next_waypoint = waypoints[next_idx]
	var turn_sharpness = calculate_turn_sharpness(target_waypoint, next_waypoint)
	
	# Get waypoint speed hint if available
	var target_speed_mult = 1.0
	if target_waypoint.has_method("get") and target_waypoint.get("speed_multiplier"):
		target_speed_mult = target_waypoint.speed_multiplier
	
	# Brake for sharp turns
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
		var next_idx = (current_waypoint_index + 1) % waypoints.size()
		var next_waypoint = waypoints[next_idx]
		var to_next = (next_waypoint.global_position - global_position).normalized()
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

func check_waypoint_reached(waypoint: Node2D) -> void:
	var current_distance = global_position.distance_to(waypoint.global_position)
	
	# Check if within reach OR started moving away
	if current_distance < WAYPOINT_REACH_DISTANCE or current_distance > last_distance_to_waypoint:
		advance_to_next_waypoint()
		last_distance_to_waypoint = INF
		
		# Reset overtake when reaching waypoint
		if overtake_timer <= 0.0:
			overtake_offset = lerp(overtake_offset, 0.0, 0.3)
	else:
		last_distance_to_waypoint = current_distance

func advance_to_next_waypoint() -> void:
	current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()

# -----------------------------
# AI SHIFTING LOGIC
# -----------------------------
func ai_shifting_logic() -> void:
	if shift_timer > 0.0:
		return
	
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var forward_speed: float = velocity.dot(forward)
	
	# Shift up near redline
	if rpm > REDLINE_RPM * 0.95 and gear < MAX_GEAR:
		gear += 1
		shift_timer = SHIFT_COOLDOWN
		if gear != 0:
			var new_ratio: float = GEAR_RATIOS[gear + 1]
			rpm = max(abs(forward_speed) * new_ratio / wheel_scale, IDLE_RPM)
	
	# Shift down if RPM too low
	elif rpm < IDLE_RPM * 1.5 and gear > 1:
		gear -= 1
		shift_timer = SHIFT_COOLDOWN
		if gear != 0:
			var new_ratio: float = GEAR_RATIOS[gear + 1]
			rpm = max(abs(forward_speed) * new_ratio / wheel_scale, IDLE_RPM)

# -----------------------------
# RUBBERBANDING
# -----------------------------
func apply_rubberbanding() -> void:
	# Find player (assuming player is in group "player")
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		rubberband_multiplier = 1.0
		return
	
	distance_to_player = global_position.distance_to(player.global_position)
	
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
# DEBUG VISUALIZATION (Optional)
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

func _physics_process(_delta: float) -> void:
	queue_redraw()  # Update debug visualization
