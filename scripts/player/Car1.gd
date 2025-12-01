extends Node2D

# --- Speed and acceleration ---
@export var max_speed: float = 500.0        # forward top speed
@export var reverse_max_speed: float = 150.0
@export var accel: float = 600.0
@export var brake_accel: float = 400.0
@export var friction: float = 500.0

# --- Steering ---
@export var max_turn_speed: float = 180.0   # deg/sec at low speed
@export var min_turn_speed: float = 120.0   # deg/sec at high speed
@export var turn_slow_factor: float = 0.05 # base factor for turn slowdown

var velocity: Vector2 = Vector2.ZERO

func _process(delta: float) -> void:
	# --- INPUT ---
	var throttle: float = 0.0
	if Input.is_action_pressed("ui_up"):
		throttle = 1.0
	elif Input.is_action_pressed("ui_down"):
		throttle = -1.0

	var turn_input: float = 0.0
	if Input.is_action_pressed("ui_left"):
		turn_input = -1.0
	elif Input.is_action_pressed("ui_right"):
		turn_input = 1.0

	# --- FORWARD VECTOR ---
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)

	# --- ACCELERATION & BRAKE ---
	var forward_speed: float = velocity.dot(forward)
	var target_speed: float = 0.0

	if throttle > 0.0:
		target_speed = max_speed
		forward_speed = move_toward(forward_speed, target_speed, accel * delta)
	elif throttle < 0.0:
		target_speed = -reverse_max_speed
		if forward_speed > 0.0:
			# braking while moving forward
			forward_speed = move_toward(forward_speed, target_speed, brake_accel * delta)
		else:
			# reverse acceleration
			forward_speed = move_toward(forward_speed, target_speed, accel * delta)
	else:
		# natural friction
		forward_speed = move_toward(forward_speed, 0.0, friction * delta)

	# --- APPLY STRONGER TURN SLOWING ---
	if turn_input != 0.0 and abs(forward_speed) > 0.0:
		var speed_scale: float = clamp(abs(forward_speed) / max_speed, 0.0, 1.0)
		var turn_slow_amount: float = turn_slow_factor * 2.0 * abs(turn_input) * speed_scale * max_speed * delta
		if abs(forward_speed) > turn_slow_amount:
			forward_speed -= sign(forward_speed) * turn_slow_amount
		else:
			forward_speed = 0.0

	velocity = forward * forward_speed

	# --- TURNING ---
	if abs(forward_speed) > 0.1: # only allow turning if moving
		var speed_factor: float = clamp(abs(forward_speed) / max_speed, 0.0, 1.0)
		var current_turn_speed: float = lerp(max_turn_speed, min_turn_speed, speed_factor * 0.5)

		# reduce turn speed if braking in forward direction
		if throttle < 0.0 and forward_speed > 0.0:
			current_turn_speed *= 0.7

		# reverse steering if moving backward
		var steering_factor: float = 1.0
		if forward_speed < 0.0:
			steering_factor = -1.0

		global_rotation += deg_to_rad(turn_input * current_turn_speed * steering_factor * delta)

	# --- MOVE CAR ---
	global_position += velocity * delta
