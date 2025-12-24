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

# Store original colors for validation
var original_name_color: Color
var original_ip_color: Color

# Track if validation is in progress
var validating_name := false
var validating_ip := false

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
	
	# Store original colors
	if player_name_input:
		original_name_color = player_name_input.get_theme_color("font_color", "LineEdit")
	if ip_input:
		original_ip_color = ip_input.get_theme_color("font_color", "LineEdit")
	
	# Pre-fill server address for convenience
	if ip_input:
		ip_input.placeholder_text = "yourdomain.com or IP address"
	
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
	GameManager.connection_failed.connect(_on_connection_failed_signal)
	GameManager.client_registered.connect(_on_client_registered)
	
	_update_ui()

func _process(_delta):
	# Continuously refresh player list while in lobby
	if in_lobby:
		_refresh_player_list()

func _check_nodes() -> bool:
	var required = [player_name_input, host_button, join_button, ip_input, 
					player_list, ready_button, start_button, back_button]
	for node in required:
		if node == null:
			return false
	return true

func _validate_name_input() -> bool:
	if not player_name_input:
		return false
	
	# Block if already validating
	if validating_name:
		return false
	
	var name_text = player_name_input.text.strip_edges()
	
	# Check if empty
	if name_text.is_empty():
		validating_name = true
		player_name_input.text = "Please input name first"
		player_name_input.add_theme_color_override("font_color", Color.RED)
		player_name_input.editable = false
		# Clear after a moment and restore
		await get_tree().create_timer(1.5).timeout
		if player_name_input:
			player_name_input.text = ""
			player_name_input.add_theme_color_override("font_color", original_name_color)
			player_name_input.editable = true
		validating_name = false
		return false
	
	# Check if name is taken (only when joining)
	if GameManager.session_active:
		for player in GameManager.players.values():
			if player["name"].to_lower() == name_text.to_lower():
				validating_name = true
				var original_text = player_name_input.text
				player_name_input.text = "Name already taken!"
				player_name_input.add_theme_color_override("font_color", Color.RED)
				player_name_input.editable = false
				await get_tree().create_timer(1.5).timeout
				if player_name_input:
					player_name_input.text = original_text
					player_name_input.add_theme_color_override("font_color", original_name_color)
					player_name_input.editable = true
				validating_name = false
				return false
	
	return true

func _validate_ip_input() -> bool:
	if not ip_input:
		return false
	
	# Block if already validating
	if validating_ip:
		return false
	
	var ip_text = ip_input.text.strip_edges()
	
	if ip_text.is_empty():
		validating_ip = true
		ip_input.text = "Please input IP first"
		ip_input.add_theme_color_override("font_color", Color.RED)
		ip_input.editable = false
		# Clear after a moment and restore
		await get_tree().create_timer(1.5).timeout
		if ip_input:
			ip_input.text = ""
			ip_input.add_theme_color_override("font_color", original_ip_color)
			ip_input.editable = true
		validating_ip = false
		return false
	
	return true

func _on_host_pressed():
	# Validate name
	if not await _validate_name_input():
		return
	
	var player_name = player_name_input.text.strip_edges()
	
	print("Hosting game with name: ", player_name)
	if GameManager.host_game(player_name):
		in_lobby = true
		_update_ui()
		_refresh_player_list()
		print("Host successful!")
	else:
		print("Host failed!")

func _on_join_pressed():
	# Validate name
	if not await _validate_name_input():
		return
	
	# Validate IP
	if not await _validate_ip_input():
		return
	
	var player_name = player_name_input.text.strip_edges()
	var address = ip_input.text.strip_edges()
	
	print("Joining game at ", address, " with name: ", player_name)
	
	# Show "Connecting..." status
	if ip_input:
		ip_input.text = "Connecting..."
		ip_input.add_theme_color_override("font_color", Color.YELLOW)
		ip_input.editable = false
	
	if GameManager.join_game(player_name, address):
		# Wait for either success or failure
		# The connection_failed signal will restore the UI if it fails
		print("Join initiated...")
	else:
		print("Join failed immediately!")
		# Restore IP input
		if ip_input:
			ip_input.text = address
			ip_input.add_theme_color_override("font_color", original_ip_color)
			ip_input.editable = true

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
		
		# Immediately update local state for instant feedback
		local_player["ready"] = is_ready
		_update_ready_button()
		_refresh_player_list()

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
	print("Player connected event received - Peer: ", _peer_id)
	# Just refresh the list - lobby entry is handled by client_registered
	_refresh_player_list()

func _on_player_disconnected(_peer_id: int):
	print("Player disconnected event received")
	_refresh_player_list()

func _on_server_disconnected():
	print("Server disconnected!")
	in_lobby = false
	GameGlobals.is_multiplayer = false
	_update_ui()

func _on_connection_failed_signal():
	print("Connection failed - showing error to user")
	in_lobby = false
	GameGlobals.is_multiplayer = false
	_update_ui()
	
	# Show error message in IP field
	if ip_input:
		var failed_address = ip_input.text
		ip_input.text = "No lobby found"
		ip_input.add_theme_color_override("font_color", Color.RED)
		ip_input.editable = false
		
		await get_tree().create_timer(2.0).timeout
		
		if ip_input:
			ip_input.text = failed_address
			ip_input.add_theme_color_override("font_color", original_ip_color)
			ip_input.editable = true

func _on_client_registered():
	print("Client successfully registered - entering lobby!")
	
	# This is the definitive "we're in!" signal
	if not in_lobby:
		in_lobby = true
		_update_ui()
		
		# Restore IP input
		if ip_input:
			ip_input.add_theme_color_override("font_color", original_ip_color)
			ip_input.editable = true
		
		_refresh_player_list()

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
