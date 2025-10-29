extends Control
class_name Shop

signal buy_requested(stats_res: Resource)
signal unit_buy_requested(stats_res: Resource)
signal reroll_requested(cost: int)

@export var reroll_cost: int = 1
@export var stats_pool: Array[Resource]
@export var show_cost_in_button := true

var _offers: Array[Resource] = []
var _locked := false
var _affordable_limit: int = -1

@onready var panel: Panel = $Panel
@onready var offers_vb: VBoxContainer = $Panel/Offers
@onready var btn_reroll: Button = $Panel/Offers/HBoxContainer/RerollButton
@onready var btn_lock: Button = $Panel/Offers/HBoxContainer/LockButton
@onready var btns: Array[Button] = [
	$Panel/Offers/Offer,
	$Panel/Offers/Offer2,
	$Panel/Offers/Offer3,
	$Panel/Offers/Offer4,
]

func _ready() -> void:
	_configure_layout_in_code()
	_wire_ui()
	_refresh_reroll_text()
	if stats_pool != null and not stats_pool.is_empty():
		generate_offers()

func set_pool(pool: Array[Resource]) -> void:
	stats_pool = pool
	if stats_pool != null and not stats_pool.is_empty():
		generate_offers()

func set_affordable_limit(coins: int) -> void:
	_affordable_limit = coins
	_update_buttons()

func _configure_layout_in_code() -> void:
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_FILL
	custom_minimum_size = Vector2(120, 100)

	visible = true
	panel.show()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 1)
	panel.add_theme_stylebox_override("panel", sb)

	offers_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL

	for b in btns:
		if b == null: continue
		b.custom_minimum_size = Vector2(0, 60)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = "—"
		b.add_theme_constant_override("alignment", HORIZONTAL_ALIGNMENT_CENTER)
		b.add_theme_font_size_override("font_size", 22)
		_style_button_white(b)

	if btn_reroll:
		btn_reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_reroll.add_theme_constant_override("alignment", HORIZONTAL_ALIGNMENT_CENTER)
		_style_button_white(btn_reroll)
	if btn_lock:
		btn_lock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_lock.add_theme_constant_override("alignment", HORIZONTAL_ALIGNMENT_CENTER)
		_style_button_white(btn_lock)

func _wire_ui() -> void:
	for i in btns.size():
		if btns[i] and not btns[i].pressed.is_connected(_on_offer_pressed.bind(i)):
			btns[i].pressed.connect(_on_offer_pressed.bind(i))
	if btn_reroll and not btn_reroll.pressed.is_connected(_on_reroll_pressed):
		btn_reroll.pressed.connect(_on_reroll_pressed)
	if btn_lock and not btn_lock.pressed.is_connected(_on_lock_pressed):
		btn_lock.pressed.connect(_on_lock_pressed)

func _style_button_white(b: Button) -> void:
	if b == null: return
	var w := Color(1,1,1,1)
	b.add_theme_color_override("font_color", w)
	b.add_theme_color_override("font_hovered_color", w)
	b.add_theme_color_override("font_pressed_color", w)
	b.add_theme_color_override("font_disabled_color", w)
	b.add_theme_color_override("font_focus_color", w)

func _symbol_for(unit_name: String) -> String:
	var n := unit_name.to_lower()
	if n.find("triang") != -1: return "△"
	if n.find("square") != -1 or n.find("cuad") != -1: return "□"
	if n.find("circle") != -1 or n.find("círc") != -1: return "○"
	if n.find("cross") != -1 or n.find("plus") != -1 or n.find("heal") != -1: return "✚"
	return "◆"

func generate_offers() -> void:
	if _locked:
		_update_buttons()
		return
	_offers.clear()
	if stats_pool == null or stats_pool.is_empty():
		_update_buttons()
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 4:
		_offers.append(stats_pool[rng.randi_range(0, stats_pool.size() - 1)])
	_update_buttons()

func _update_buttons() -> void:
	for i in btns.size():
		var b := btns[i]
		if b == null:
			continue

		if i < _offers.size() and _offers[i] != null:
			var s: Resource = _offers[i]

			var unit_name: String = s.get("unit_name") if s is Object and s.has_method("get") else ""
			var attack := int(s.get("attack")) if s is Object else 0
			var max_hp := int(s.get("max_hp")) if s is Object else 0
			var attack_range := float(s.get("attack_range")) if s is Object else 1.0
			var attack_cooldown := float(s.get("attack_cooldown")) if s is Object else 1.0
			var price := int(s.get("cost")) if s is Object else 1
			var icon: Texture2D = s.get("icon") if s is Object and s.has_method("get") else null

			var sym := _symbol_for(str(unit_name))
			b.disabled = false

			if show_cost_in_button:
				b.text = "%s\n%d€" % [sym, price]
			else:
				b.text = "%s" % sym

			if icon is Texture2D:
				b.icon = icon
				b.expand_icon = true
			else:
				b.icon = null

			b.tooltip_text = "%s\nATK %d  HP %d  RNG %.0f  CD %.1f" % [
				unit_name, attack, max_hp, attack_range, attack_cooldown
			]

			if _affordable_limit >= 0:
				b.disabled = b.disabled or (_affordable_limit < price)
		else:
			b.disabled = true
			b.text = "—"
			b.tooltip_text = ""

	_refresh_reroll_text()

func _refresh_reroll_text() -> void:
	if btn_reroll:
		btn_reroll.text = "Reroll (%d)" % reroll_cost
	if btn_lock:
		btn_lock.text = "Unlock" if _locked else "Lock"

func _on_offer_pressed(idx: int) -> void:
	if idx >= 0 and idx < _offers.size() and _offers[idx] != null:
		var res := _offers[idx]
		emit_signal("buy_requested", res)
		emit_signal("unit_buy_requested", res) 

func _on_reroll_pressed() -> void:
	emit_signal("reroll_requested", reroll_cost)

func _on_lock_pressed() -> void:
	_locked = not _locked
	_refresh_reroll_text()
