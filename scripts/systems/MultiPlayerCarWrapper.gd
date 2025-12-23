extends Node
# Attach this as a CHILD of your car (not replacing the car script!)

@onready var car = get_parent()

var player_id := 1
var is_local := false

var remote_position := Vector2.ZERO
var remote_rotation := 0.0
var remote_velocity := Vector2.ZERO
const LERP_SPEED = 20.0

var sync_timer := 0.0
const SYNC_INTERVAL = 1.0 / 30.0

# Spawn locking
var spawn_position := Vector2.ZERO
var spawn_rotation := 0.0
var spawn_locked := true
var lock_time := 0.0
const LOCK_DURATION = 0.5  # 0.5 seconds at any FPS

const UI_NODE_PATHS = ["CanvasLayer"]

func _ready():
	# HIGHEST priority - run before everything else
	set_process_priority(-1000)
	set_physics_process_priority(-1000)
	
	# Store spawn position IMMEDIATELY
	spawn_position = car.global_position
	spawn_rotation = car.global_rotation
	
	print("\n=== SPAWN LOCK INIT ===")
	print("Car: ", car.name)
	print("Locked at: ", spawn_position, " rotation: ", rad_to_deg(spawn_rotation), "°")
	
	# IMMEDIATELY disable car's processing during spawn lock
	car.set_process(false)
	car.set_physics_process(false)
	print("Car processing DISABLED for spawn lock")
	
	# Don't check multiplayer until next frame - prevents race conditions
	call_deferred("_setup_multiplayer")

func _setup_multiplayer():
	if not multiplayer.has_multiplayer_peer():
		print("Solo mode - unlocking immediately")
		_unlock_spawn()
		return
	
	is_local = car.is_multiplayer_authority()
	player_id = car.get_multiplayer_authority()
	
	print("=== MULTIPLAYER SETUP ===")
	print("Peer ", player_id, " | Local: ", is_local)
	
	if is_local:
		car.add_to_group("local_player")
		_setup_camera(true)
		_setup_ui(true)
	else:
		car.add_to_group("remote_player")
		_setup_camera(false)
		_setup_ui(false)
		_disable_car_input()
		
		# CRITICAL: Initialize remote target to spawn position
		# This prevents lerping to (0,0) or stale positions
		remote_position = spawn_position
		remote_rotation = spawn_rotation
		remote_velocity = Vector2.ZERO
		
		print("Remote car initialized at spawn position")

func _physics_process(delta):
	if spawn_locked:
		lock_time += delta
		
		# FORCE car to spawn position - override everything
		car.global_position = spawn_position
		car.global_rotation = spawn_rotation
		
		# Zero out all velocity
		if "velocity" in car:
			car.velocity = Vector2.ZERO
		if "linear_velocity" in car:
			car.linear_velocity = Vector2.ZERO
		if "angular_velocity" in car:
			car.angular_velocity = 0.0
		
		# CRITICAL: Keep resetting remote targets during lock
		# This prevents the car from trying to lerp to received positions
		if not is_local:
			remote_position = spawn_position
			remote_rotation = spawn_rotation
			remote_velocity = Vector2.ZERO
		
		# Check if lock time expired
		if lock_time >= LOCK_DURATION:
			_unlock_spawn()
		
		return
	
	# Normal multiplayer sync after unlock
	if not multiplayer.has_multiplayer_peer():
		return
	
	if is_local:
		sync_timer += delta
		if sync_timer >= SYNC_INTERVAL:
			sync_timer = 0.0
			var vel = Vector2.ZERO
			if "velocity" in car:
				vel = car.velocity
			elif "linear_velocity" in car:
				vel = car.linear_velocity
			sync_car.rpc(car.global_position, car.rotation, vel)
	else:
		# Smoothly interpolate to remote position
		car.global_position = car.global_position.lerp(remote_position, LERP_SPEED * delta)
		car.rotation = lerp_angle(car.rotation, remote_rotation, LERP_SPEED * delta)
		if "velocity" in car:
			car.velocity = car.velocity.lerp(remote_velocity, LERP_SPEED * delta)

func _unlock_spawn():
	spawn_locked = false
	
	# RE-ENABLE car's processing
	car.set_process(true)
	car.set_physics_process(true)
	
	print("\n✓✓✓ SPAWN UNLOCKED ✓✓✓")
	print("Time locked: ", lock_time, " seconds")
	print("Final position: ", car.global_position)
	print("Target position: ", spawn_position)
	print("Difference: ", car.global_position.distance_to(spawn_position), " pixels")
	print("Car processing RE-ENABLED\n")

func _setup_camera(enable: bool):
	var cameras = _find_cameras(car)
	for camera in cameras:
		camera.enabled = enable
		if enable:
			camera.make_current()

func _find_cameras(node: Node) -> Array:
	var cameras = []
	for child in node.get_children():
		if child is Camera2D:
			cameras.append(child)
		if child.get_child_count() > 0:
			cameras.append_array(_find_cameras(child))
	return cameras

func _setup_ui(enable: bool):
	for ui_path in UI_NODE_PATHS:
		if car.has_node(ui_path):
			car.get_node(ui_path).visible = enable

@rpc("any_peer", "unreliable")
func sync_car(pos: Vector2, rot: float, vel: Vector2):
	# During spawn lock, we ignore all incoming sync data
	# The spawn lock will keep resetting our targets anyway
	if spawn_locked:
		return
	
	if not is_multiplayer_authority():
		remote_position = pos
		remote_rotation = rot
		remote_velocity = vel

func set_player_authority(peer_id: int):
	player_id = peer_id
	car.set_multiplayer_authority(peer_id)
	is_local = car.is_multiplayer_authority()

func _disable_car_input():
	car.set_process_input(false)
	car.set_process_unhandled_input(false)
	car.set_process_unhandled_key_input(false)
