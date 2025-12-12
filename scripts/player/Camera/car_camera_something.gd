extends Camera2D

@export var car_path: NodePath 
@export var follow_rotation: bool = true
@export var position_smooth_speed: float = 8.0
@export var rotation_smooth_speed: float = 6.0

var car: Node2D
var target_position: Vector2
var target_rotation: float = 0.0

func _ready():
	car = get_node_or_null(car_path)
	if car == null:
		push_error("Camera2D: car_path not assigned or invalid")
		return
	target_position = global_position
	if follow_rotation:
		target_rotation = -car.global_rotation

func _process(delta):
	if car == null:
		return

	# Smooth position follow
	target_position = target_position.lerp(car.global_position, 1.0 - exp(-position_smooth_speed * delta))
	global_position = target_position

	# Smooth rotation follow
	if follow_rotation:
		target_rotation = -car.global_rotation
	global_rotation = lerp_angle(global_rotation, target_rotation, 1.0 - exp(-rotation_smooth_speed * delta))
