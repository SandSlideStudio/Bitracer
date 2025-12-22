extends Control

@onready var title_label = $Panel/VBoxContainer/TitleLabel
@onready var solo_button = $Panel/VBoxContainer/SoloButton
@onready var multiplayer_button = $Panel/VBoxContainer/MultiplayerButton
@onready var settings_button = $Panel/VBoxContainer/SettingsButton
@onready var quit_button = $Panel/VBoxContainer/QuitButton

func _ready():
	# Connect buttons
	solo_button.pressed.connect(_on_solo_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# CRITICAL: Clean up any leftover multiplayer state when returning to menu
	_cleanup_multiplayer()

func _cleanup_multiplayer():
	"""Ensure no leftover multiplayer state"""
	if multiplayer.multiplayer_peer:
		print("Cleaning up leftover multiplayer peer...")
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	# Reset GameManager state
	GameManager.disconnect_from_game()
	GameGlobals.is_multiplayer = false
	
	print("Main menu ready - multiplayer state cleared")

func _on_solo_pressed():
	# Ensure multiplayer is OFF
	_cleanup_multiplayer()
	
	# Set game mode to solo
	GameGlobals.is_multiplayer = false
	
	print("Starting solo mode")
	
	# Go to car selector
	get_tree().change_scene_to_file("res://scenes/main/CarSelector.tscn")

func _on_multiplayer_pressed():
	# Set game mode to multiplayer
	GameGlobals.is_multiplayer = true
	
	print("Starting multiplayer mode")
	
	# Go to lobby
	get_tree().change_scene_to_file("res://scenes/main/Lobby.tscn")

func _on_settings_pressed():
	# TODO: Add settings menu
	print("Settings not implemented yet")

func _on_quit_pressed():
	get_tree().quit()
