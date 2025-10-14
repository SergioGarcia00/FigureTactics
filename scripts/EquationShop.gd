extends Control
class_name EquationShop

signal equation_buy_requested(eq: Equation)
signal reroll_requested(cost: int)

@export var reroll_cost: int = 1
@export var default_cost: int = 1
@export var equation_pool: Array[Equation]

var _offers: Array[Equation] = []
var _locked := false

@onready var panel: Panel = $"Panel"
@onready var offers_vb: VBoxContainer = $"Panel/Offers"
@onready var btn_reroll: Button = $"Panel/Offers/HBoxContainer/RerollButton"
@onready var btn_lock: Button = $"Panel/Offers/HBoxContainer/LockButton"

@onready var btns: Array[Button] = [
	$"Panel/Offers/Offer",
	$"Panel/Offers/Offer2",
	$"Panel/Offers/Offer3",
	$"Panel/Offers/Offer4",
]


func _ready() -> void:
	_configure_layout()
	_wire()
	_refresh_footer()
	if equation_pool != null and not equation_pool.is_empty():
		generate_offers()

	# habilitar drag en cada botón
	for i in btns.size():
		if btns[i]:
			btns[i].gui_input.connect(_on_offer_gui_input.bind(i))


func set_pool(pool: Array[Equation]) -> void:
	equation_pool = pool
	if equation_pool != null and not equation_pool.is_empty():
		generate_offers()


func _configure_layout() -> void:
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_FILL
	custom_minimum_size = Vector2(120, 100)  # ancho mínimo visible
	# Estilo del panel
	if panel:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 1)
		panel.add_theme_stylebox_override("panel", sb)
	else:
		push_warning("EquationShop: nodo 'Panel' no encontrado.")

	if offers_vb:
		offers_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		push_error("EquationShop: 'Panel/Offers' no encontrado o no es VBoxContainer.")

	for b in btns:
		if b == null: continue
		b.custom_minimum_size = Vector2(0, 60)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = "—"
		b.add_theme_constant_override("alignment", HORIZONTAL_ALIGNMENT_CENTER)
		b.add_theme_font_size_override("font_size", 22)
		_make_text_white(b)

	_make_text_white(btn_reroll)
	_make_text_white(btn_lock)


func _make_text_white(b: Button) -> void:
	if b == null: return
	var w := Color(1, 1, 1, 1)
	b.add_theme_color_override("font_color", w)
	b.add_theme_color_override("font_hovered_color", w)
	b.add_theme_color_override("font_pressed_color", w)
	b.add_theme_color_override("font_disabled_color", w)
	b.add_theme_color_override("font_focus_color", w)


func _wire() -> void:
	for i in btns.size():
		if btns[i] and not btns[i].pressed.is_connected(_on_offer.bind(i)):
			btns[i].pressed.connect(_on_offer.bind(i))
	if btn_reroll and not btn_reroll.pressed.is_connected(_on_reroll):
		btn_reroll.pressed.connect(_on_reroll)
	if btn_lock and not btn_lock.pressed.is_connected(_on_lock):
		btn_lock.pressed.connect(_on_lock)


func generate_offers() -> void:
	if _locked:
		_update_buttons()
		return

	_offers.clear()

	if equation_pool == null or equation_pool.is_empty():
		_update_buttons()
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 4:
		_offers.append(equation_pool[rng.randi_range(0, equation_pool.size() - 1)])

	_update_buttons()


func _update_buttons() -> void:
	for i in btns.size():
		var b := btns[i]
		if b == null:
			continue

		if i < _offers.size() and _offers[i] != null:
			var e: Equation = _offers[i]

			# Precio con tipado explícito
			var price: int = default_cost
			if e != null and e.has_method("get"):
				var maybe_cost: Variant = e.get("cost")
				if typeof(maybe_cost) == TYPE_INT or typeof(maybe_cost) == TYPE_FLOAT:
					price = int(maybe_cost)

			var label: String = e.get("label") if e != null and e.has_method("get") else "—"

			b.disabled = false
			b.text = "%s\n%d€" % [label, price]
			b.tooltip_text = "Aplica %s al ATAQUE al inicio de la ronda (1 turno)." % label
		else:
			b.disabled = true
			b.text = "—"
			b.tooltip_text = ""

	_refresh_footer()


func _refresh_footer() -> void:
	if btn_reroll:
		btn_reroll.text = "Reroll (%d)" % reroll_cost
	if btn_lock:
		btn_lock.text = "Unlock" if _locked else "Lock"


func _on_offer(idx: int) -> void:
	if idx >= 0 and idx < _offers.size() and _offers[idx] != null:
		equation_buy_requested.emit(_offers[idx])


func _on_reroll() -> void:
	reroll_requested.emit(reroll_cost)


func _on_lock() -> void:
	_locked = not _locked
	_refresh_footer()

# --- DRAG & DROP SUPPORT ---
var _drag_idx: int = -1

func _on_offer_gui_input(event: InputEvent, idx: int) -> void:
	if idx < 0 or idx >= _offers.size() or _offers[idx] == null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_idx = idx
			# Start drag on click
			var eq := _offers[idx]
			var preview := _make_preview_label(eq.label)
			btns[idx].force_drag(eq, preview)
			_drag_idx = -1

	# Movimiento con botón izq. pulsado: iniciamos el drag
	elif event is InputEventMouseMotion:
		if _drag_idx == idx and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var eq := _offers[idx]
			var preview := _make_preview_label(eq.label)
			# Inicia el drag desde el propio botón (no desde el panel)
			btns[idx].force_drag(eq, preview)
			_drag_idx = -1  # evitamos reiniciar el drag en más movimientos

func _make_preview_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 24)  # Larger font
	l.modulate = Color(1, 1, 0, 1)  # Bright yellow for visibility
	l.add_theme_color_override("font_color", Color(1, 1, 0, 1))
	# Add a background for better visibility
	l.add_theme_stylebox_override("normal", _make_preview_stylebox())
	return l

func _make_preview_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)  # Dark semi-transparent background
	style.border_color = Color(1, 1, 0, 1)  # Yellow border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style
