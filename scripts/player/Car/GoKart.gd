extends StaticBody2D

# -----------------------------
# Engine + Centrifugal Clutch
# -----------------------------
const IDLE_RPM: float = 1800.0
const MAX_RPM: float = 11500.0
const CLUTCH_ENGAGE_RPM: float = 2000.0  # When clutch starts engaging
const CLUTCH_FULL_RPM: float = 3500.0    # When clutch is fully engaged (wider range = smoother)
const RPM_RANGE: float = 9700.0  # Cached: MAX_RPM - IDLE_RPM
var rpm: float = IDLE_RPM

# Engine inertia - how quickly engine can change RPM
const ENGINE_INERTIA: float = 0.15  # Lower = faster RPM changes (small engine = low inertia)
const ENGINE_FRICTION: float = 150.0  # Internal friction slowing engine down

# Single-speed ratio (direct drive once clutch engaged)
const DRIVE_RATIO: float = 2.9  # Lower for higher top speed

# Clutch slip simulation
var clutch_slip_rpm: float = 0.0  # Difference between engine and wheel speed during slip

# -----------------------------
# Go-Kart handling - Cached constants
# -----------------------------
@export var wheel_scale: float = 0.0525
@export var friction: float = 80.0  # Reduced base friction
@export var max_turn_speed: float = 200.0  # More responsive steering
@export var min_turn_speed: float = 140.0

const ENGINE_FORCE_MULTIPLIER: float = 52.0  # Base multiplier
const BRAKE_FORCE: float = 500.0
const TURN_DRAG_FACTOR: float = 0.6  # More drag in turns (no differential)
const AIR_RESISTANCE: float = 0.006  # Reduced - was too high

var velocity: Vector2 = Vector2.ZERO

# -----------------------------
# UI References
# -----------------------------
@onready var rpm_label: Label = $CanvasLayer/Control/VBoxContainer/RPMlabel
@onready var speed_label: Label = $CanvasLayer/Control/VBoxContainer/SpeedLabel
@onready var clutch_label: Label = $CanvasLayer/Control/VBoxContainer/ClutchLabel
@onready var engine_sound: AudioStreamPlayer2D = $EngineSound

# -----------------------------
# Engine Sound Settings
# -----------------------------
@export var min_pitch: float = 0.9
@export var max_pitch: float = 2.8
@export var pitch_smoothing: float = 6.0
const BASE_VOLUME: float = -6.0  # Louder for small engine
const THROTTLE_VOLUME_BOOST: float = 4.0
var current_pitch: float = 1.0

# Cached input states
var throttle_pressed: bool = false
var brake_pressed: bool = false
var turn_input: float = 0.0

# UI update throttling
var ui_update_timer: float = 0.0
const UI_UPDATE_INTERVAL: float = 0.033  # ~30 FPS for UI updates

# Cached color values
const COLOR_GREEN: Color = Color.GREEN
const COLOR_YELLOW: Color = Color.YELLOW
const COLOR_RED: Color = Color.RED
const COLOR_WHITE: Color = Color.WHITE
const COLOR_ORANGE: Color = Color(1.0, 0.6, 0.0)

# -----------------------------
# Torque curve - small engine characteristics
# -----------------------------
func get_torque(in_rpm: float) -> float:
	# Realistic small 2-stroke or 4-stroke engine curve
	# More low-end torque for better launches
	if in_rpm < 2000.0:
		return 0.4
	if in_rpm < 3000.0:
		return 0.7  # Strong low-end for initial acceleration
	if in_rpm < 4000.0:
		return 0.85
	if in_rpm < 5500.0:
		return 0.95
	if in_rpm < 8000.0:
		return 1.0  # Peak power
	if in_rpm < 10000.0:
		return 0.88
	if in_rpm < MAX_RPM:
		return 0.72
	return 0.0

# -----------------------------
# Centrifugal Clutch Engagement
# -----------------------------
func get_clutch_engagement() -> float:
	if rpm < CLUTCH_ENGAGE_RPM:
		return 0.0
	if rpm >= CLUTCH_FULL_RPM:
		return 1.0
	# Progressive engagement curve that starts very gentle
	var t: float = (rpm - CLUTCH_ENGAGE_RPM) / (CLUTCH_FULL_RPM - CLUTCH_ENGAGE_RPM)
	# Cubic easing for very smooth start
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

# -----------------------------
# READY
# -----------------------------
func _ready() -> void:
	# Validate UI references once
	assert(rpm_label != null, "RPM Label is missing!")
	assert(speed_label != null, "Speed Label is missing!")
	if clutch_label == null:
		push_warning("Clutch Label is missing - add a Label node at CanvasLayer/Control/VBoxContainer/ClutchLabel")

func _process(delta: float) -> void:
	# Cache input states once per frame
	throttle_pressed = Input.is_action_pressed("accelerate")
	brake_pressed = Input.is_action_pressed("brake")
	turn_input = Input.get_axis("steer_left", "steer_right")
	
	# -----------------------------
	# FORWARD VECTOR & SPEED
	# -----------------------------
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var forward_speed: float = velocity.dot(forward)
	var abs_speed: float = abs(forward_speed)
	
	# -----------------------------
	# CALCULATE WHEEL RPM
	# -----------------------------
	var wheel_rpm: float = abs_speed * DRIVE_RATIO / wheel_scale
	
	# -----------------------------
	# CALCULATE CLUTCH ENGAGEMENT
	# -----------------------------
	var clutch: float = get_clutch_engagement()
	
	# -----------------------------
	# ENGINE RPM SIMULATION WITH INERTIA
	# -----------------------------
	var target_engine_rpm: float = rpm
	
	if clutch < 0.99:
		# Clutch slipping or disengaged - engine RPM controlled by throttle
		if throttle_pressed:
			# Throttle pressed - engine tries to rev up
			# But limited by engine inertia (can't instantly reach max RPM)
			target_engine_rpm = lerp(rpm, MAX_RPM, 0.15)
		else:
			# No throttle - engine returns to idle
			target_engine_rpm = IDLE_RPM
		
		# Apply engine inertia - gradual RPM changes
		var rpm_acceleration: float = (target_engine_rpm - rpm) / ENGINE_INERTIA
		rpm += rpm_acceleration * delta
		
		# Engine internal friction
		if rpm > IDLE_RPM and !throttle_pressed:
			rpm -= ENGINE_FRICTION * delta
		
		# Calculate clutch slip
		clutch_slip_rpm = rpm - wheel_rpm
		
	else:
		# Clutch fully engaged - engine RPM locked to wheel speed
		rpm = max(wheel_rpm, IDLE_RPM)
		clutch_slip_rpm = 0.0
		
		# But if engine would over-rev, clutch can slip to protect engine
		if rpm > MAX_RPM * 0.98:
			rpm = MAX_RPM * 0.98
	
	# Add realistic fluctuation
	rpm += randf_range(-25.0, 25.0)
	rpm = clamp(rpm, IDLE_RPM - 50.0, MAX_RPM + 50.0)
	
	# -----------------------------
	# ENGINE FORCE WITH CLUTCH SLIP
	# -----------------------------
	# Power = Torque at current RPM * gear ratio * multiplier
	var engine_torque: float = get_torque(rpm)
	var base_force: float = engine_torque * DRIVE_RATIO * ENGINE_FORCE_MULTIPLIER
	
	# During clutch slip, power transmission is reduced by clutch engagement
	var transmitted_force: float = base_force * clutch
	
	# Additional slip loss - clutch can't transfer full power while slipping
	if clutch < 0.99 and clutch > 0.01:
		# More slip = more power loss (heat dissipation)
		var slip_factor: float = abs(clutch_slip_rpm) / 1500.0  # Increased denominator for less slip loss
		slip_factor = clamp(slip_factor, 0.0, 0.3)  # Reduced max slip loss
		transmitted_force *= (1.0 - slip_factor)
	
	# -----------------------------
	# ACCELERATION & BRAKING
	# -----------------------------
	if throttle_pressed and forward_speed >= 0.0:
		forward_speed += transmitted_force * delta
		var max_speed: float = MAX_RPM * wheel_scale / DRIVE_RATIO
		forward_speed = min(forward_speed, max_speed)
	elif brake_pressed:
		forward_speed = move_toward(forward_speed, 0.0, BRAKE_FORCE * delta)
	else:
		# Coasting - friction and engine braking
		var drag: float = friction
		
		# Reduced engine braking when clutch engaged
		if clutch > 0.8:
			drag += 40.0 * clutch  # Reduced from 80.0
		
		forward_speed = move_toward(forward_speed, 0.0, drag * delta)
	
	# Air resistance (increases with speed squared)
	if forward_speed > 0.0:
		var air_drag: float = AIR_RESISTANCE * forward_speed * forward_speed
		forward_speed -= air_drag * delta
	
	# Prevent reverse (no reverse gear in go-karts)
	forward_speed = max(forward_speed, 0.0)
	
	# -----------------------------
	# TURN SLOWING (no differential = inside wheel drags)
	# -----------------------------
	if turn_input != 0.0 and abs_speed > 1.0:
		forward_speed -= abs_speed * TURN_DRAG_FACTOR * abs(turn_input) * delta
		forward_speed = max(forward_speed, 0.0)
	
	velocity = forward * forward_speed
	
	# -----------------------------
	# TURNING - Direct steering, no power assist
	# -----------------------------
	if abs_speed > 0.1:
		var speed_factor: float = clamp(abs_speed * DRIVE_RATIO / (MAX_RPM * wheel_scale), 0.0, 1.0)
		var current_turn_speed: float = lerp(max_turn_speed, min_turn_speed, speed_factor * 0.4)
		
		# Brake turning (common go-kart technique)
		if brake_pressed:
			current_turn_speed *= 1.3  # Better turning while braking
		
		global_rotation += deg_to_rad(turn_input * current_turn_speed * delta)
	
	# -----------------------------
	# MOVE KART
	# -----------------------------
	var collision: KinematicCollision2D = move_and_collide(velocity * delta)
	if collision:
		# Simple collision response
		velocity = velocity.slide(collision.get_normal())
		forward_speed *= 0.3  # Lose speed on impact
	
	# -----------------------------
	# UPDATE UI (throttled)
	# -----------------------------
	ui_update_timer += delta
	if ui_update_timer >= UI_UPDATE_INTERVAL:
		ui_update_timer = 0.0
		update_ui(forward_speed, clutch)
	
	# -----------------------------
	# UPDATE ENGINE SOUND
	# -----------------------------
	update_engine_sound(delta)

# -----------------------------
# UI UPDATE - Optimized
# -----------------------------
func update_ui(speed: float, clutch_engagement: float) -> void:
	var rpm_int: int = int(rpm)
	rpm_label.text = str(rpm_int) + " RPM"
	
	# RPM color coding
	if rpm_int < 5000:
		rpm_label.modulate = COLOR_GREEN
	elif rpm_int < 7000:
		rpm_label.modulate = COLOR_YELLOW
	elif rpm_int < 8200:
		rpm_label.modulate = COLOR_ORANGE
	else:
		rpm_label.modulate = COLOR_RED
	
	# Clutch engagement indicator
	if clutch_label:
		if clutch_engagement < 0.1:
			clutch_label.text = "CLUTCH: DISENGAGED"
			clutch_label.modulate = COLOR_RED
		elif clutch_engagement < 0.99:
			clutch_label.text = "CLUTCH: " + str(int(clutch_engagement * 100)) + "%"
			clutch_label.modulate = COLOR_YELLOW
		else:
			clutch_label.text = "CLUTCH: ENGAGED"
			clutch_label.modulate = COLOR_GREEN
	
	# Speed display
	speed_label.text = str(int(speed * 0.5)) + " km/h"

# -----------------------------
# ENGINE SOUND UPDATE - Optimized
# -----------------------------
func update_engine_sound(delta: float) -> void:
	if !engine_sound:
		return
	
	var rpm_normalized: float = (rpm - IDLE_RPM) / RPM_RANGE
	var target_pitch: float = lerp(min_pitch, max_pitch, rpm_normalized)
	current_pitch = lerp(current_pitch, target_pitch, pitch_smoothing * delta)
	engine_sound.pitch_scale = current_pitch
	
	# Volume changes with throttle
	var target_volume: float = BASE_VOLUME
	if throttle_pressed:
		target_volume += THROTTLE_VOLUME_BOOST
	
	engine_sound.volume_db = target_volume
