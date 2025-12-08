extends Area2D
# Attach this script directly to your Track's Area2D node

@onready var start_line: CollisionShape2D = $StartLine
@onready var mid_point: CollisionShape2D = $MidPoint

# Reference to the UI
var lap_timer_ui = null

# Lap tracking state
var passed_start: bool = false
var passed_mid: bool = false
var lap_in_progress: bool = false

# Track which checkpoint we last touched to prevent double triggers
var last_checkpoint_touched: String = ""

func _ready() -> void:
	# Connect signals for Area2D entering (not Body2D)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	
	print("Lap tracker ready!")
	print("StartLine found: ", start_line != null)
	print("MidPoint found: ", mid_point != null)
	
	# Find the lap timer UI in the scene tree
	lap_timer_ui = get_tree().current_scene.get_node_or_null("LapTimerUI")
	if lap_timer_ui == null:
		print("ERROR: LapTimerUI not found! Make sure it's named 'LapTimerUI' in your scene")
	else:
		print("LapTimerUI found successfully!")

func _on_area_entered(area) -> void:
	print("Area entered detection: ", area.name, " (parent: ", area.get_parent().name, ")")
	
	# Check if it's the car's detection area
	var car_node = area.get_parent()
	if car_node.name != "Car":
		return
	
	# Determine which checkpoint was crossed based on distance
	var body_pos: Vector2 = car_node.global_position
	var start_pos: Vector2 = start_line.global_position
	var mid_pos: Vector2 = mid_point.global_position
	
	var dist_to_start: float = body_pos.distance_to(start_pos)
	var dist_to_mid: float = body_pos.distance_to(mid_pos)
	
	print("Distance to start: ", dist_to_start, " | Distance to mid: ", dist_to_mid)
	
	# Determine which checkpoint is closer
	if dist_to_start < dist_to_mid:
		if last_checkpoint_touched != "start":
			_on_start_line_crossed()
			last_checkpoint_touched = "start"
	else:
		if last_checkpoint_touched != "mid":
			_on_mid_point_crossed()
			last_checkpoint_touched = "mid"

func _on_area_exited(area) -> void:
	var car_node = area.get_parent()
	if car_node.name == "Car":
		last_checkpoint_touched = ""

func _on_start_line_crossed() -> void:
	print("START LINE CROSSED!")
	
	if not lap_in_progress:
		# Starting a new lap
		passed_start = true
		passed_mid = false
		lap_in_progress = true
		if lap_timer_ui:
			lap_timer_ui.start_timing()
			print("Timer started!")
		else:
			print("ERROR: Cannot start timer - UI not found!")
	elif passed_mid:
		# Completing a lap (crossed mid, now back at start)
		if lap_timer_ui:
			var lap_time: float = lap_timer_ui.stop_timing()
			print("LAP COMPLETED! Time: ", lap_time)
		
		# Start new lap immediately
		passed_start = true
		passed_mid = false
		if lap_timer_ui:
			lap_timer_ui.start_timing()
			print("New lap started!")

func _on_mid_point_crossed() -> void:
	print("MIDPOINT CROSSED!")
	
	if lap_in_progress and passed_start and not passed_mid:
		# Reached midpoint
		passed_mid = true
		print("Midpoint registered!")
