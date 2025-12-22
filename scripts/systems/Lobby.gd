extends Control

# Use get_node_or_null for safer access
@onready var player_name_input = get_node_or_null("Panel/VBoxContainer/NameInput")
@onready var host_button = get_node_or_null("Panel/VBoxContainer/HostButton")
@onready var join_button = get_node_or_null("Panel/VBoxContainer/JoinButton")
@onready var ip_input = get_node_or_null("Panel/VBoxContainer/IPInput")
@onready var player_list = get_node_or_null("Panel/VBoxContainer/PlayerList")
@onready var ready_button = get_node_or_null("Panel/VBoxContainer/ReadyButton")
@onready var start_button = get_node_or_null("Panel/VBoxContainer/StartButton")
@onready var back_button = get_node_or_null("Panel/VBoxContainer/BackButton")
@onready var select_car_button = get_node_or_null("Panel/VBoxContainer/SelectCarButton")
@onready var select_track_button = get_node_or_null("Panel/VBoxContainer/SelectTrackButton")

var in_lobby := false

func _ready():
	print("=== LOBBY READY ===")
	print("GameManager.session_active: ", GameManager.session_active)
	print("GameManager.players.size(): ", GameManager.players.size())
	
	# Simple check - use the explicit session flag
	if GameManager.session_active:
		print("Active session detected - showing lobby")
		in_lobby = true
	else:
		print("No active session - showing host/join screen")
		in_lobby = false
	
	# Check if all required nodes exist
	if not _check_nodes():
		push_error("Lobby UI nodes missing! Check scene structure.")
		return
	
	# Connect signals
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
	if join_button:
		join_button.pressed.connect(_on_join_pressed)
	if ready_button:
		ready_button.pressed.connect(_on_ready_pressed)
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if select_car_button:
		select_car_button.pressed.connect(_on_select_car_pressed)
	if select_track_button:
		select_track_button.pressed.connect(_on_select_track_pressed)
	
	GameManager.player_connected.connect(_on_player_connected)
	GameManager.player_disconnected.connect(_on_player_disconnected)
	GameManager.server_disconnected.connect(_on_server_disconnected)
	
	_update_ui()

func _check_nodes() -> bool:
	var required = [player_name_input, host_button, join_button, ip_input, 
					player_list, ready_button, start_button, back_button]
	for node in required:
		if node == null:
			return false
	return true

func _on_host_pressed():
	var player_name = player_name_input.text if player_name_input else "Host"
	if player_name.strip_edges().is_empty():
		player_name = "Host"
	
	print("Hosting game with name: ", player_name)
	if GameManager.host_game(player_name):
		in_lobby = true
		_update_ui()
		_refresh_player_list()
		print("Host successful!")
	else:
		print("Host failed!")

func _on_join_pressed():
	var player_name = player_name_input.text if player_name_input else "Player"
	if player_name.strip_edges().is_empty():
		player_name = "Player"
	
	var address = ip_input.text if ip_input else "127.0.0.1"
	if address.strip_edges().is_empty():
		address = "127.0.0.1"
	
	print("Joining game at ", address, " with name: ", player_name)
	if GameManager.join_game(player_name, address):
		in_lobby = true
		_update_ui()
		print("Join initiated...")
	else:
		print("Join failed!")

func _on_select_car_pressed():
	print("Going to car selector (session will persist)")
	get_tree().change_scene_to_file("res://scenes/main/CarSelector.tscn")

func _on_select_track_pressed():
	# Only host can select track
	if not GameManager.is_server():
		print("Only host can select track!")
		return
	
	print("Going to track selector (session will persist)")
	get_tree().change_scene_to_file("res://scenes/main/TrackSelector.tscn")

func _on_ready_pressed():
	var local_player = GameManager.get_local_player()
	if local_player:
		var is_ready = !local_player["ready"]
		print("Setting ready state to: ", is_ready)
		GameManager.set_player_ready.rpc(GameManager.local_player_id, is_ready)
		_update_ready_button()

func _on_start_pressed():
	if not GameManager.is_server():
		print("Not server - can't start!")
		return
	
	# Check if track is selected
	if GameGlobals.selected_track_path == "":
		print("Please select a track first!")
		return
	
	# Check if all players are ready
	var all_ready = true
	for player in GameManager.players.values():
		if not player["ready"]:
			all_ready = false
			print("Player ", player["name"], " is not ready")
			break
	
	if not all_ready:
		print("Not all players are ready!")
		return
	
	# Start the race on selected track
	print("Starting race!")
	GameManager.start_race.rpc(GameGlobals.selected_track_path)

func _on_back_pressed():
	if in_lobby:
		print("Leaving lobby and disconnecting")
		GameManager.disconnect_from_game()
		in_lobby = false
		# Also reset multiplayer flag
		GameGlobals.is_multiplayer = false
		_update_ui()
	else:
		print("Going back to main menu")
		get_tree().change_scene_to_file("res://scenes/main/MainMenu.tscn")

func _on_player_connected(_peer_id: int, _player_info: Dictionary):
	print("Player connected event received")
	_refresh_player_list()

func _on_player_disconnected(_peer_id: int):
	print("Player disconnected event received")
	_refresh_player_list()

func _on_server_disconnected():
	print("Server disconnected!")
	in_lobby = false
	GameGlobals.is_multiplayer = false
	_update_ui()

func _update_ui():
	print("Updating UI - in_lobby: ", in_lobby)
	
	# Show/hide elements based on lobby state
	if player_name_input:
		player_name_input.visible = !in_lobby
	if host_button:
		host_button.visible = !in_lobby
	if join_button:
		join_button.visible = !in_lobby
	if ip_input:
		ip_input.visible = !in_lobby
	
	if player_list:
		player_list.visible = in_lobby
	if ready_button:
		ready_button.visible = in_lobby
	if select_car_button:
		select_car_button.visible = in_lobby
	if select_track_button:
		select_track_button.visible = in_lobby and GameManager.is_server()
	if start_button:
		start_button.visible = in_lobby and GameManager.is_server()
	
	if back_button:
		back_button.text = "Leave Lobby" if in_lobby else "Back"
	
	if in_lobby:
		_refresh_player_list()
		_update_ready_button()

func _update_ready_button():
	if not ready_button:
		return
	
	var local_player = GameManager.get_local_player()
	if local_player:
		ready_button.text = "Unready" if local_player["ready"] else "Ready"

func _refresh_player_list():
	if not player_list:
		return
	
	player_list.text = "Players:\n"
	
	for player in GameManager.players.values():
		var ready_status = "[READY]" if player["ready"] else "[NOT READY]"
		var host_marker = " (HOST)" if player["peer_id"] == 1 else ""
		player_list.text += player["name"] + " " + ready_status + host_marker + "\n"
	
	# Show selected track if host has chosen one
	if GameGlobals.selected_track_path != "":
		player_list.text += "\nTrack: Selected"
	else:
		player_list.text += "\nTrack: Not selected"
