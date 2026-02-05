extends RigidBody2D

# -----------------------------
# Rally Car Physics
# -----------------------------
@export var accel := 800.0
@export var max_speed := 400.0
@export var steering := 3.0  # Further reduced
@export var drift_factor := 0.15
@export var linear_friction := 2.0

# -----------------------------
# Handbrake Settings
# -----------------------------
@export var handbrake_drift_factor := 0.92  # Reduced - still allows some forward motion
@export var handbrake_brake_force := 250.0  # Reduced to maintain momentum
@export var handbrake_steering_multiplier := 1.3  # Reduced from boost
@export var handbrake_max_angular_velocity := 2.5  # NEW: Maximum rotation speed during handbrake
@export var handbrake_angular_acceleration := 8.0  # NEW: How fast rotation builds up
@export var wheelspin_duration := 0.6
@export var wheelspin_drift_factor := 0.88
@export var traction_recovery_rate := 2.0

# Handbrake state
var handbrake_active: bool = false
var handbrake_just_released: bool = false
var wheelspin_timer: float = 0.0
var current_traction: float = 1.0

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
const GEAR_MAX_SPEEDS: Array[float] = [100.0, 999999.0, 80.0, 130.0, 180.0, 250.0, 320.0, 400.0]
const ENGINE_FORCE_MULTIPLIER: float = 85.0
const BRAKE_FORCE: float = 600.0

# -----------------------------
# Dirt Particles
# -----------------------------
@onready var dirt_particles1: CPUParticles2D = $Dirt_particles1
@onready var dirt_particles2: CPUParticles2D = $Dirt_particles2
const PARTICLE_SPEED_THRESHOLD: float = 50.0
const DRIFT_THRESHOLD: float = 30.0

# -----------------------------
# UI References
# -----------------------------
@onready var rpm_label: Label = $CanvasLayer/Control/VBoxContainer/RPMlabel
@onready var gear_label: Label = $CanvasLayer/Control/VBoxContainer/GearLabel
@onready var speed_label: Label = $CanvasLayer/Control/VBoxContainer/SpeedLabel
@onready var engine_sound: AudioStreamPlayer2D = $EngineSound

# -----------------------------
# Engine Sound Settings
# -----------------------------
@export var min_pitch: float = 0.8
@export var max_pitch: float = 2.5
@export var pitch_smoothing: float = 5.0
const BASE_VOLUME: float = -8.0
const THROTTLE_VOLUME_BOOST: float = 3.0
var current_pitch: float = 1.0

var throttle_pressed: bool = false
var brake_pressed: bool = false
var handbrake_pressed: bool = false

var ui_update_timer: float = 0.0
const UI_UPDATE_INTERVAL: float = 0.033

const COLOR_GREEN: Color = Color.GREEN
const COLOR_YELLOW: Color = Color.YELLOW
const COLOR_RED: Color = Color.RED
const COLOR_WHITE: Color = Color.WHITE
const COLOR_ORANGE: Color = Color.ORANGE

# DEBUG
var debug_timer: float = 0.0

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
func _ready():
	gravity_scale = 0
	linear_damp = 0
	angular_damp = 0
	
	if rpm_label:
		rpm_label.text = str(int(IDLE_RPM))
	if gear_label:
		gear_label.text = "N"
	if speed_label:
		speed_label.text = "0 km/h"
	
	# Initialize particles
	if dirt_particles1:
		dirt_particles1.position = Vector2(-10, 10)
		dirt_particles1.emitting = false
		dirt_particles1.amount = 50
		dirt_particles1.lifetime = 1.0
		dirt_particles1.one_shot = false
		dirt_particles1.explosiveness = 0.0
		dirt_particles1.visible = true
		dirt_particles1.modulate = Color.WHITE
		dirt_particles1.direction = Vector2(0, 1)
		dirt_particles1.spread = 15.0
		dirt_particles1.gravity = Vector2(0, 0)
		dirt_particles1.initial_velocity_min = 50.0
		dirt_particles1.initial_velocity_max = 100.0
		dirt_particles1.scale_amount_min = 2.0
		dirt_particles1.scale_amount_max = 4.0
		dirt_particles1.color = Color(0.6, 0.4, 0.2, 1.0)
	
	if dirt_particles2:
		dirt_particles2.position = Vector2(10, 10)
		dirt_particles2.emitting = false
		dirt_particles2.amount = 50
		dirt_particles2.lifetime = 1.0
		dirt_particles2.one_shot = false
		dirt_particles2.explosiveness = 0.0
		dirt_particles2.visible = true
		dirt_particles2.modulate = Color.WHITE
		dirt_particles2.direction = Vector2(0, 1)
		dirt_particles2.spread = 15.0
		dirt_particles2.gravity = Vector2(0, 0)
		dirt_particles2.initial_velocity_min = 50.0
		dirt_particles2.initial_velocity_max = 100.0
		dirt_particles2.scale_amount_min = 2.0
		dirt_particles2.scale_amount_max = 4.0
		dirt_particles2.color = Color(0.6, 0.4, 0.2, 1.0)

func _physics_process(delta):
	shift_timer -= delta
	debug_timer += delta
	
	throttle_pressed = Input.is_action_pressed("accelerate")
	brake_pressed = Input.is_action_pressed("brake")
	var was_handbrake_pressed = handbrake_pressed
	handbrake_pressed = Input.is_action_pressed("handbrake")
	
	# Detect handbrake release - ONLY trigger wheelspin if throttle is pressed
	if was_handbrake_pressed and not handbrake_pressed:
		handbrake_just_released = true
		if gear > 0 and throttle_pressed:
			wheelspin_timer = wheelspin_duration
			rpm = min(rpm + 1500.0, REDLINE_RPM)
	
	var steer_input = Input.get_axis("steer_left", "steer_right")
	
	var forward = -transform.y
	var right = transform.x
	
	var forward_speed = forward.dot(linear_velocity)
	var _abs_speed = abs(forward_speed)
	var current_speed = linear_velocity.length()
	
	var lateral_speed = right.dot(linear_velocity)
	
	# -----------------------------
	# HANDBRAKE & TRACTION SYSTEM
	# -----------------------------
	handbrake_active = handbrake_pressed
	
	# Update wheelspin timer
	if wheelspin_timer > 0.0:
		wheelspin_timer -= delta
		var recovery_progress = 1.0 - (wheelspin_timer / wheelspin_duration)
		current_traction = lerp(0.0, 1.0, recovery_progress * traction_recovery_rate)
	elif handbrake_active:
		current_traction = 0.0
	else:
		current_traction = 1.0
	
	# -----------------------------
	# REALISTIC ANGULAR VELOCITY CONTROL
	# -----------------------------
	if handbrake_active:
		# Gradually build up rotation based on steering input
		if abs(steer_input) > 0.05:
			# Target angular velocity based on speed and steering
			var speed_influence = clamp(current_speed / 150.0, 0.2, 1.0)
			var target_angular = steer_input * handbrake_max_angular_velocity * speed_influence
			
			# Smoothly accelerate towards target
			angular_velocity = move_toward(angular_velocity, target_angular, handbrake_angular_acceleration * delta)
		else:
			# No steering input - slow down rotation
			angular_velocity = move_toward(angular_velocity, 0.0, 15.0 * delta)
	else:
		# Normal damping when not handbraking
		if abs(forward_speed) < 10:
			angular_velocity = move_toward(angular_velocity, 0.0, 10.0 * delta)
	
	# -----------------------------
	# UPDATE DIRT PARTICLES
	# -----------------------------
	var _is_drifting = abs(lateral_speed) > DRIFT_THRESHOLD
	var is_wheel_locked = handbrake_active and current_speed > 20.0
	var is_wheelspinning = wheelspin_timer > 0.0 and current_speed > 20.0 and throttle_pressed
	var should_emit = current_speed > PARTICLE_SPEED_THRESHOLD or is_wheel_locked or is_wheelspinning
	
	if dirt_particles1:
		dirt_particles1.emitting = should_emit
		
		if is_wheel_locked:
			dirt_particles1.amount = 120
			dirt_particles1.initial_velocity_min = 120.0
			dirt_particles1.initial_velocity_max = 200.0
			dirt_particles1.lifetime = 1.5
			dirt_particles1.scale_amount_min = 3.0
			dirt_particles1.scale_amount_max = 6.0
		elif is_wheelspinning:
			dirt_particles1.amount = 100
			dirt_particles1.initial_velocity_min = 100.0
			dirt_particles1.initial_velocity_max = 180.0
			dirt_particles1.lifetime = 1.3
			dirt_particles1.scale_amount_min = 2.5
			dirt_particles1.scale_amount_max = 5.0
		else:
			dirt_particles1.amount = 50
			dirt_particles1.initial_velocity_min = 50.0
			dirt_particles1.initial_velocity_max = 100.0
			dirt_particles1.lifetime = 1.0
			dirt_particles1.scale_amount_min = 2.0
			dirt_particles1.scale_amount_max = 4.0
	
	if dirt_particles2:
		dirt_particles2.emitting = should_emit
		
		if is_wheel_locked:
			dirt_particles2.amount = 120
			dirt_particles2.initial_velocity_min = 120.0
			dirt_particles2.initial_velocity_max = 200.0
			dirt_particles2.lifetime = 1.5
			dirt_particles2.scale_amount_min = 3.0
			dirt_particles2.scale_amount_max = 6.0
		elif is_wheelspinning:
			dirt_particles2.amount = 100
			dirt_particles2.initial_velocity_min = 100.0
			dirt_particles2.initial_velocity_max = 180.0
			dirt_particles2.lifetime = 1.3
			dirt_particles2.scale_amount_min = 2.5
			dirt_particles2.scale_amount_max = 5.0
		else:
			dirt_particles2.amount = 50
			dirt_particles2.initial_velocity_min = 50.0
			dirt_particles2.initial_velocity_max = 100.0
			dirt_particles2.lifetime = 1.0
			dirt_particles2.scale_amount_min = 2.0
			dirt_particles2.scale_amount_max = 4.0
	
	# Debug output
	if debug_timer > 2.0:
		debug_timer = 0.0
		print("Speed: ", int(current_speed), " | HB: ", handbrake_active, " | AngVel: ", snappedf(angular_velocity, 0.01), " | Lateral: ", snappedf(lateral_speed, 0.1))
	
	# -----------------------------
	# SHIFTING
	# -----------------------------
	handle_shifting(current_speed)
	
	# -----------------------------
	# CALCULATE RPM
	# -----------------------------
	if gear == 0:
		rpm = move_toward(rpm, REDLINE_RPM if throttle_pressed else IDLE_RPM, 
						  (5000.0 if throttle_pressed else 2000.0) * delta)
	else:
		var gear_max = GEAR_MAX_SPEEDS[gear + 1]
		var speed_ratio = current_speed / gear_max
		
		if wheelspin_timer > 0.0 and throttle_pressed:
			var wheelspin_rpm_boost = (wheelspin_timer / wheelspin_duration) * 2000.0
			rpm = IDLE_RPM + (speed_ratio * RPM_RANGE) + wheelspin_rpm_boost
		else:
			rpm = IDLE_RPM + (speed_ratio * RPM_RANGE)
		
		rpm = clamp(rpm, IDLE_RPM, REDLINE_RPM)
	
	rpm += randf_range(-30.0, 30.0)
	rpm = clamp(rpm, IDLE_RPM - 50.0, REDLINE_RPM + 50.0)
	
	# -----------------------------
	# ENGINE FORCE & MOVEMENT
	# -----------------------------
	var ratio: float = GEAR_RATIOS[gear + 1]
	var torque: float = get_torque(rpm)
	var engine_force: float = torque * abs(ratio) * ENGINE_FORCE_MULTIPLIER
	
	# Reduce engine force during wheelspin
	if wheelspin_timer > 0.0 and throttle_pressed:
		engine_force *= current_traction * 0.4
	
	if gear == 0:
		linear_velocity = linear_velocity.move_toward(Vector2.ZERO, linear_friction * delta)
	elif gear == -1:
		if throttle_pressed:
			apply_central_force(-forward * engine_force)
			if current_speed > GEAR_MAX_SPEEDS[0]:
				linear_velocity = linear_velocity.normalized() * GEAR_MAX_SPEEDS[0]
		elif brake_pressed or handbrake_pressed:
			linear_velocity = linear_velocity.move_toward(Vector2.ZERO, BRAKE_FORCE * delta)
		else:
			linear_velocity = linear_velocity.move_toward(Vector2.ZERO, linear_friction * delta)
	else:
		if throttle_pressed and not handbrake_active:
			apply_central_force(forward * engine_force)
			var gear_limit: float = GEAR_MAX_SPEEDS[gear + 1]
			if current_speed > gear_limit and wheelspin_timer <= 0.0:
				linear_velocity = linear_velocity.normalized() * gear_limit
		# Allow throttle during handbrake to maintain momentum through drift
		elif throttle_pressed and handbrake_active:
			# Reduced force to maintain realistic drift momentum
			apply_central_force(forward * engine_force * 0.6)
		elif brake_pressed:
			linear_velocity = linear_velocity.move_toward(Vector2.ZERO, BRAKE_FORCE * delta)
		elif handbrake_active:
			# Light braking to scrub speed realistically
			linear_velocity = linear_velocity.move_toward(Vector2.ZERO, handbrake_brake_force * delta)
		else:
			linear_velocity = linear_velocity.move_toward(Vector2.ZERO, linear_friction * delta)
	
	# -----------------------------
	# DRIFT PHYSICS - Realistic lateral grip loss
	# -----------------------------
	var active_drift_factor = drift_factor
	
	if handbrake_active:
		active_drift_factor = handbrake_drift_factor
	elif wheelspin_timer > 0.0 and throttle_pressed:
		active_drift_factor = wheelspin_drift_factor
	
	# Apply lateral friction to create sliding effect
	linear_velocity -= right * lateral_speed * active_drift_factor
	
	# -----------------------------
	# STEERING - Realistic control during drift
	# -----------------------------
	if abs(forward_speed) > 10:
		var active_steering = steering
		var speed_factor = forward_speed / max_speed
		
		if handbrake_active:
			# Slight steering boost, but main control comes from angular velocity system above
			active_steering *= handbrake_steering_multiplier
		
		rotation += steer_input * active_steering * speed_factor * delta
	
	ui_update_timer += delta
	if ui_update_timer >= UI_UPDATE_INTERVAL:
		ui_update_timer = 0.0
		update_ui(current_speed)
	
	update_engine_sound(delta)

func handle_shifting(current_speed: float) -> void:
	if shift_timer > 0.0:
		return
	
	if Input.is_action_just_pressed("shift_up") and gear < MAX_GEAR:
		gear += 1
		shift_timer = SHIFT_COOLDOWN
	
	elif Input.is_action_just_pressed("shift_down") and gear > MIN_GEAR:
		var target_gear: int = gear - 1
		
		if target_gear != 0:
			var target_max_speed = GEAR_MAX_SPEEDS[target_gear + 1]
			var predicted_speed_ratio = current_speed / target_max_speed
			var predicted_rpm = IDLE_RPM + (predicted_speed_ratio * RPM_RANGE)
			
			if predicted_rpm <= REDLINE_RPM:
				gear = target_gear
				shift_timer = SHIFT_COOLDOWN
		else:
			gear = target_gear
			shift_timer = SHIFT_COOLDOWN

func update_ui(speed: float) -> void:
	if !rpm_label or !gear_label or !speed_label:
		return
	
	var rpm_int: int = int(rpm)
	rpm_label.text = str(rpm_int)
	
	if wheelspin_timer > 0.0 and throttle_pressed:
		rpm_label.modulate = COLOR_ORANGE
	elif rpm_int < 5000:
		rpm_label.modulate = COLOR_GREEN
	elif rpm_int < 6500:
		rpm_label.modulate = COLOR_YELLOW
	else:
		rpm_label.modulate = COLOR_RED
	
	var gear_text = "R" if gear == -1 else ("N" if gear == 0 else str(gear))
	
	if handbrake_active:
		gear_text += " [HB]"
	elif wheelspin_timer > 0.0 and throttle_pressed:
		gear_text += " [SPIN]"
	
	gear_label.text = gear_text
	gear_label.modulate = COLOR_ORANGE if (handbrake_active or (wheelspin_timer > 0.0 and throttle_pressed)) else COLOR_WHITE
	
	speed_label.text = str(int(speed * 0.5)) + " km/h"

func update_engine_sound(delta: float) -> void:
	if !engine_sound:
		return
	
	var rpm_normalized: float = (rpm - IDLE_RPM) / RPM_RANGE
	var target_pitch: float = lerp(min_pitch, max_pitch, rpm_normalized)
	
	if wheelspin_timer > 0.0 and throttle_pressed:
		target_pitch += sin(Time.get_ticks_msec() * 0.01) * 0.15
	
	current_pitch = lerp(current_pitch, target_pitch, pitch_smoothing * delta)
	engine_sound.pitch_scale = current_pitch
	
	var volume_boost = THROTTLE_VOLUME_BOOST if (throttle_pressed and gear > 0) else 0.0
	
	if wheelspin_timer > 0.0 and throttle_pressed:
		volume_boost += 2.0
	
	engine_sound.volume_db = BASE_VOLUME + volume_boost
