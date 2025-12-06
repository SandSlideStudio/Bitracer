extends StaticBody2D

# -----------------------------
# Engine + Transmission
# -----------------------------
const IDLE_RPM: float = 900.0
const REDLINE_RPM: float = 7800.0
const PIT_LIMITER_SPEED: float = 160.0  # 80 km/h × 2 (our speed multiplier is 0.5)
var rpm: float = IDLE_RPM
var gear: int = 0  # 0 = Neutral, -1 = Reverse, 1-6 = Forward gears
const MIN_GEAR: int = -1  # Reverse
const MAX_GEAR: int = 6
var shift_cooldown: float = 0.2
var shift_timer: float = 0.0
var pit_limiter_active: bool = false

# Realistic gear ratios (lower gears -> higher ratio)
var gear_ratios: Dictionary = {
	-1: 3.20,  # Reverse (same as 1st gear)
	0: 1.0,    # Neutral (not used for calculations)
	1: 3.20,
	2: 2.10,
	3: 1.45,
	4: 1.10,
	5: 0.90,
	6: 0.78,
}

# -----------------------------
# Car handling
# -----------------------------
@export var wheel_scale: float = 0.0525  # Reduced from 0.07 (75% of original for lower top speed)
@export var friction: float = 150.0  # Reduced from 500.0 for more coasting
@export var max_turn_speed: float = 180.0   # deg/sec at low speed
@export var min_turn_speed: float = 120.0   # deg/sec at high speed
@export var turn_slow_factor: float = 0.05  # base factor for turn slowdown

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
@export var min_pitch: float = 0.8  # Pitch at idle RPM
@export var max_pitch: float = 2.5  # Pitch at redline RPM
@export var pitch_smoothing: float = 5.0  # How fast pitch changes (lower = smoother)
var target_pitch: float = 1.0
var current_pitch: float = 1.0

# -----------------------------
# Torque curve
# -----------------------------
func get_torque(in_rpm: float) -> float:
	# Approximate torque curve (returns multiplier)
	if in_rpm < 1500.0:
		return 0.2
	elif in_rpm < 3000.0:
		return 0.55
	elif in_rpm < 4500.0:
		return 0.85
	elif in_rpm < 6500.0:
		return 1.0
	elif in_rpm < REDLINE_RPM:
		return 0.7
	else:
		return 0.0

# -----------------------------
# READY
# -----------------------------
func _ready() -> void:
	print("Car script ready!")
	print("RPM Label found: ", rpm_label != null)
	print("Gear Label found: ", gear_label != null)
	print("Speed Label found: ", speed_label != null)
	
	if rpm_label == null:
		print("ERROR: RPM Label is null!")
	if gear_label == null:
		print("ERROR: Gear Label is null!")
	if speed_label == null:
		print("ERROR: Speed Label is null!")

func _process(delta: float) -> void:
	shift_timer -= delta
	
	# -----------------------------
	# INPUT
	# -----------------------------
	var throttle_pressed: bool = Input.is_action_pressed("ui_up")
	var brake_pressed: bool = Input.is_action_pressed("ui_down")
	
	var turn_input: float = 0.0
	if Input.is_action_pressed("ui_left"):
		turn_input = -1.0
	elif Input.is_action_pressed("ui_right"):
		turn_input = 1.0
	
	# -----------------------------
	# PIT LIMITER TOGGLE
	# -----------------------------
	if Input.is_action_just_pressed("pit_limiter"):
		pit_limiter_active = !pit_limiter_active
		if pit_limiter_active:
			gear = 2  # Force into 2nd gear
	
	# -----------------------------
	# FORWARD VECTOR & SPEED
	# -----------------------------
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var forward_speed: float = velocity.dot(forward)
	
	# -----------------------------
	# SHIFTING
	# -----------------------------
	if shift_timer <= 0.0 and !pit_limiter_active:  # Can't shift when pit limiter is on
		if Input.is_action_just_pressed("shift_up") and gear < MAX_GEAR:
			gear += 1
			shift_timer = shift_cooldown
			# Instantly recalculate RPM for new gear
			if gear != 0:  # Skip if not in neutral
				var new_ratio: float = float(gear_ratios.get(gear, 1.0))
				var wheel_rpm_now: float = abs(forward_speed) / wheel_scale
				rpm = max(wheel_rpm_now * new_ratio, IDLE_RPM)
		if Input.is_action_just_pressed("shift_down") and gear > MIN_GEAR:
			# Check if downshifting would cause over-revving
			var target_gear: int = gear - 1
			if target_gear != 0:  # Skip check for neutral
				var new_ratio: float = float(gear_ratios.get(target_gear, 1.0))
				var wheel_rpm_now: float = abs(forward_speed) / wheel_scale
				var predicted_rpm: float = wheel_rpm_now * abs(new_ratio)
				
				# Only allow downshift if RPM would be at or below redline
				if predicted_rpm <= REDLINE_RPM:
					gear = target_gear
					shift_timer = shift_cooldown
					rpm = max(predicted_rpm, IDLE_RPM)
				# else: downshift blocked, do nothing
			else:
				# Always allow shifting to neutral
				gear = target_gear
				shift_timer = shift_cooldown
	
	# -----------------------------
	# CALCULATE RPM FROM WHEEL SPEED
	# -----------------------------
	var ratio: float = 1.0
	if gear != 0:  # Not in neutral
		ratio = float(gear_ratios.get(gear, 1.0))
	
	var wheel_rpm: float = abs(forward_speed) / wheel_scale
	var calculated_rpm: float = wheel_rpm * abs(ratio)
	
	# -----------------------------
	# RPM BEHAVIOR - Direct match to speed
	# -----------------------------
	if gear == 0:  # NEUTRAL - can rev freely
		if throttle_pressed:
			rpm = min(rpm + 5000.0 * delta, REDLINE_RPM)
		else:
			rpm = move_toward(rpm, IDLE_RPM, 2000.0 * delta)
	else:
		# RPM ALWAYS matches wheel speed in gear (forward or reverse)
		rpm = max(calculated_rpm, IDLE_RPM)
	
	# Add realistic RPM fluctuation
	var rpm_fluctuation: float = randf_range(-30.0, 30.0)
	rpm += rpm_fluctuation
	
	rpm = clamp(rpm, IDLE_RPM - 50.0, REDLINE_RPM + 50.0)
	
	# -----------------------------
	# ENGINE FORCE (based on torque and gear)
	# -----------------------------
	var torque: float = get_torque(rpm)
	var engine_force: float = torque * abs(ratio) * 56.25  # 75.0 * 0.75
	
	# -----------------------------
	# ACCELERATION & BRAKING
	# -----------------------------
	if gear == 0:  # NEUTRAL - no power to wheels
		# Just apply friction, no throttle or brake effect
		forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	elif gear == -1:  # REVERSE
		if throttle_pressed:
			# Reverse acceleration (W makes you go backward)
			forward_speed -= engine_force * delta
			# Limit reverse speed
			var max_reverse_speed: float = (REDLINE_RPM / abs(ratio)) * wheel_scale
			forward_speed = max(forward_speed, -max_reverse_speed)
		elif brake_pressed:
			# S brakes when in reverse - reduced brake force
			forward_speed = move_toward(forward_speed, 0.0, 600.0 * delta)
		else:
			forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	else:  # FORWARD GEARS (1-6)
		# Pit limiter logic - disable throttle if above speed limit
		var can_use_throttle: bool = true
		if pit_limiter_active and forward_speed > PIT_LIMITER_SPEED:
			can_use_throttle = false
		
		if throttle_pressed and can_use_throttle:
			# Forward acceleration using engine force (gear-dependent)
			forward_speed += engine_force * delta
			# Limit speed by current gear's max RPM capability
			var max_speed_in_gear: float = (REDLINE_RPM / ratio) * wheel_scale
			forward_speed = min(forward_speed, max_speed_in_gear)
			
			# Pit limiter speed cap (only when accelerating from below limit)
			if pit_limiter_active:
				forward_speed = min(forward_speed, PIT_LIMITER_SPEED)
		elif brake_pressed:
			# S brakes in forward gears - reduced brake force
			forward_speed = move_toward(forward_speed, 0.0, 600.0 * delta)
		else:
			# Natural friction/coasting - much less slowdown
			forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	
	# -----------------------------
	# TURN SLOWING
	# -----------------------------
	if turn_input != 0.0 and abs(forward_speed) > 1.0 and gear != 0:  # Don't slow in neutral
		# The faster you go, the more speed you lose when turning
		var turn_drag: float = abs(forward_speed) * 0.5 * abs(turn_input) * delta
		forward_speed -= sign(forward_speed) * turn_drag
	
	velocity = forward * forward_speed
	
	# -----------------------------
	# TURNING
	# -----------------------------
	if abs(forward_speed) > 0.1:  # Only allow turning if moving
		var max_possible_speed: float = (REDLINE_RPM / abs(ratio)) * wheel_scale
		var speed_factor: float = clamp(abs(forward_speed) / max_possible_speed, 0.0, 1.0)
		var current_turn_speed: float = lerp(max_turn_speed, min_turn_speed, speed_factor * 0.5)
		
		# Reduce turn speed if braking in forward direction
		if brake_pressed and forward_speed > 0.0:
			current_turn_speed *= 0.7
		
		# Reverse steering if moving backward
		var steering_factor: float = 1.0
		if forward_speed < 0.0:
			steering_factor = -1.0
		
		global_rotation += deg_to_rad(turn_input * current_turn_speed * steering_factor * delta)
	
	# -----------------------------
	# MOVE CAR (using test_move for collision)
	# -----------------------------
	var motion: Vector2 = velocity * delta
	var collision: KinematicCollision2D = move_and_collide(motion)
	
	if collision:
		# Hit something, stop movement
		velocity = Vector2.ZERO
		print("Hit: ", collision.get_collider().name)
	
	# -----------------------------
	# UPDATE UI
	# -----------------------------
	update_ui(forward_speed)
	
	# -----------------------------
	# UPDATE ENGINE SOUND
	# -----------------------------
	update_engine_sound(delta)

# -----------------------------
# UI UPDATE
# -----------------------------
func update_ui(speed: float) -> void:
	if rpm_label:
		rpm_label.text = "%d" % int(rpm)
		# Color code RPM (green -> yellow -> red)
		if rpm < 5000.0:
			rpm_label.modulate = Color.GREEN
		elif rpm < 6500.0:
			rpm_label.modulate = Color.YELLOW
		else:
			rpm_label.modulate = Color.RED
	else:
		print("RPM label is null in update_ui!")
	
	if gear_label:
		# Display gear as R, N, or 1-6, or PIT LIMIT
		var gear_text: String = ""
		if pit_limiter_active:
			gear_text = "PIT LIMIT"
			gear_label.modulate = Color.YELLOW
		elif gear == -1:
			gear_text = "R"
			gear_label.modulate = Color.WHITE
		elif gear == 0:
			gear_text = "N"
			gear_label.modulate = Color.WHITE
		else:
			gear_text = str(gear)
			gear_label.modulate = Color.WHITE
		gear_label.text = "%s" % gear_text
	else:
		print("Gear label is null in update_ui!")
	
	if speed_label:
		# Convert speed to km/h (multiply by arbitrary factor for gameplay feel)
		var kmh: float = abs(speed) * 0.5  # Adjust multiplier to taste
		speed_label.text = "%d km/h" % int(kmh)
	else:
		print("Speed label is null in update_ui!")

# -----------------------------
# ENGINE SOUND UPDATE
# -----------------------------
func update_engine_sound(delta: float) -> void:
	if !engine_sound:
		return
	
	# Calculate target pitch based on RPM
	# Map RPM (900-7800) to pitch (min_pitch - max_pitch)
	var rpm_normalized: float = (rpm - IDLE_RPM) / (REDLINE_RPM - IDLE_RPM)
	target_pitch = lerp(min_pitch, max_pitch, rpm_normalized)
	
	# Smoothly interpolate current pitch towards target
	current_pitch = lerp(current_pitch, target_pitch, pitch_smoothing * delta)
	
	# Apply pitch to audio player
	engine_sound.pitch_scale = current_pitch
	
	# Optional: Adjust volume based on throttle (louder when accelerating)
	var base_volume: float = -8.0  # Base volume in dB
	var throttle_volume_boost: float = 0.0
	if Input.is_action_pressed("ui_up") and gear > 0:
		throttle_volume_boost = 3.0  # +3dB when throttling
	
	engine_sound.volume_db = base_volume + throttle_volume_boost
