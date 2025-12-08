extends Control

var tracks := [
	{"name": "Coralus Iceway", "path": "res://scenes/Main/Coralus_Iceway+Car.tscn"}
]

var current_index := 0

@onready var track_label = $Panel/VBoxContainer/TrackLabel
@onready var btn_prev = $Panel/VBoxContainer/HBoxContainer/BtnPrev
@onready var btn_next = $Panel/VBoxContainer/HBoxContainer/BtnNext
@onready var btn_play = $Panel/VBoxContainer/BtnPlay
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer

func _ready():
	btn_prev.pressed.connect(_on_prev_pressed)
	btn_next.pressed.connect(_on_next_pressed)
	btn_play.pressed.connect(_on_play_pressed)

	_update_track_label()

func _update_track_label():
	track_label.text = tracks[current_index]["name"]

func _on_prev_pressed():
	current_index = (current_index - 1 + tracks.size()) % tracks.size()
	_update_track_label()

func _on_next_pressed():
	current_index = (current_index + 1) % tracks.size()
	_update_track_label()

func _on_play_pressed():
	sfx_player.play()
	get_tree().change_scene_to_file(tracks[current_index]["path"])

func get_selected_track_path() -> String:
	return tracks[current_index]["path"]
