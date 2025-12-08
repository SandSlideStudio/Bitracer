extends CanvasLayer

@onready var current_time_label: Label = $MarginContainer/VBoxContainer/CurrentTimeLabel
@onready var last_time_label: Label = $MarginContainer/VBoxContainer/LastTimeLabel
@onready var best_time_label: Label = $MarginContainer/VBoxContainer/BestTimeLabel

var current_time: float = 0.0
var last_time: float = 0.0
var best_time: float = 0.0
var is_timing: bool = false

func _ready() -> void:
	reset_display()

func _process(delta: float) -> void:
	if is_timing:
		current_time += delta
		update_current_time_display()

func start_timing() -> void:
	is_timing = true
	current_time = 0.0

func stop_timing() -> float:
	is_timing = false
	var final_time: float = current_time
	
	# Update last lap time
	last_time = final_time
	update_last_time_display()
	
	# Update best lap time
	if best_time == 0.0 or final_time < best_time:
		best_time = final_time
		update_best_time_display()
		# Flash best time yellow when new record
		best_time_label.modulate = Color.YELLOW
	
	return final_time

func update_current_time_display() -> void:
	if current_time_label:
		current_time_label.text = "Current: %s" % format_time(current_time)

func update_last_time_display() -> void:
	if last_time_label:
		if last_time > 0.0:
			last_time_label.text = "Last: %s" % format_time(last_time)
		else:
			last_time_label.text = "Last: --:--.---"

func update_best_time_display() -> void:
	if best_time_label:
		if best_time > 0.0:
			best_time_label.text = "Best: %s" % format_time(best_time)
		else:
			best_time_label.text = "Best: --:--.---"

func format_time(time_seconds: float) -> String:
	@warning_ignore("integer_division")
	var minutes: int = int(time_seconds) / 60
	var seconds: int = int(time_seconds) % 60
	var milliseconds: int = int((time_seconds - int(time_seconds)) * 1000)
	return "%d:%02d.%03d" % [minutes, seconds, milliseconds]

func reset_display() -> void:
	current_time = 0.0
	update_current_time_display()
	update_last_time_display()
	update_best_time_display()

func reset_best_time() -> void:
	best_time = 0.0
	update_best_time_display()
