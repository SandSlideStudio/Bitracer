extends CharacterBody2D

# ========== TUNABLE CAR STATS ==========
@export var max_speed: float = 360.0         # top speed on dirt
@export var accel: float = 680.0             # throttle power
@export var brake_accel: float = 900.0       # braking force
@export var friction: float = 520.0          # natural slowdown
@export var turn_speed: float = 3.4          # base turn rate
@export var turn_slow_factor: float = 0.6    # steering reduces speed
@export var rear_grip: float = 0.45          # lower = more oversteer (RWD feeling)
@export var front_grip: float = 0.85         # higher = more planted steering
@export var lateral_damp: float = 4.5        # sideways damping

# ========== INTERNAL ==========
var forward_dir: Vector2
var forward_speed: float = 0.0
var lateral_speed: float = 0.0


func _physics_process(delta: float) -> void:
	# -----------------------------------------
	# INPUT
	# -----------------------------------------
	var throttle: float = 0.0
	if Input.is_action_pressed("ui_up"):
		throttle = 1.0
	elif Input.is_action_pressed("ui_down"):
		throttle = -1.0

	var steer: float = 0.0
	if Input.is_action_pressed("ui_left"):
		steer = -1.0
	elif Input.is_action_pressed("ui_right"):
		steer = 1.0

	# -----------------------------------------
	# DIRECTIONS
	# -----------------------------------------
	forward_dir = Vector2.UP.rotated(rotation)
	var right_dir: Vector2 = forward_dir.orthogonal()

	# -----------------------------------------
	# SPLIT VELOCITY INTO FORWARD + LATERAL
	# -----------------------------------------
	forward_speed = velocity.dot(forward_dir)
	lateral_speed = velocity.dot(right_dir)

	# -----------------------------------------
	# ACCELERATION + BRAKING
	# -----------------------------------------
	if throttle > 0.0:
		forward_speed = move_toward(forward_speed, max_speed, accel * delta)
	elif throttle < 0.0:
		# braking when moving forward, otherwise reverse accel
		if forward_speed > 0.0:
			forward_speed = move_toward(forward_speed, 0.0, brake_accel * delta)
		else:
			forward_speed = move_toward(forward_speed, -max_speed * 0.4, accel * delta)
	else:
		# natural rolling resistance
		forward_speed = move_toward(forward_speed, 0.0, friction * delta)

	# -----------------------------------------
	# RWD STYLE LATERAL SLOP
	# -----------------------------------------
	var rear_lateral: float = lateral_speed * rear_grip
	var front_lateral: float = lateral_speed * front_grip
	lateral_speed = move_toward(lateral_speed, 0.0, lateral_damp * delta)

	# -----------------------------------------
	# COMBINE VELOCITY
	# -----------------------------------------
	velocity = forward_dir * forward_speed + right_dir * lateral_speed

	# -----------------------------------------
	# TURNING — REDUCED AT HIGH SPEED + WHEN THROTTLING
	# -----------------------------------------
	var speed_factor: float = clamp(abs(forward_speed) / max_speed, 0.0, 1.0)
	var steer_strength: float = turn_speed * (1.0 - speed_factor * turn_slow_factor)

	# prevent steering while standing still
	if abs(forward_speed) > 12.0:
		rotation += steer * steer_strength * delta

	# -----------------------------------------
	# FINAL MOVEMENT
	# -----------------------------------------
	move_and_slide()
