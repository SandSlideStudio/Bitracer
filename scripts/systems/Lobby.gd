extends Control

# Use get_node_or_null for safer access
@onready var player_name_input = get_node_or_null("NameInput")
@onready var host_button = get_node_or_null("HostButton")
@onready var join_button = get_node_or_null("JoinButton")
@onready var ip_input = get_node_or_null("IPInput")
@onready var player_list = get_node_or_null("PlayerList")
@onready var ready_button = get_node_or_null("ReadyButton")
@onready var start_button = get_node_or_null("StartButton")
@onready var back_button = get_node_or_null("BackButton")
@onready var select_car_button = get_node_or_null("SelectCarButton")
@onready var select_track_button = get_node_or_null("SelectTrackButton")

var in_lobby := false

# Store original colors for validation
var original_name_color: Color
var original_ip_color: Color

# Track if validation is in progress
var validating_name := false
var validating_ip := false

# Store the last valid address for restoration
var last_valid_address := ""

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
	
	# Store original colors and set character limits
	if player_name_input:
		original_name_color = player_name_input.get_theme_color("font_color", "LineEdit")
		player_name_input.max_length = 16
	if ip_input:
		original_ip_color = ip_input.get_theme_color("font_color", "LineEdit")
		ip_input.max_length = 100
	
	# Pre-fill server address for convenience
	if ip_input:
		ip_input.placeholder_text = "Server address or domain"
	
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
		player_name_input.text = "Input name first"
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
				player_name_input.text = "This name is taken"
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

func _is_valid_ipv4(ip: String) -> bool:
	"""Check if string is a valid IPv4 address"""
	var parts = ip.split(".")
	if parts.size() != 4:
		return false
	
	for part in parts:
		if not part.is_valid_int():
			return false
		var num = part.to_int()
		if num < 0 or num > 255:
			return false
	
	return true

func _is_valid_domain(domain: String) -> bool:
	"""Check if string is a valid domain name"""
	# Basic domain validation - at least one dot and valid characters
	if domain.length() < 3:
		return false
	
	# Check for valid domain characters (letters, numbers, dots, hyphens)
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9][a-zA-Z0-9-\\.]*[a-zA-Z0-9]$")
	
	if not regex.search(domain):
		return false
	
	# Must contain at least one dot
	if not "." in domain:
		return false
	
	return true

func _parse_address_and_port(input: String) -> Dictionary:
	"""Parse address into host and port components"""
	var result = {"host": "", "port": 0}
	
	# Check if there's a port specified
	var parts = input.split(":")
	
	if parts.size() == 1:
		# No port specified
		result["host"] = parts[0]
		result["port"] = 0
	elif parts.size() == 2:
		# Port specified
		result["host"] = parts[0]
		if parts[1].is_valid_int():
			result["port"] = parts[1].to_int()
		else:
			# Invalid port, return empty result
			return {"host": "", "port": 0}
	else:
		# Too many colons, invalid format
		return {"host": "", "port": 0}
	
	return result

func _validate_ip_input() -> bool:
	if not ip_input:
		return false
	
	# Block if already validating
	if validating_ip:
		return false
	
	var ip_text = ip_input.text.strip_edges()
	
	if ip_text.is_empty():
		validating_ip = true
		ip_input.text = "Server address missing"
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
	
	# Parse the address
	var parsed = _parse_address_and_port(ip_text)
	
	if parsed["host"].is_empty():
		validating_ip = true
		ip_input.text = "Invalid address format"
		ip_input.add_theme_color_override("font_color", Color.RED)
		ip_input.editable = false
		await get_tree().create_timer(1.5).timeout
		if ip_input:
			ip_input.text = ""
			ip_input.add_theme_color_override("font_color", original_ip_color)
			ip_input.editable = true
		validating_ip = false
		return false
	
	# Validate the host part
	var is_valid = _is_valid_ipv4(parsed["host"]) or _is_valid_domain(parsed["host"])
	
	if not is_valid:
		validating_ip = true
		var original_text = ip_input.text
		ip_input.text = "Invalid IP or domain"
		ip_input.add_theme_color_override("font_color", Color.RED)
		ip_input.editable = false
		await get_tree().create_timer(1.5).timeout
		if ip_input:
			ip_input.text = original_text
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

func _try_connection_with_ports(player_name: String, host: String, custom_port: int, is_domain: bool):
	"""Try connecting with different port configurations"""
	var ports_to_try = []
	
	if custom_port > 0:
		# User specified a port - try it first
		ports_to_try.append(custom_port)
		# Then try default port
		if custom_port != 7777:
			ports_to_try.append(7777)
	elif is_domain:
		# For domains without port, try common web ports and game port
		ports_to_try = [80, 443, 7777]
	else:
		# For IPs without port, just try default
		ports_to_try = [7777]
	
	# Try each port in sequence
	for port in ports_to_try:
		var address = host + ":" + str(port)
		print("Trying connection to: ", address)
		
		if GameManager.join_game(player_name, address):
			print("Join initiated with port ", port)
			# Wait a bit to see if connection succeeds
			await get_tree().create_timer(2.0).timeout
			
			# If we're in lobby, connection succeeded
			if in_lobby:
				print("Connection successful!")
				return
		
		print("Port ", port, " failed, trying next...")
	
	# All ports failed
	print("All connection attempts failed")
	_on_connection_failed_signal()

func _on_join_pressed():
	# Validate name
	if not await _validate_name_input():
		return
	
	# Validate IP/domain
	if not await _validate_ip_input():
		return
	
	var player_name = player_name_input.text.strip_edges()
	var input_address = ip_input.text.strip_edges()
	
	# Store for restoration on failure
	last_valid_address = input_address
	
	# Parse the address
	var parsed = _parse_address_and_port(input_address)
	var host = parsed["host"]
	var custom_port = parsed["port"]
	var is_domain = _is_valid_domain(host)
	
	print("Joining game at ", host, " (port: ", custom_port if custom_port > 0 else "default", ") with name: ", player_name)
	
	# Show "Connecting..." status
	if ip_input:
		ip_input.text = "Connecting..."
		ip_input.add_theme_color_override("font_color", Color.YELLOW)
		ip_input.editable = false
	
	# Try connection with smart port handling
	_try_connection_with_ports(player_name, host, custom_port, is_domain)

func _on_select_car_pressed():
	print("Going to car selector")
	get_tree().change_scene_to_file("res://scenes/main/CarSelector.tscn")

func _on_select_track_pressed():
	# Only host can select track
	if not GameManager.is_server():
		print("Only host can select track!")
		return
	
	print("Going to track selector")
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
	
	# Show error message in IP field, then restore original address
	if ip_input:
		ip_input.text = "Connection failed"
		ip_input.add_theme_color_override("font_color", Color.RED)
		ip_input.editable = false
		
		await get_tree().create_timer(2.0).timeout
		
		if ip_input:
			# Restore the address they tried to connect to
			ip_input.text = last_valid_address
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
		# Show the track name stored in GameGlobals (set by TrackSelector)
		var track_name = GameGlobals.get("selected_track_name")
		if track_name and track_name != "":
			player_list.text += "\nTrack: " + track_name
		else:
			# Fallback to extracting from path if name not stored
			track_name = GameGlobals.selected_track_path.get_file().get_basename()
			player_list.text += "\nTrack: " + track_name
	else:
		player_list.text += "\nTrack: Not selected"
