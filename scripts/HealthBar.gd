extends Node2D
class_name HealthBar

var max_hp: int = 100
var current_hp: int = 100

@export var width: float = 48.0
@export var height: float = 6.0
@export var padding: float = 1.0
@export var offset_y: float = -36.0
@export var bg_color: Color = Color(0, 0, 0, 0.65)
@export var fg_color: Color = Color(0.2, 0.9, 0.2, 1.0)

func set_values(cur: int, maxv: int) -> void:
	max_hp = max(1, maxv)
	current_hp = clamp(cur, 0, max_hp)
	queue_redraw()

func _draw() -> void:
	var ratio: float = float(current_hp) / float(max_hp)

	# background
	draw_rect(Rect2(Vector2(-width/2.0, offset_y), Vector2(width, height)), bg_color, true)
	# fill
	draw_rect(
		Rect2(
			Vector2(-width/2.0 + padding, offset_y + padding),
			Vector2((width - 2.0 * padding) * ratio, height - 2.0 * padding)
		),
		fg_color,
		true
	)
