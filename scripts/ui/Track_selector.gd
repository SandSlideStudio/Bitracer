extends Control

const TRACKS := [
	{"name": "Coralus Iceway", "path": "res://scenes/Main/Coralus_Iceway+Car.tscn"},
]

var current_index := 0

@onready var track_label = $Panel/VBoxContainer/TrackLabel
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer

func _ready():
	$Panel/VBoxContainer/HBoxContainer/BtnPrev.pressed.connect(_cycle.bind(-1))
	$Panel/VBoxContainer/HBoxContainer/BtnNext.pressed.connect(_cycle.bind(1))
	$Panel/VBoxContainer/BtnPlay.pressed.connect(_play)
	_update_label()

func _cycle(dir: int):
	current_index = (current_index + dir + TRACKS.size()) % TRACKS.size()
	_update_label()

func _update_label():
	track_label.text = TRACKS[current_index]["name"]

func _play():
	sfx_player.play()
	get_tree().change_scene_to_file(TRACKS[current_index]["path"])

func get_selected_track_path() -> String:
	return TRACKS[current_index]["path"]
