extends Node2D

@export var cam_rotating: Camera2D
@export var cam_fixed: Camera2D

var use_rotating_camera: bool = true

func _ready():
	# Ensure cameras are assigned
	if cam_rotating == null or cam_fixed == null:
		push_error("Camera_Controller: assign both cameras in Inspector!")
		return
	# Activate rotating camera by default
	cam_rotating.make_current()
	# no need to call clear_current(), Godot handles deactivating others automatically

func _input(event):
	if event.is_action_pressed("toggle_camera_rotation"):
		use_rotating_camera = !use_rotating_camera
		if use_rotating_camera:
			cam_rotating.make_current()
		else:
			cam_fixed.make_current()
