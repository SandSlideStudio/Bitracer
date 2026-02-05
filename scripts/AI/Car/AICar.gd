# ai_racer.gd
extends StaticBody2D
class_name AIRacer

# -----------------------------
# AI Navigation
# -----------------------------
var track: Node2D
var waypoints: Array = []
var current_waypoint_index: int = 0
const WAYPOINT_REACH_DISTANCE: float = 80.0
var last_distance_to_waypoint: float = INF

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

var velocity: Vector2 = Vector2.ZERO

# AI Input simulation
var ai_throttle: bool = false
var ai_brake: bool = false
var ai_turn_input: float = 0.0

# Engine Sound
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
	current_waypoint_index = 0
	last_distance_to_waypoint = INF
	overtake_offset = 0.0
	overtake_timer = 0.0
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

func find_node_by_name(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var result = find_node_by_name(child, node_name)
		if result:
			return result
	return null

func load_waypoints_from_node(racing_line: Node) -> void:
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
# MAIN PROCESS
# -----------------------------
func _process(delta: float) -> void:
	shift_timer -= delta
	overtake_timer -= delta
	
	if waypoints.is_empty():
		ai_throttle = true
		ai_brake = false
		ai_turn_input = 0.0
		ai_shifting_logic()
	else:
		ai_navigation_logic(delta)
		ai_shifting_logic()
		apply_rubberbanding()
	
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var forward_speed: float = velocity.dot(forward)
	
	var ratio: float = GEAR_RATIOS[gear + 1] if gear != 0 else 1.0
	var abs_speed: float = abs(forward_speed)
	
	if gear == 0:
		rpm = move_toward(rpm, REDLINE_RPM if ai_throttle else IDLE_RPM, (5000.0 if ai_throttle else 2000.0) * delta)
	else:
		rpm = max(abs_speed * abs(ratio) / wheel_scale, IDLE_RPM)
	
	rpm += randf_range(-30.0, 30.0)
	rpm = clamp(rpm, IDLE_RPM - 50.0, REDLINE_RPM + 50.0)
	
	var engine_force: float = get_torque(rpm) * abs(ratio) * ENGINE_FORCE_MULTIPLIER
	engine_force *= rubberband_multiplier
	
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
	
	if ai_turn_input != 0.0 and abs_speed > 1.0 and gear != 0:
		forward_speed -= sign(forward_speed) * abs_speed * TURN_DRAG_FACTOR * abs(ai_turn_input) * delta
	
	velocity = forward * forward_speed
	
	if abs_speed > 0.1:
		var speed_factor: float = clamp(abs_speed * ratio / (REDLINE_RPM * wheel_scale), 0.0, 1.0)
		var current_turn_speed: float = lerp(max_turn_speed, min_turn_speed, speed_factor * SPEED_TURN_LERP)
		if ai_brake and forward_speed > 0.0:
			current_turn_speed *= BRAKE_TURN_FACTOR
		var steering_factor: float = -1.0 if forward_speed < 0.0 else 1.0
		global_rotation += deg_to_rad(ai_turn_input * current_turn_speed * steering_factor * delta)
	
	var collision: KinematicCollision2D = move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(collision.get_normal()) * 0.5
	
	update_engine_sound(delta)

# -----------------------------
# AI NAVIGATION LOGIC WITH OBSTACLE AVOIDANCE
# -----------------------------
const OBSTACLE_DETECT_RADIUS: float = 60.0
const OBSTACLE_AVOID_FORCE: float = 1.0

func ai_navigation_logic(delta: float) -> void:
	if waypoints.is_empty():
		return
	
	var target_wp = waypoints[current_waypoint_index]
	
	# 1️⃣ Steering toward waypoint
	var dir: Vector2 = (target_wp.global_position - global_position).normalized()
	var target_angle = dir.angle() + PI / 2
	var angle_diff = angle_difference(global_rotation, target_angle)
	ai_turn_input = clamp(angle_diff * 2.0, -1.0, 1.0)
	
	# 2️⃣ Throttle/brake logic
	if global_position.distance_to(target_wp.global_position) > WAYPOINT_REACH_DISTANCE:
		ai_throttle = true
		ai_brake = false
	else:
		ai_throttle = false
		ai_brake = false
	
	# 3️⃣ Obstacle avoidance
	avoid_obstacles(delta)
	
	# 4️⃣ Waypoint reached
	check_waypoint_reached(target_wp)

func avoid_obstacles(delta: float) -> void:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = OBSTACLE_DETECT_RADIUS
	query.shape = shape
	query.transform = Transform2D(global_rotation, global_position)
	query.collision_mask = collision_mask
	
	var results = space_state.intersect_shape(query, 10)
	var avoid_dir: Vector2 = Vector2.ZERO
	
	for result in results:
		var body = result.collider
		if body == self:
			continue
		if not (body is StaticBody2D or body is CharacterBody2D):
			continue
		
		var to_body = body.global_position - global_position
		var forward = Vector2.UP.rotated(global_rotation)
		if forward.dot(to_body.normalized()) < 0.0:
			continue
		
		avoid_dir -= to_body.normalized()
		
		if to_body.length() < OBSTACLE_DETECT_RADIUS * 0.5:
			ai_throttle = false
			ai_brake = true
	
	if avoid_dir != Vector2.ZERO:
		var avoid_angle = avoid_dir.angle() + PI / 2
		var angle_diff = angle_difference(global_rotation, avoid_angle)
		ai_turn_input = clamp(ai_turn_input + angle_diff * OBSTACLE_AVOID_FORCE, -1.0, 1.0)

func check_waypoint_reached(waypoint: Node2D) -> void:
	if global_position.distance_to(waypoint.global_position) <= WAYPOINT_REACH_DISTANCE:
		current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()

func ai_shifting_logic() -> void:
	if shift_timer > 0.0:
		return
	
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var forward_speed: float = velocity.dot(forward)
	
	if rpm > REDLINE_RPM * 0.85 and gear < MAX_GEAR:
		gear += 1
		shift_timer = SHIFT_COOLDOWN
		if gear != 0:
			rpm = max(abs(forward_speed) * GEAR_RATIOS[gear + 1] / wheel_scale, IDLE_RPM)
	elif rpm < IDLE_RPM * 2.0 and gear > 1 and abs(forward_speed) > 10.0:
		gear -= 1
		shift_timer = SHIFT_COOLDOWN
		if gear != 0:
			rpm = max(abs(forward_speed) * GEAR_RATIOS[gear + 1] / wheel_scale, IDLE_RPM)

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
