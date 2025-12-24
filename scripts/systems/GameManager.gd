extends Node

# Multiplayer settings
const DEFAULT_PORT = 7777
const MAX_PLAYERS = 8

# Player data
var players := {}  # peer_id -> player_info
var local_player_id := 1

# Race state
var race_started := false
var selected_track := ""

# Session tracking
var session_active := false

# NEW: Spawn coordination
var spawn_ready := false
var players_spawned := {}  # peer_id -> bool

# Periodic sync timer
var sync_timer := 0.0
const SYNC_INTERVAL := 0.5  # Sync player list every 0.5 seconds

# Connection timeout
var connection_timeout := 0.0
const CONNECTION_TIMEOUT_DURATION := 10.0  # 10 seconds to connect
var is_connecting := false

# Signals
signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected()
signal all_players_spawned()
signal connection_failed()
signal client_registered()  # NEW: Emitted when client successfully registers with server

func _ready():
	# CRITICAL: Don't destroy this node when changing scenes
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta):
	# Server periodically syncs player list to all clients
	if is_server() and session_active:
		sync_timer += delta
		if sync_timer >= SYNC_INTERVAL:
			sync_timer = 0.0
			# Broadcast current player list to all clients
			sync_players.rpc(players)
	
	# Track connection timeout
	if is_connecting:
		connection_timeout += delta
		if connection_timeout >= CONNECTION_TIMEOUT_DURATION:
			print("Connection timeout!")
			_on_connection_failed()
			is_connecting = false

# HOST GAME
func host_game(host_name: String, port: int = DEFAULT_PORT) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		print("Failed to create server: ", error)
		return false
	
	multiplayer.multiplayer_peer = peer
	local_player_id = multiplayer.get_unique_id()
	
	# Add host as a player
	players[local_player_id] = {
		"name": host_name,
		"peer_id": local_player_id,
		"car_path": GameGlobals.selected_car_path,
		"ready": false
	}
	
	session_active = true
	
	print("Server created! ID: ", local_player_id)
	print("Session is now ACTIVE")
	return true

# JOIN GAME
func join_game(client_name: String, address: String, port: int = DEFAULT_PORT) -> bool:
	print("Attempting to connect to ", address, ":", port)
	
	# Temporarily suppress error spam from invalid addresses
	var original_print_error_messages = ProjectSettings.get_setting("debug/settings/stdout/print_error_messages")
	ProjectSettings.set_setting("debug/settings/stdout/print_error_messages", false)
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	# Restore error output
	ProjectSettings.set_setting("debug/settings/stdout/print_error_messages", original_print_error_messages)
	
	if error != OK:
		print("Failed to create client (Error code: ", error, ")")
		return false
	
	multiplayer.multiplayer_peer = peer
	local_player_id = multiplayer.get_unique_id()
	
	# Store player name for later registration
	players[local_player_id] = {
		"name": client_name,
		"peer_id": local_player_id,
		"car_path": GameGlobals.selected_car_path,
		"ready": false
	}
	
	session_active = true
	is_connecting = true
	connection_timeout = 0.0
	
	return true

# DISCONNECT
func disconnect_from_game():
	print("=== DISCONNECTING FROM GAME ===")
	
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		print("Multiplayer peer closed and cleared")
	
	players.clear()
	players_spawned.clear()
	race_started = false
	session_active = false
	spawn_ready = false
	
	print("Session is now INACTIVE")
	print("Players cleared")

# Check if this peer is the server
func is_server() -> bool:
	return multiplayer.is_server()

# Get local player info
func get_local_player():
	return players.get(local_player_id)

# Check if we're in an active multiplayer session
func is_in_session() -> bool:
	return session_active and players.size() > 0

# === CALLBACKS ===

func _on_player_connected(id: int):
	print("Player connected: ", id)

func _on_player_disconnected(id: int):
	print("Player disconnected: ", id)
	
	if players.has(id):
		var player_name = players[id]["name"]
		players.erase(id)
		players_spawned.erase(id)
		player_disconnected.emit(id)
		print(player_name, " left the game")

func _on_connected_to_server():
	print("Successfully connected to server!")
	is_connecting = false  # Stop timeout tracking
	local_player_id = multiplayer.get_unique_id()
	
	# Get stored player info
	var player_info = players.get(local_player_id, {
		"name": "Player",
		"peer_id": local_player_id,
		"car_path": GameGlobals.selected_car_path,
		"ready": false
	})
	
	# Register with server
	register_player.rpc_id(1, local_player_id, player_info)
	
	# IMPORTANT: Wait a bit for registration to complete, then notify lobby
	await get_tree().create_timer(0.3).timeout
	# Emit a local signal to tell lobby we're ready
	player_connected.emit(local_player_id, player_info)

func _on_connection_failed():
	print("Failed to connect to server")
	is_connecting = false
	
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	players.clear()
	session_active = false
	
	connection_failed.emit()

func _on_server_disconnected():
	print("Server disconnected")
	multiplayer.multiplayer_peer = null
	players.clear()
	players_spawned.clear()
	session_active = false
	spawn_ready = false
	server_disconnected.emit()

# === RPCs ===

# Client calls this to register with server
@rpc("any_peer", "reliable")
func register_player(id: int, player_info: Dictionary):
	if not is_server():
		return
	
	players[id] = player_info
	print("Player registered: ", player_info["name"], " (ID: ", id, ")")
	
	# Send all players to the new player
	sync_players.rpc_id(id, players)
	
	# IMPORTANT: Confirm registration back to the client
	confirm_registration.rpc_id(id)
	
	# Notify all other players about new player
	player_connected.emit(id, player_info)
	announce_player_joined.rpc(id, player_info)

# Server confirms successful registration to client
@rpc("authority", "reliable")
func confirm_registration():
	print("✓ Registration confirmed by server!")
	client_registered.emit()

# Server sends full player list to a client (or all clients)
@rpc("authority", "reliable")
func sync_players(all_players: Dictionary):
	# Merge incoming players with existing ones
	for peer_id in all_players.keys():
		players[peer_id] = all_players[peer_id]
	
	# Remove players that are no longer in the server's list
	var peers_to_remove = []
	for peer_id in players.keys():
		if not all_players.has(peer_id):
			peers_to_remove.append(peer_id)
	
	for peer_id in peers_to_remove:
		players.erase(peer_id)
	
	# Debug output only on first sync or when count changes
	if players.size() != all_players.size():
		print("Player list synced: ", players.keys())

# Server announces new player to all clients
@rpc("authority", "reliable")
func announce_player_joined(id: int, player_info: Dictionary):
	if not players.has(id):
		players[id] = player_info
		player_connected.emit(id, player_info)

# Player updates their selected car
@rpc("any_peer", "reliable")
func update_player_car(peer_id: int, car_path: String):
	if is_server():
		if players.has(peer_id):
			players[peer_id]["car_path"] = car_path
			print("Player ", peer_id, " updated car to: ", car_path)
			# Sync to all clients
			sync_car_update.rpc(peer_id, car_path)

# Server syncs car update to all clients
@rpc("authority", "reliable")
func sync_car_update(peer_id: int, car_path: String):
	if players.has(peer_id):
		players[peer_id]["car_path"] = car_path

# Player toggles ready state
@rpc("any_peer", "call_local", "reliable")
func set_player_ready(peer_id: int, is_ready: bool):
	if players.has(peer_id):
		players[peer_id]["ready"] = is_ready
		print(players[peer_id]["name"], " is ", "ready" if is_ready else "not ready")
		
		# If we're the server, broadcast to all clients
		if is_server():
			sync_ready_state.rpc(peer_id, is_ready)

# Server broadcasts ready state changes to all clients
@rpc("authority", "reliable")
func sync_ready_state(peer_id: int, is_ready: bool):
	if players.has(peer_id):
		players[peer_id]["ready"] = is_ready
		print("Synced ready state: ", players[peer_id]["name"], " is ", "ready" if is_ready else "not ready")

# Server starts the race
@rpc("authority", "call_local", "reliable")
func start_race(track_path: String):
	print("Starting race! Track: ", track_path)
	race_started = true
	spawn_ready = false
	players_spawned.clear()
	get_tree().change_scene_to_file(track_path)

# === NEW: OPTION C - SPAWN COORDINATION ===

# Called by track/spawner when it's ready to spawn cars
func prepare_spawning():
	spawn_ready = true
	players_spawned.clear()
	print("Spawn system ready")

# Server spawns a car for a specific player at a specific position
@rpc("authority", "call_local", "reliable")
func spawn_player_car(peer_id: int, car_scene_path: String, spawn_pos: Vector2, spawn_rot: float):
	if not spawn_ready:
		push_error("Spawn system not ready!")
		return
	
	print("Spawning car for peer ", peer_id, " at ", spawn_pos)
	
	# Load and instance the car
	var car_scene = load(car_scene_path)
	if not car_scene:
		push_error("Failed to load car scene: ", car_scene_path)
		return
	
	var car = car_scene.instantiate()
	car.name = "Car_" + str(peer_id)
	
	# Set position BEFORE adding to tree
	car.global_position = spawn_pos
	car.global_rotation = spawn_rot
	
	# Add multiplayer wrapper if it doesn't have one
	var wrapper = car.get_node_or_null("MultiplayerCarWrapper")
	if not wrapper:
		wrapper = preload("res://scripts/systems/MultiplayerCarWrapper.gd").new()
		wrapper.name = "MultiplayerCarWrapper"
		car.add_child(wrapper)
	
	# Set authority BEFORE adding to scene tree
	car.set_multiplayer_authority(peer_id)
	
	# Add to scene
	get_tree().current_scene.add_child(car)
	
	# Mark as spawned
	players_spawned[peer_id] = true
	print("Car spawned for peer ", peer_id, " | Spawned: ", players_spawned.size(), "/", players.size())
	
	# Check if all players spawned
	if players_spawned.size() == players.size():
		print("All players spawned!")
		all_players_spawned.emit()

# Client notifies server it's ready to receive spawn commands
@rpc("any_peer", "reliable")
func client_ready_for_spawn():
	var peer_id = multiplayer.get_remote_sender_id()
	print("Client ", peer_id, " ready for spawn")
	# Server can use this to coordinate spawn timing if needed
