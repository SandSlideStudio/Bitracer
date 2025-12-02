extends RigidBody2D

@export var accel := 800.0
@export var max_speed := 400.0
@export var steering := 3.0
@export var drift_factor := 0.15
@export var linear_friction := 2.0

func _ready():
	gravity_scale = 0
	linear_damp = 0
	angular_damp = 0

func _physics_process(delta):
	# Input
	var forward_input = Input.get_action_strength("ui_up") - Input.get_action_strength("ui_down")
	var steer_input = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")

	var forward = -transform.y
	var right = transform.x

	# Apply forward/backward force
	apply_central_force(forward * accel * forward_input)

	# Limit max speed
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

	# Lateral drift damping
	var lateral_speed = right.dot(linear_velocity)
	linear_velocity -= right * lateral_speed * drift_factor

	# Steering only scales with forward motion
	var forward_speed = forward.dot(linear_velocity)
	if abs(forward_speed) > 10:
		rotation += steer_input * steering * (forward_speed / max_speed) * delta

	# Base linear friction
	linear_velocity = linear_velocity.move_toward(Vector2.ZERO, linear_friction * delta)
