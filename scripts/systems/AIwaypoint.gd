# waypoint.gd
@tool
extends Marker2D
class_name Waypoint

@export var speed_multiplier: float = 1.0  # 0.0 to 1.0
@export var track_width: float = 60.0
@export var sector: int = 0

# Optional visual helper (only in editor)
func _draw():
	if Engine.is_editor_hint():
		draw_circle(Vector2.ZERO, 8, Color.GREEN)
		draw_circle(Vector2.ZERO, track_width / 2, Color(0, 1, 0, 0.2))
