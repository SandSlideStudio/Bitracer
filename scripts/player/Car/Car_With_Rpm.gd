extends StaticBody2D

# -----------------------------
# Engine + Transmission
# -----------------------------
const IDLE_RPM: float = 900.0
const REDLINE_RPM: float = 7800.0
const PIT_LIMITER_SPEED: float = 160.0
const RPM_RANGE: float = 6900.0  # Cached: REDLINE_RPM - IDLE_RPM
var rpm: float = IDLE_RPM
var gear: int = 0
const MIN_GEAR: int = -1
const MAX_GEAR: int = 6
const SHIFT_COOLDOWN: float = 0.2
var shift_timer: float = 0.0
var pit_limiter_active: bool = false

# Cached gear ratios as floats (index: gear + 1, so -1 becomes 0, 0 becomes 1, etc.)
const GEAR_RATIOS: Array[float] = [3.20, 1.0, 3.20, 2.10, 1.45, 1.10, 0.90, 0.78]
# Indices: [0]=R(-1), [1]=N(0), [2]=1st, [3]=2nd, [4]=3rd, [5]=4th, [6]=5th, [7]=6th

# -----------------------------
# Car handling - Cached constants
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

# Cached input states to avoid repeated calls
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

# -----------------------------
# Torque curve - optimized lookup
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
	# Validate UI references once
	assert(rpm_label != null, "RPM Label is missing!")
	assert(gear_label != null, "Gear Label is missing!")
	assert(speed_label != null, "Speed Label is missing!")

func _process(delta: float) -> void:
	shift_timer -= delta
	
	# Cache input states once per frame
	throttle_pressed = Input.is_action_pressed("ui_up")
	brake_pressed = Input.is_action_pressed("ui_down")
	turn_input = Input.get_axis("ui_left", "ui_right")
	
	# -----------------------------
	# PIT LIMITER TOGGLE
	# -----------------------------
	if Input.is_action_just_pressed("pit_limiter"):
		pit_limiter_active = !pit_limiter_active
		if pit_limiter_active:
			gear = 2
	
	# -----------------------------
	# FORWARD VECTOR & SPEED
	# -----------------------------
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var forward_speed: float = velocity.dot(forward)
	
	# -----------------------------
	# SHIFTING
	# -----------------------------
	if shift_timer <= 0.0 and !pit_limiter_active:
		if Input.is_action_just_pressed("shift_up") and gear < MAX_GEAR:
			gear += 1
			shift_timer = SHIFT_COOLDOWN
			if gear != 0:
				var new_ratio: float = GEAR_RATIOS[gear + 1]
				rpm = max(abs(forward_speed) * new_ratio / wheel_scale, IDLE_RPM)
				
		elif Input.is_action_just_pressed("shift_down") and gear > MIN_GEAR:
			var target_gear: int = gear - 1
			if target_gear != 0:
				var new_ratio: float = GEAR_RATIOS[target_gear + 1]
				var predicted_rpm: float = abs(forward_speed) * new_ratio / wheel_scale
				
				if predicted_rpm <= REDLINE_RPM:
					gear = target_gear
					shift_timer = SHIFT_COOLDOWN
					rpm = max(predicted_rpm, IDLE_RPM)
			else:
				gear = target_gear
				shift_timer = SHIFT_COOLDOWN
	
	# -----------------------------
	# CALCULATE RPM FROM WHEEL SPEED
	# -----------------------------
	var ratio: float = GEAR_RATIOS[gear + 1] if gear != 0 else 1.0
	var abs_speed: float = abs(forward_speed)
	
	# -----------------------------
	# RPM BEHAVIOR
	# -----------------------------
	if gear == 0:
		rpm = move_toward(rpm, REDLINE_RPM if throttle_pressed else IDLE_RPM, 
						  (5000.0 if throttle_pressed else 2000.0) * delta)
	else:
		rpm = max(abs_speed * abs(ratio) / wheel_scale, IDLE_RPM)
	
	# Add fluctuation (cheaper random)
	rpm += randf_range(-30.0, 30.0)
	rpm = clamp(rpm, IDLE_RPM - 50.0, REDLINE_RPM + 50.0)
	
	# -----------------------------
	# ENGINE FORCE
	# -----------------------------
	var engine_force: float = get_torque(rpm) * abs(ratio) * ENGINE_FORCE_MULTIPLIER
	
	# -----------------------------
	# ACCELERATION & BRAKING
	# -----------------------------
	if gear == 0:
		forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	elif gear == -1:
		if throttle_pressed:
			forward_speed -= engine_force * delta
			forward_speed = max(forward_speed, -(REDLINE_RPM * wheel_scale / abs(ratio)))
		elif brake_pressed:
			forward_speed = move_toward(forward_speed, 0.0, BRAKE_FORCE * delta)
		else:
			forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	else:
		var can_use_throttle: bool = !pit_limiter_active or forward_speed <= PIT_LIMITER_SPEED
		
		if throttle_pressed and can_use_throttle:
			forward_speed += engine_force * delta
			var max_speed: float = REDLINE_RPM * wheel_scale / ratio
			forward_speed = min(forward_speed, max_speed if !pit_limiter_active else min(max_speed, PIT_LIMITER_SPEED))
		elif brake_pressed:
			forward_speed = move_toward(forward_speed, 0.0, BRAKE_FORCE * delta)
		else:
			forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	
	# -----------------------------
	# TURN SLOWING
	# -----------------------------
	if turn_input != 0.0 and abs_speed > 1.0 and gear != 0:
		forward_speed -= sign(forward_speed) * abs_speed * TURN_DRAG_FACTOR * abs(turn_input) * delta
	
	velocity = forward * forward_speed
	
	# -----------------------------
	# TURNING
	# -----------------------------
	if abs_speed > 0.1:
		var speed_factor: float = clamp(abs_speed * ratio / (REDLINE_RPM * wheel_scale), 0.0, 1.0)
		var current_turn_speed: float = lerp(max_turn_speed, min_turn_speed, speed_factor * SPEED_TURN_LERP)
		
		if brake_pressed and forward_speed > 0.0:
			current_turn_speed *= BRAKE_TURN_FACTOR
		
		var steering_factor: float = -1.0 if forward_speed < 0.0 else 1.0
		global_rotation += deg_to_rad(turn_input * current_turn_speed * steering_factor * delta)
	
	# -----------------------------
	# MOVE CAR
	# -----------------------------
	var collision: KinematicCollision2D = move_and_collide(velocity * delta)
	if collision:
		velocity = Vector2.ZERO
	
	# -----------------------------
	# UPDATE UI (throttled)
	# -----------------------------
	ui_update_timer += delta
	if ui_update_timer >= UI_UPDATE_INTERVAL:
		ui_update_timer = 0.0
		update_ui(forward_speed)
	
	# -----------------------------
	# UPDATE ENGINE SOUND
	# -----------------------------
	update_engine_sound(delta)

# -----------------------------
# UI UPDATE - Optimized
# -----------------------------
func update_ui(speed: float) -> void:
	var rpm_int: int = int(rpm)
	rpm_label.text = str(rpm_int)
	
	# Simplified color logic
	if rpm_int < 5000:
		rpm_label.modulate = COLOR_GREEN
	elif rpm_int < 6500:
		rpm_label.modulate = COLOR_YELLOW
	else:
		rpm_label.modulate = COLOR_RED
	
	# Gear display
	if pit_limiter_active:
		gear_label.text = "PIT LIMIT"
		gear_label.modulate = COLOR_YELLOW
	else:
		gear_label.text = "R" if gear == -1 else ("N" if gear == 0 else str(gear))
		gear_label.modulate = COLOR_WHITE
	
	# Speed - simplified calculation
	speed_label.text = str(int(abs(speed) * 0.5)) + " km/h"

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
	
	engine_sound.volume_db = BASE_VOLUME + (THROTTLE_VOLUME_BOOST if (throttle_pressed and gear > 0) else 0.0)
