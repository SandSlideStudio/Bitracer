# track.gd
extends Node2D

@onready var racing_line = $RacingLine
var waypoints: Array[Marker2D] = []

func _ready():
	for child in racing_line.get_children():
		waypoints.append(child)
#Since ill probably forget this, waypoints have to be children of a node2d called RacingLine in order for the ai to be able to pick up on it
