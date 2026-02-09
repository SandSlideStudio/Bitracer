extends Node

# Global storage for player selections
var selected_car_path: String = "res://scenes/player/Car/Car_Arcade_Physics_with_rpm+gearshifts.tscn"
var selected_track_path: String = ""
var selected_track_name: String = ""

# Game mode
var is_multiplayer: bool = false

# Optional: Store additional game state
var player_name: String = "Player"
var best_lap_times := {}

func reset_selections():
	selected_car_path = "res://scenes/player/Car/Car_Arcade_Physics_with_rpm+gearshifts.tscn"
	selected_track_path = ""
	selected_track_name = ""
	is_multiplayer = false
