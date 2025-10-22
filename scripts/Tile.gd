extends Node2D
class_name Tile

@export var q: int = 0
@export var r: int = 0
@export var equation: Equation

var _eq_label: Label
var is_blue: bool = false
var is_red: bool = false
var is_bench: bool = false

var occupied: bool = false
var occupant: Node = null

# Para selección de ecuaciones
var selected_for_equation: bool = false

@export var base_color: Color = Color(0.80, 0.80, 0.80)
@onready var poly: Polygon2D = $Polygon2D

# --- Control hijo para aceptar drops desde la tienda ---
class DropTarget extends Control:
	var tile: Tile

	func _init(t: Tile) -> void:
		tile = t
		# PASS para no bloquear el Area2D de clics
		mouse_filter = Control.MOUSE_FILTER_PASS
		size = Vector2(48, 48)
		pivot_offset = size * 0.5

	func _can_drop_data(_pos, data) -> bool:
		# Bancos no aceptan ecuaciones
		if tile.is_bench:
			return false
		# Acepta si hay una unidad (aliada o enemiga) encima
		return (data is Equation) and (tile.occupant is Unit)

	func _drop_data(_pos, data):
		if data is Equation:
			get_tree().call_group("main", "_on_tile_drop_equation", tile, data)

func _ready() -> void:
	_update_visual()
	_make_eq_label()
	_update_equation_visual()

	# Area2D para clicks en el tablero
	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	shape.shape = circle
	area.add_child(shape)
	add_child(area)
	area.input_event.connect(_on_area_input_event)

	# Control overlay para aceptar drag & drop desde la tienda
	var drop := DropTarget.new(self)
	add_child(drop)
	# Centra el rectángulo sobre el origen de la casilla; ajusta según tu malla/hex
	drop.position = Vector2(-drop.size.x * 0.5, -drop.size.y * 0.5)
	drop.z_index = 100  # suficientemente alto para captar el drop

# ========================
#  VISUAL
# ========================
func set_base_color(c: Color) -> void:
	base_color = c
	_update_visual()

func _update_visual() -> void:
	if is_instance_valid(poly):
		poly.color = base_color
		if poly.has_method("queue_redraw"):
			poly.queue_redraw()

func highlight(col: Color) -> void:
	if is_instance_valid(poly):
		poly.color = col
		if poly.has_method("queue_redraw"):
			poly.queue_redraw()

func reset_color() -> void:
	_update_visual()

# ========================
#  UNIDAD / OCUPACIÓN
# ========================
func set_occupied(v: bool, by: Node = null) -> void:
	occupied = v
	occupant = by if v else null

# ========================
#  ECUACIONES
# ========================
func set_equation(eq: Equation) -> bool:
	equation = eq
	_update_equation_visual()
	return true

func clear_equation() -> void:
	equation = null
	_update_equation_visual()

func _make_eq_label() -> void:
	if _eq_label: return
	_eq_label = Label.new()
	_eq_label.visible = false
	_eq_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eq_label.add_theme_font_size_override("font_size", 18)
	_eq_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eq_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var sb := StyleBoxFlat.new()
	# Antes: Color.hex("2b2f36") / Color.hex("0f1115")
	# Ahora: valores en float (r,g,b,a)
	sb.bg_color = Color(0.1686, 0.1843, 0.2118, 1.0)   # #2b2f36
	sb.border_color = Color(0.0588, 0.0667, 0.0824, 1.0) # #0f1115
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2

	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6

	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_eq_label.add_theme_stylebox_override("normal", sb)
	_eq_label.add_theme_color_override("font_color", Color(1,1,1))

	add_child(_eq_label)
	_eq_label.position = Vector2(-18, -30)
	_eq_label.z_index = 50

func _update_equation_visual() -> void:
	_make_eq_label()
	if equation == null:
		_eq_label.visible = false
		return

	_eq_label.text = String(equation.label)
	_eq_label.visible = true

	# color por tipo (+, -, ×, ÷)
	var sb := _eq_label.get_theme_stylebox("normal") as StyleBoxFlat
	var txt := _eq_label.text.strip_edges()

	if txt.begins_with("+"):
		sb.bg_color = Color(0.1059, 0.3686, 0.1255, 1.0) # #1b5e20 verde
	elif txt.begins_with("-"):
		sb.bg_color = Color(0.4275, 0.1059, 0.1059, 1.0) # #6d1b1b rojo
	elif txt.begins_with("x") or txt.begins_with("×"):
		sb.bg_color = Color(0.1569, 0.2078, 0.5765, 1.0) # #283593 azul
	elif txt.begins_with("d") or txt.begins_with("÷") or txt.begins_with("/"):
		sb.bg_color = Color(0.3059, 0.2039, 0.1804, 1.0) # #4e342e marrón
	else:
		sb.bg_color = Color(0.1686, 0.1843, 0.2118, 1.0) # #2b2f36 por defecto

	_eq_label.add_theme_stylebox_override("normal", sb)

	# pequeña animación pop
	var tw := create_tween()
	_eq_label.scale = Vector2(0.8, 0.8)
	tw.tween_property(_eq_label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ========================
#   INPUT (click selección)
# ========================
func _on_area_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Cualquier casilla del tablero (no banco) con una unidad encima (aliada o enemiga)
		if not is_bench and (occupant is Unit):
			get_tree().call_group("main", "_on_tile_selected_for_equation", self)

# ========================
#   SELECCIÓN VISUAL
# ========================
func mark_selected() -> void:
	selected_for_equation = true
	highlight(Color(0.4, 0.6, 1.0)) # azul clarito

func unmark_selected() -> void:
	selected_for_equation = false
	reset_color()
