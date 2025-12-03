extends Node2D

# -----------------------------
# Engine + Transmission
# -----------------------------
const IDLE_RPM: float = 900.0
const REDLINE_RPM: float = 7800.0
var rpm: float = IDLE_RPM
var gear: int = 0  # 0 = Neutral, -1 = Reverse, 1-6 = Forward gears
const MIN_GEAR: int = -1  # Reverse
const MAX_GEAR: int = 6
var shift_cooldown: float = 0.2
var shift_timer: float = 0.0

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
@export var wheel_scale: float = 0.07  # DOUBLED from 0.035 for higher top speeds
@export var friction: float = 500.0
@export var max_turn_speed: float = 180.0   # deg/sec at low speed
@export var min_turn_speed: float = 120.0   # deg/sec at high speed
@export var turn_slow_factor: float = 0.05  # base factor for turn slowdown

var velocity: Vector2 = Vector2.ZERO

# -----------------------------
# UI References
# -----------------------------
@export var rpm_label: Label
@export var gear_label: Label
@export var speed_label: Label

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
	# FORWARD VECTOR & SPEED
	# -----------------------------
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	var forward_speed: float = velocity.dot(forward)
	
	# -----------------------------
	# SHIFTING
	# -----------------------------
	if shift_timer <= 0.0:
		if Input.is_action_just_pressed("shift_up") and gear < MAX_GEAR:
			gear += 1
			shift_timer = shift_cooldown
			# Instantly recalculate RPM for new gear
			if gear != 0:  # Skip if not in neutral
				var new_ratio: float = float(gear_ratios.get(gear, 1.0))
				var wheel_rpm_now: float = abs(forward_speed) / wheel_scale
				rpm = max(wheel_rpm_now * new_ratio, IDLE_RPM)
		if Input.is_action_just_pressed("shift_down") and gear > MIN_GEAR:
			gear -= 1
			shift_timer = shift_cooldown
			# Instantly recalculate RPM for new gear
			if gear != 0:  # Skip if not in neutral
				var new_ratio: float = float(gear_ratios.get(gear, 1.0))
				var wheel_rpm_now: float = abs(forward_speed) / wheel_scale
				rpm = max(wheel_rpm_now * new_ratio, IDLE_RPM)
	
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
	elif throttle_pressed:
		# When accelerating, RPM can go higher than wheel speed suggests
		rpm = max(calculated_rpm, min(rpm + 5000.0 * delta, REDLINE_RPM))
	else:
		# Otherwise, RPM directly matches wheel speed
		rpm = max(calculated_rpm, IDLE_RPM)
	
	rpm = clamp(rpm, IDLE_RPM, REDLINE_RPM)
	
	# -----------------------------
	# ENGINE FORCE (based on torque and gear)
	# -----------------------------
	var torque: float = get_torque(rpm)
	var engine_force: float = torque * abs(ratio) * 150.0
	
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
			# S brakes when in reverse
			forward_speed = move_toward(forward_speed, 0.0, 1200.0 * delta)
		else:
			forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	else:  # FORWARD GEARS (1-6)
		if throttle_pressed:
			# Forward acceleration using engine force (gear-dependent)
			forward_speed += engine_force * delta
			# Limit speed by current gear's max RPM capability
			var max_speed_in_gear: float = (REDLINE_RPM / ratio) * wheel_scale
			forward_speed = min(forward_speed, max_speed_in_gear)
		elif brake_pressed:
			# S brakes in forward gears, does NOT reverse
			forward_speed = move_toward(forward_speed, 0.0, 1200.0 * delta)
		else:
			# Natural friction
			forward_speed = move_toward(forward_speed, 0.0, friction * delta)
	
	# -----------------------------
	# TURN SLOWING
	# -----------------------------
	if turn_input != 0.0 and abs(forward_speed) > 0.0 and gear != 0:  # Don't slow in neutral
		var max_possible_speed: float = (REDLINE_RPM / abs(ratio)) * wheel_scale
		var speed_scale: float = clamp(abs(forward_speed) / max_possible_speed, 0.0, 1.0)
		var turn_slow_amount: float = turn_slow_factor * 2.0 * abs(turn_input) * speed_scale * max_possible_speed * delta
		if abs(forward_speed) > turn_slow_amount:
			forward_speed -= sign(forward_speed) * turn_slow_amount
		else:
			forward_speed = 0.0
	
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
	# MOVE CAR
	# -----------------------------
	global_position += velocity * delta
	
	# -----------------------------
	# UPDATE UI
	# -----------------------------
	update_ui(forward_speed)

# -----------------------------
# UI UPDATE
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

func update_ui(speed: float) -> void:
	if rpm_label:
		rpm_label.text = "RPM: %d" % int(rpm)
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
		# Display gear as R, N, or 1-6
		var gear_text: String = ""
		if gear == -1:
			gear_text = "R"
		elif gear == 0:
			gear_text = "N"
		else:
			gear_text = str(gear)
		gear_label.text = "Gear: %s" % gear_text
	else:
		print("Gear label is null in update_ui!")
	
	if speed_label:
		# Convert speed to km/h (multiply by arbitrary factor for gameplay feel)
		var kmh: float = abs(speed) * 0.5  # Adjust multiplier to taste
		speed_label.text = "Speed: %d km/h" % int(kmh)
	else:
		print("Speed label is null in update_ui!")
