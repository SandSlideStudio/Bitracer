extends Control

# Car definitions with categories
const CARS := [
	# GT3 Cars
	{
		"category": "Single seater Custom",
		"name": "Default Car",
		"path": "res://scenes/player/Car/Car_Arcade_Physics_with_rpm+gearshifts.tscn",
		"description": "What can i say? Its the default car"
	},
	{
		"category": "Rally",
		"name": "Rally",
		"path": "res://scenes/player/Car/Car_Arcade_Rally_Physics.tscn",
		"description": "This fucker is quite shit"
	},
	{
		"category": "Karts",
		"name": "Custom kart",
		"path": "res://scenes/player/Car/GoKart.tscn",
		"description": "Its one hell of a go kart"
	},
]

# Folder to auto-scan for modded cars
const MOD_CAR_FOLDER := "res://mods/Cars/"

var categories := {}
var category_names := []
var mod_cars := []

var current_selection_level := 0
var current_category_index := 0
var current_car_index := 0
var selected_category := ""

@onready var car_label = $Panel/VBoxContainer/CarLabel
@onready var description_label = $Panel/VBoxContainer/DescriptionLabel
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer if has_node("SFXPlayer") else null

@onready var title_label = $Panel/VBoxContainer/Title if has_node("Panel/VBoxContainer/Title") else null
@onready var back_button = $Panel/VBoxContainer/BtnBack if has_node("Panel/VBoxContainer/BtnBack") else null

func _ready():
	print("=== CAR SELECTOR READY ===")
	print("Is in multiplayer session: ", GameManager.is_in_session())
	print("Players in session: ", GameManager.players.keys())
	
	_load_cars()
	$Panel/VBoxContainer/HBoxContainer/BtnPrev.pressed.connect(_cycle.bind(-1))
	$Panel/VBoxContainer/HBoxContainer/BtnNext.pressed.connect(_cycle.bind(1))
	$Panel/VBoxContainer/BtnSelect.pressed.connect(_on_select)
	
	if back_button:
		back_button.pressed.connect(_on_back)
	
	_update_ui()

func _load_cars():
	for car in CARS:
		var category = car.get("category", "Uncategorized")
		
		if not categories.has(category):
			categories[category] = []
			category_names.append(category)
		
		categories[category].append(car)
	
	var dir = DirAccess.open(MOD_CAR_FOLDER)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".tscn"):
				var car_path = MOD_CAR_FOLDER + file_name
				var display_name = file_name.replace(".tscn", "").replace("_", " ").replace("+", " ")
				mod_cars.append({
					"name": display_name,
					"path": car_path,
					"description": "Modded car"
				})
			
			file_name = dir.get_next()
		
		dir.list_dir_end()
	
	if mod_cars.size() > 0:
		categories["Mods"] = mod_cars
		category_names.append("Mods")

func _cycle(dir: int):
	if current_selection_level == 0:
		current_category_index = (current_category_index + dir + category_names.size()) % category_names.size()
		current_car_index = 0
	else:
		var cars_in_category = categories[selected_category]
		current_car_index = (current_car_index + dir + cars_in_category.size()) % cars_in_category.size()
	
	_update_ui()

func _on_select():
	if current_selection_level == 0:
		selected_category = category_names[current_category_index]
		current_selection_level = 1
		current_car_index = 0
		_update_ui()
	else:
		var cars_in_category = categories[selected_category]
		var selected_car = cars_in_category[current_car_index]
		
		# Save selected car path
		GameGlobals.selected_car_path = selected_car["path"]
		print("Car selected: ", selected_car["name"])
		
		# Update player's car in multiplayer (session persists!)
		if GameManager.is_in_session():
			print("Updating car in active session...")
			if GameManager.players.has(GameManager.local_player_id):
				GameManager.players[GameManager.local_player_id]["car_path"] = selected_car["path"]
				
				# Sync to server if we're not the server
				if not GameManager.is_server():
					GameManager.update_player_car.rpc_id(1, GameManager.local_player_id, selected_car["path"])
				else:
					# Server broadcasts to all clients
					GameManager.sync_car_update.rpc(GameManager.local_player_id, selected_car["path"])
				print("Car updated in session!")
		
		if sfx_player:
			sfx_player.play()
			await sfx_player.finished
		
		_proceed_to_next_screen()

func _on_back():
	if current_selection_level == 1:
		current_selection_level = 0
		_update_ui()
	else:
		_return_to_previous_screen()

func _proceed_to_next_screen():
	print("Proceeding to next screen...")
	print("Is multiplayer: ", GameGlobals.is_multiplayer)
	print("In session: ", GameManager.is_in_session())
	
	if GameGlobals.is_multiplayer and GameManager.is_in_session():
		# Return to lobby (session persists because GameManager is autoload)
		print("Returning to lobby with active session")
		# The lobby will automatically detect the car change via _check_for_car_updates()
		get_tree().change_scene_to_file("res://scenes/main/Lobby.tscn")
	else:
		# Solo mode - go to track selector
		print("Going to track selector (solo mode)")
		get_tree().change_scene_to_file("res://scenes/main/TrackSelector.tscn")

func _return_to_previous_screen():
	if GameGlobals.is_multiplayer and GameManager.is_in_session():
		# Return to lobby
		get_tree().change_scene_to_file("res://scenes/main/Lobby.tscn")
	else:
		# Return to main menu
		get_tree().change_scene_to_file("res://scenes/main/MainMenu.tscn")

func _update_ui():
	if back_button:
		back_button.visible = true
	
	if current_selection_level == 0:
		var category = category_names[current_category_index]
		var car_count = categories[category].size()
		
		car_label.text = category
		description_label.text = str(car_count) + (" car" if car_count == 1 else " cars") + " in this category"
		$Panel/VBoxContainer/BtnSelect.text = "Select Category"
		
		if title_label:
			title_label.text = "SELECT CATEGORY"
	else:
		var cars_in_category = categories[selected_category]
		var selected_car = cars_in_category[current_car_index]
		
		car_label.text = selected_car["name"]
		description_label.text = selected_car.get("description", "")
		$Panel/VBoxContainer/BtnSelect.text = "Confirm Car"
		
		if title_label:
			title_label.text = "SELECT CAR - " + selected_category
