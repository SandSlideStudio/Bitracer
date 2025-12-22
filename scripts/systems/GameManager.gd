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

# Signals
signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected()

func _ready():
	# CRITICAL: Don't destroy this node when changing scenes
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

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
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		print("Failed to create client: ", error)
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
	
	print("Attempting to connect to ", address, ":", port)
	return true

# DISCONNECT
func disconnect_from_game():
	print("=== DISCONNECTING FROM GAME ===")
	
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		print("Multiplayer peer closed and cleared")
	
	players.clear()
	race_started = false
	session_active = false
	
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
		player_disconnected.emit(id)
		print(player_name, " left the game")

func _on_connected_to_server():
	print("Successfully connected to server!")
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

func _on_connection_failed():
	print("Failed to connect to server")
	multiplayer.multiplayer_peer = null
	session_active = false

func _on_server_disconnected():
	print("Server disconnected")
	multiplayer.multiplayer_peer = null
	players.clear()
	session_active = false
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
	
	# Notify all other players about new player
	player_connected.emit(id, player_info)
	announce_player_joined.rpc(id, player_info)

# Server sends full player list to a client
@rpc("authority", "reliable")
func sync_players(all_players: Dictionary):
	players = all_players
	print("Received player list: ", players.keys())

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

# Server starts the race
@rpc("authority", "call_local", "reliable")
func start_race(track_path: String):
	print("Starting race! Track: ", track_path)
	race_started = true
	get_tree().change_scene_to_file(track_path)
