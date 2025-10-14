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
		mouse_filter = Control.MOUSE_FILTER_PASS
		size = Vector2(48, 48)
		pivot_offset = size * 0.5

	func _can_drop_data(_pos, data) -> bool:
		# Bench tiles cannot accept equations
		if tile.is_bench:
			return false
		# Any occupied tile on the main battlefield can accept equations
		return data is Equation and tile.occupied and tile.occupant != null

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
	drop.z_index = 100  # CHANGED FROM 9999 to 100 (much lower)

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
	print("TILE DEBUG: set_equation called with: ", eq.label if eq else "null")
	equation = eq
	_update_equation_visual()
	return true

func clear_equation() -> void:
	equation = null
	_update_equation_visual()

func _make_eq_label() -> void:
	if _eq_label: 
		print("TILE DEBUG: _eq_label already exists")
		return
	print("TILE DEBUG: Creating new _eq_label")
	_eq_label = Label.new()
	_eq_label.visible = false
	_eq_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eq_label.add_theme_font_size_override("font_size", 20)  # Larger font
	_eq_label.modulate = Color(0, 0, 0, 1)  # BLACK text
	_eq_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	
	# Force white background
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(1, 1, 1, 0.9)  # Solid white background
	stylebox.border_color = Color(0, 0, 0, 1)  # Black border
	stylebox.border_width_left = 2
	stylebox.border_width_top = 2
	stylebox.border_width_right = 2
	stylebox.border_width_bottom = 2
	stylebox.corner_radius_top_left = 4
	stylebox.corner_radius_top_right = 4
	stylebox.corner_radius_bottom_right = 4
	stylebox.corner_radius_bottom_left = 4
	stylebox.content_margin_left = 8
	stylebox.content_margin_top = 4
	stylebox.content_margin_right = 8
	stylebox.content_margin_bottom = 4
	_eq_label.add_theme_stylebox_override("normal", stylebox)
	
	add_child(_eq_label)
	_eq_label.position = Vector2(-20, -30)  # More centered position
	_eq_label.z_index = 50
	print("TILE DEBUG: _eq_label created and added to tile")

func _update_equation_visual() -> void:
	print("TILE DEBUG: _update_equation_visual called, equation: ", equation.label if equation else "null")
	_make_eq_label()
	if equation == null:
		_eq_label.visible = false
		print("TILE DEBUG: No equation, hiding label")
		return
	_eq_label.text = equation.label
	_eq_label.visible = true
	print("TILE DEBUG: Equation label set to: ", equation.label, " visible: ", _eq_label.visible)
	

# ========================
#   INPUT (click selección)
# ========================
func _on_area_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Casilla azul con unidad → seleccionable para ecuación
		if is_blue and occupied and occupant != null:
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
