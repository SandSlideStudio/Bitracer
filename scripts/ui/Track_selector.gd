extends Control

# Official tracks
const OFFICIAL_TRACKS := [
	{"name": "Coralus Iceway", "path": "res://scenes/track/Track+Car/Coralus_Iceway+SELECTOR.tscn"},
	{"name": "Grass Lands Trail (long)", "path": "res://scenes/track/Track+Car/GrassLandsTrailLONG+SELECTOR.tscn"},
	{"name": "Grass Lands Trail (short)", "path": "res://scenes/track/Track+Car/GrassLandsTrailSHORT+SELECTOR.tscn"},
]

# Folder to auto-scan for modded tracks
const MOD_TRACK_FOLDER := "res://mods/tracks/"

var official_tracks := []
var mod_tracks := []
var current_mode := ""  # "official" or "mods"
var current_index := 0
var in_mode_select := true

@onready var track_label = $Panel/VBoxContainer/TrackLabel
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer if has_node("SFXPlayer") else null

func _ready():
	print("=== TRACK SELECTOR READY ===")
	print("Is in multiplayer session: ", GameManager.is_in_session())
	print("Players in session: ", GameManager.players.keys())
	
	_load_tracks()
	$Panel/VBoxContainer/HBoxContainer/BtnPrev.pressed.connect(_cycle.bind(-1))
	$Panel/VBoxContainer/HBoxContainer/BtnNext.pressed.connect(_cycle.bind(1))
	$Panel/VBoxContainer/BtnPlay.pressed.connect(_on_select)
	_update_ui()

func _load_tracks():
	# Load official tracks
	official_tracks = OFFICIAL_TRACKS.duplicate()
	
	# Auto-scan mods folder for modded tracks
	var dir = DirAccess.open(MOD_TRACK_FOLDER)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".tscn"):
				var track_path = MOD_TRACK_FOLDER + file_name
				var display_name = file_name.replace(".tscn", "").replace("_", " ").replace("+", " ")
				mod_tracks.append({"name": display_name, "path": track_path})
			
			file_name = dir.get_next()
		
		dir.list_dir_end()
	
	# Auto-skip mode selection if no mods exist
	if mod_tracks.size() == 0:
		current_mode = "official"
		in_mode_select = false

func _get_current_tracks() -> Array:
	return official_tracks if current_mode == "official" else mod_tracks

func _cycle(dir: int):
	if in_mode_select:
		# Cycle between Official and Mods
		current_index = (current_index + dir + 2) % 2
	else:
		# Cycle between tracks
		var tracks = _get_current_tracks()
		if tracks.size() == 0:
			return
		current_index = (current_index + dir + tracks.size()) % tracks.size()
	_update_ui()

func _on_select():
	if in_mode_select:
		# Player selected a mode
		current_mode = "official" if current_index == 0 else "mods"
		in_mode_select = false
		current_index = 0
		_update_ui()
	else:
		# Player selected a track
		var tracks = _get_current_tracks()
		if tracks.size() == 0:
			return
		
		# Store selected track path and name
		GameGlobals.selected_track_path = tracks[current_index]["path"]
		GameGlobals.selected_track_name = tracks[current_index]["name"]
		print("Track selected: ", tracks[current_index]["name"])
		
		if sfx_player:
			sfx_player.play()
			await sfx_player.finished
		
		# Return to appropriate screen
		print("Returning to appropriate screen...")
		print("Is multiplayer: ", GameGlobals.is_multiplayer)
		print("In session: ", GameManager.is_in_session())
		
		if GameGlobals.is_multiplayer and GameManager.is_in_session():
			# Return to lobby (session persists!)
			print("Returning to lobby with active session")
			get_tree().change_scene_to_file("res://scenes/main/Lobby.tscn")
		else:
			# Start race in solo mode
			print("Starting race (solo mode)")
			get_tree().change_scene_to_file(tracks[current_index]["path"])

func _update_ui():
	if in_mode_select:
		# Show mode selection
		track_label.text = "Official Tracks" if current_index == 0 else "Modded Tracks"
		$Panel/VBoxContainer/BtnPlay.text = "Select"
	else:
		# Show track selection
		var tracks = _get_current_tracks()
		if tracks.size() > 0:
			track_label.text = tracks[current_index]["name"]
		else:
			track_label.text = "No tracks available"
		
		if GameGlobals.is_multiplayer and GameManager.is_in_session():
			$Panel/VBoxContainer/BtnPlay.text = "Confirm"
		else:
			$Panel/VBoxContainer/BtnPlay.text = "Race"

func get_selected_track_path() -> String:
	var tracks = _get_current_tracks()
	return tracks[current_index]["path"] if tracks.size() > 0 else ""
