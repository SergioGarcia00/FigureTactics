extends Polygon2D

@export var outline_color: Color = Color.BLACK
@export var outline_width: float = 2.0

func _draw() -> void:
	if polygon.size() == 0:
		return
	var pts := PackedVector2Array()
	pts.append_array(polygon)   # copiamos los puntos
	pts.append(polygon[0])      # cerramos la línea
	draw_polyline(pts, outline_color, outline_width)
