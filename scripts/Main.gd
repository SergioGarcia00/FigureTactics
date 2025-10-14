extends Node2D

@onready var grid: Grid = $Grid
@onready var cam: Camera2D = $Camera2D
@onready var start_button: Button = $"CanvasLayer/StartButton"
@onready var reset_button: Button = $"CanvasLayer/ResetButton"
@onready var economy: Node = get_node_or_null("Economy")
@onready var blue_label: Label = $"CanvasLayer/TopBar/BlueCoinsLabel" if has_node("CanvasLayer/TopBar/BlueCoinsLabel") else null

@onready var shop: Shop = $"CanvasLayer/RightDock/HBoxContainer/Shop"
@onready var eq_shop: EquationShop = $"CanvasLayer/RightDock/HBoxContainer/EquationShop"

var _pending_equation: Equation = null
var _placing_equation := false
var _selected_tile: Tile = null   # casilla marcada (modo “casilla primero”)

const UNIT_SCN: PackedScene = preload("res://scenes/Unit.tscn")

const STATS_POOL: Array[Resource] = [
	preload("res://resources/Square.tres"),
	preload("res://resources/Triangle.tres"),
	preload("res://resources/Circle.tres"),
	preload("res://resources/Cross.tres"),
]

const EQ_POOL: Array[Equation] = [
	preload("res://resources/+3.tres"),
	preload("res://resources/-2.tres"),
	preload("res://resources/x4.tres"),
	preload("res://resources/d5.tres"),
]

const NUM_BLUE: int = 3
const NUM_RED: int  = 3

var round_active: bool = false


func _ready() -> void:
	add_to_group("main") # para que Tile.gd pueda llamarnos por call_group

	# Botones Start/Reset
	if is_instance_valid(start_button):
		if not start_button.pressed.is_connected(_on_start_pressed):
			start_button.pressed.connect(_on_start_pressed)
		start_button.disabled = false
		start_button.text = "Start Round"
	if is_instance_valid(reset_button):
		if not reset_button.pressed.is_connected(_on_reset_pressed):
			reset_button.pressed.connect(_on_reset_pressed)
		reset_button.disabled = true
		reset_button.text = "Reset"

	_layout_ui()
	round_active = false
	_set_build_phase_for_all(true)

	# Economía
	if is_instance_valid(economy):
		if economy.has_signal("balance_changed") and not economy.balance_changed.is_connected(_on_balance_changed):
			economy.balance_changed.connect(_on_balance_changed)
		if is_instance_valid(blue_label):
			var coins := 0
			if economy.has_method("balance_of"):
				coins = int(economy.balance_of(0))
			_update_blue_label(coins)

	# Tienda de unidades
	if is_instance_valid(shop):
		if shop.has_method("set_pool"):
			shop.set_pool(STATS_POOL)
		if shop.has_signal("unit_buy_requested"):
			if not shop.unit_buy_requested.is_connected(_on_shop_buy):
				shop.unit_buy_requested.connect(_on_shop_buy)
		elif shop.has_signal("buy_requested"):
			if not shop.buy_requested.is_connected(_on_shop_buy):
				shop.buy_requested.connect(_on_shop_buy)
		if shop.has_signal("reroll_requested") and not shop.reroll_requested.is_connected(_on_shop_reroll):
			shop.reroll_requested.connect(_on_shop_reroll)
		if shop.has_method("generate_offers"):
			shop.generate_offers()

	# Tienda de ecuaciones
	if is_instance_valid(eq_shop):
		eq_shop.set_pool(EQ_POOL)
		if not eq_shop.equation_buy_requested.is_connected(_on_equation_buy):
			eq_shop.equation_buy_requested.connect(_on_equation_buy)
		if not eq_shop.reroll_requested.is_connected(_on_equation_reroll):
			eq_shop.reroll_requested.connect(_on_equation_reroll)
		eq_shop.generate_offers()

	# Spawn inicial de prueba
	if get_tree().get_nodes_in_group("units").is_empty():
		_spawn_random_teams(NUM_BLUE, NUM_RED)
	_debug_report_units()

	await get_tree().process_frame
	_center_and_fit_camera(false, 64.0)
	get_viewport().size_changed.connect(_on_viewport_resized)

func _process(_delta: float) -> void:
	# Visual feedback for equation targeting
	if _placing_equation and _pending_equation != null:
		_highlight_valid_equation_targets()

func _highlight_valid_equation_targets() -> void:
	# Reset all tiles first
	for q in grid.tiles:
		for r in grid.tiles[q]:
			var tile = grid.tiles[q][r]
			if tile.has_method("reset_color"):
				tile.reset_color()
	
	# Reset bench tiles too
	for bench_tile in grid.bench_blue:
		if bench_tile.has_method("reset_color"):
			bench_tile.reset_color()
	for bench_tile in grid.bench_red:
		if bench_tile.has_method("reset_color"):
			bench_tile.reset_color()
	
	# Highlight valid targets (any occupied non-bench tile)
	var mouse_pos = get_global_mouse_position()
	var hover_tile = grid.get_tile_at_position(mouse_pos)
	
	if hover_tile and not hover_tile.is_bench and _can_apply_equation_on_tile(hover_tile, 0):
		if hover_tile.has_method("highlight"):
			# Use different colors for allies vs enemies
			if hover_tile.is_blue:
				hover_tile.highlight(Color(0.3, 0.8, 0.3))  # Green for allies
			else:
				hover_tile.highlight(Color(0.8, 0.3, 0.3))  # Red for enemies
	else:
		# Optional: Show invalid targets in a dim color
		if hover_tile and not hover_tile.is_bench:
			if hover_tile.has_method("highlight"):
				hover_tile.highlight(Color(0.5, 0.5, 0.5, 0.5))  # Dim for invalid
				
func _physics_process(_delta: float) -> void:
	if not round_active:
		return
	var blue_alive := false
	var red_alive := false
	for n in get_tree().get_nodes_in_group("units"):
		if n is Unit and (n as Unit)._is_alive():
			if (n as Unit).team == 0: blue_alive = true
			elif (n as Unit).team == 1: red_alive = true
	if not blue_alive or not red_alive:
		_finish_round()


# --- UI ---
func _on_start_pressed() -> void:
	round_active = true
	for n in get_tree().get_nodes_in_group("units"):
		if n is Unit:
			(n as Unit).reset_round_bonuses()
	_apply_tile_buffs_for_team(0)
	_apply_tile_buffs_for_team(1)
	_set_build_phase_for_all(false)
	if is_instance_valid(start_button):
		start_button.disabled = true
		start_button.text = "Round Running"
	if is_instance_valid(reset_button):
		reset_button.disabled = false


func _on_reset_pressed() -> void:
	round_active = false
	_set_build_phase_for_all(true)
	if is_instance_valid(start_button):
		start_button.disabled = false
		start_button.text = "Start Round"
	if is_instance_valid(reset_button):
		reset_button.disabled = true


func _finish_round() -> void:
	round_active = false
	_set_build_phase_for_all(true)
	if is_instance_valid(start_button):
		start_button.disabled = false
		start_button.text = "Start Round"
	if is_instance_valid(reset_button):
		reset_button.disabled = true


# ========= ECUACIONES =========
func _on_equation_buy(eq: Equation) -> void:
	# Enter targeting mode for click placement
	_pending_equation = eq
	_placing_equation = true
	print("Equation selected: ", eq.label, " - Click on a blue hexagon with a unit to apply")
	
func _on_equation_reroll(cost: int) -> void:
	var team := 0
	if is_instance_valid(economy):
		if economy.has_method("can_afford") and not economy.can_afford(team, cost):
			push_warning("No hay oro para reroll (ecuaciones).")
			return
		if economy.has_method("spend") and not economy.spend(team, cost):
			return
	if is_instance_valid(eq_shop):
		eq_shop.generate_offers()

func _unhandled_input(event: InputEvent) -> void:
	if _placing_equation and _pending_equation != null:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var t := grid.get_tile_at_position(get_global_mouse_position())
			if t != null and _can_apply_equation_on_tile(t, 0):
				_apply_equation_on_tile(t, _pending_equation)
			else:
				print("Invalid target - must be blue hexagon with your unit")
			# Consume the event to prevent multiple triggers
			get_viewport().set_input_as_handled()

func _can_apply_equation_on_tile(t: Tile, team: int) -> bool:
	if t == null: 
		return false
	# Bench tiles cannot have equations (for either team)
	if t.is_bench:
		return false
	# Tile must be occupied by a unit
	if not ("occupied" in t) or not t.occupied: 
		return false
	if t.occupant == null or not (t.occupant is Unit): 
		return false
	
	# For team 0 (blue player), can apply to BOTH teams (for buffs AND debuffs)
	# This allows blue player to buff allies AND debuff enemies
	return true

# Llamado desde Tile.gd al click en casilla azul
func _on_tile_selected_for_equation(tile: Tile) -> void:
	# desmarcar la anterior si es distinta
	if _selected_tile and is_instance_valid(_selected_tile) and _selected_tile != tile:
		_selected_tile.unmark_selected()
	_selected_tile = tile
	# Si hay ecuación pendiente, aplicar inmediatamente
	if _placing_equation and _pending_equation != null:
		if _apply_equation_on_tile(tile, _pending_equation):
			return
	# si no se aplicó, dejarla marcada visualmente
	if _selected_tile:
		_selected_tile.mark_selected()

# Llamado desde Tile.gd al soltar un drag de Equation encima de una casilla
func _on_tile_drop_equation(tile: Tile, eq: Equation) -> void:
	if _can_apply_equation_on_tile(tile, 0):
		_apply_equation_on_tile(tile, eq)

# Aplica la ecuación (cobra, valida y escribe en la tile)

# Aplica la ecuación (cobra, valida y escribe en la tile)
func _apply_equation_on_tile(tile: Tile, eq: Equation) -> bool:
	if tile == null or eq == null:
		print("DEBUG: Tile or Equation is null")
		return false
	if not _can_apply_equation_on_tile(tile, 0):
		print("DEBUG: Cannot apply equation to this tile")
		return false

	# Precio
	var price := 1
	if "cost" in eq:
		price = int(eq.cost)

	# Cobro
	if is_instance_valid(economy):
		if economy.has_method("can_afford") and not economy.can_afford(0, price):
			print("DEBUG: Cannot afford equation")
			return false
		if economy.has_method("spend") and not economy.spend(0, price):
			print("DEBUG: Failed to spend coins")
			return false

	# Aplicar
	print("DEBUG: Attempting to set equation on tile")
	if grid.set_tile_equation(tile, eq):
		print("DEBUG: Equation successfully set on tile")
		if _selected_tile:
			_selected_tile.unmark_selected()
		_selected_tile = null
		_pending_equation = null
		_placing_equation = false
		
		var target_type = "aliado" if tile.is_blue else "enemigo"
		push_warning("Ecuación %s aplicada a unidad %s." % [eq.label, target_type])
		return true

	print("DEBUG: grid.set_tile_equation returned false")
	push_warning("No se pudo aplicar en esa casilla.")
	return false

# ======== FIN ECUACIONES ========


# --- Layout botones ---
func _layout_ui() -> void:
	if not is_instance_valid(start_button):
		return
	await get_tree().process_frame
	var margin := Vector2(16, 16)
	var spacing := 12.0
	if start_button is Control:
		var sb: Control = start_button as Control
		sb.anchor_left = 0.0
		sb.anchor_top = 0.0
		sb.anchor_right = 0.0
		sb.anchor_bottom = 0.0
		sb.position = margin
		if is_instance_valid(reset_button) and reset_button is Control:
			var rb: Control = reset_button as Control
			rb.anchor_left = 0.0
			rb.anchor_top = 0.0
			rb.anchor_right = 0.0
			rb.anchor_bottom = 0.0
			rb.position = Vector2(sb.position.x + sb.size.x + spacing, sb.position.y)
	else:
		start_button.position = margin
		if is_instance_valid(reset_button):
			reset_button.position = margin + Vector2(120.0 + spacing, 0.0)


# --- Helpers de unidades / tablero / cámara ---
func _set_build_phase_for_all(enabled: bool) -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit:
			(u as Unit).set_build_phase(enabled)

func _apply_tile_buffs_for_team(team: int) -> void:
	for q in grid.tiles.keys():
		var row: Dictionary = grid.tiles[q]
		for r in row.keys():
			var t: Tile = row[r]
			_apply_tile_buff_on_tile(t, team)
	for t in grid.bench_tiles_for_team(team):
		_apply_tile_buff_on_tile(t, team)

func _apply_tile_buff_on_tile(t: Tile, team: int) -> void:
	if t == null: return
	if not ("equation" in t) or t.equation == null: return
	if not t.occupied or t.occupant == null or not (t.occupant is Unit): return
	var u := t.occupant as Unit
	if u.team != team: return
	var base_attack := 0.0
	if u.stats != null and "attack" in u.stats:
		base_attack = float(u.stats.attack)
	var modified := t.equation.apply(base_attack)
	u.add_round_attack_bonus(modified - base_attack)

func _spawn_random_teams(n_blue: int, n_red: int) -> void:
	var blue_tiles: Array = []
	var red_tiles: Array  = []
	_collect_tiles_with_fallback(grid, blue_tiles, red_tiles)
	blue_tiles.shuffle()
	red_tiles.shuffle()
	n_blue = min(n_blue, blue_tiles.size())
	n_red  = min(n_red,  red_tiles.size())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(n_blue):
		var u: Unit = UNIT_SCN.instantiate()
		u.team = 0
		u.stats = STATS_POOL[rng.randi_range(0, STATS_POOL.size() - 1)]
		add_child(u)
		u.place_on_tile(blue_tiles[i])
	for j in range(n_red):
		var v: Unit = UNIT_SCN.instantiate()
		v.team = 1
		v.stats = STATS_POOL[rng.randi_range(0, STATS_POOL.size() - 1)]
		add_child(v)
		v.place_on_tile(red_tiles[j])
	_debug_report_units()

func _collect_tiles_with_fallback(root: Node, blue_out: Array, red_out: Array) -> void:
	var all_tiles: Array = []
	_collect_all_tiles(root, all_tiles)
	var non_blue: Array = []
	for tnode in all_tiles:
		var t := tnode as Tile
		if t == null: continue
		var is_blue_flag := false
		if "is_blue" in t:
			is_blue_flag = t.is_blue
		if is_blue_flag: blue_out.append(t)
		else: non_blue.append(t)
	for tnode in non_blue:
		var tr := tnode as Tile
		if tr == null: continue
		if "is_red" in tr and tr.is_red:
			red_out.append(tr)
	if red_out.is_empty() and not non_blue.is_empty():
		var min_x := INF
		var max_x := -INF
		for tnode in non_blue:
			var t2 := tnode as Tile
			if t2 == null: continue
			var x := float(t2.global_position.x)
			if x < min_x: min_x = x
			if x > max_x: max_x = x
		var cutoff := (min_x + max_x) * 0.5
		for tnode in non_blue:
			var t3 := tnode as Tile
			if t3 == null: continue
			if float(t3.global_position.x) > cutoff:
				red_out.append(t3)

func _collect_all_tiles(node: Node, out: Array) -> void:
	if node is Tile:
		out.append(node)
	for c in node.get_children():
		_collect_all_tiles(c, out)

func _debug_report_units() -> void:
	var all := get_tree().get_nodes_in_group("units")
	print("Units in scene: ", all.size())
	for u in all:
		if u is Unit:
			prints(" •", u.name, "team", u.team, "at", u.global_position)

func _on_viewport_resized() -> void:
	_center_and_fit_camera(false, 64.0)

func _center_and_fit_camera(include_benches: bool = false, margin: float = 64.0) -> void:
	if cam == null or grid == null: return
	var rect: Rect2 = grid.board_rect(include_benches)
	var center: Vector2 = rect.position + rect.size * 0.5
	cam.position = center
	cam.make_current()
	var vp_size: Vector2 = get_viewport_rect().size
	var target_w := rect.size.x + margin
	var target_h := rect.size.y + margin
	if vp_size.x <= 0.0 or vp_size.y <= 0.0: return
	var zoom_w := vp_size.x / target_w
	var zoom_h := vp_size.y / target_h
	var zoom: float = min(zoom_w, zoom_h)
	zoom = clamp(zoom, 0.05, 1.0)
	cam.zoom = Vector2(zoom, zoom)
	_set_camera_limits_to_rect(rect)

func _set_camera_limits_to_rect(rect: Rect2) -> void:
	var half_view: Vector2 = get_viewport_rect().size * 0.5 * cam.zoom
	cam.limit_left   = int(rect.position.x - half_view.x)
	cam.limit_top    = int(rect.position.y - half_view.y)
	cam.limit_right  = int(rect.position.x + rect.size.x + half_view.x)
	cam.limit_bottom = int(rect.position.y + half_view.y + rect.size.y)

func _set_camera_limits(rect: Rect2) -> void:
	cam.limit_left = int(rect.position.x)
	cam.limit_top = int(rect.position.y)
	cam.limit_right = int(rect.position.x + rect.size.x)
	cam.limit_bottom = int(rect.position.y + rect.size.y)

func _update_blue_label(coins: int) -> void:
	if is_instance_valid(blue_label):
		blue_label.text = "Blue: %d" % coins


# --- Tienda UNITS ---
func _on_shop_buy(stats_res: Resource) -> void:
	if stats_res == null: return
	var team := 0
	var price := 1
	if "cost" in stats_res:
		price = int(stats_res.cost)
	if is_instance_valid(economy):
		if economy.has_method("can_afford") and not economy.can_afford(team, price):
			push_warning("No hay oro suficiente (%d)." % price)
			return
		if economy.has_method("spend") and not economy.spend(team, price):
			return
	var u: Unit = UNIT_SCN.instantiate()
	u.team = team
	u.stats = stats_res
	add_child(u)
	var placed := false
	if is_instance_valid(grid) and grid.has_method("place_unit_on_bench"):
		placed = grid.place_unit_on_bench(u, team)
	if not placed:
		if is_instance_valid(economy) and economy.has_method("add"):
			economy.add(team, price)
		u.queue_free()
		push_warning("No hay espacio en el banco azul.")
		return
	if is_instance_valid(shop) and shop.has_method("generate_offers"):
		shop.generate_offers()

func _on_balance_changed(team: int, coins: int) -> void:
	if team == 0:
		_update_blue_label(coins)
		if is_instance_valid(shop) and shop.has_method("set_affordable_limit"):
			shop.set_affordable_limit(coins)

func _on_shop_reroll(cost: int) -> void:
	var team := 0
	if is_instance_valid(economy):
		if economy.has_method("can_afford") and not economy.can_afford(team, cost):
			push_warning("No hay oro para reroll.")
			return
		if economy.has_method("spend") and not economy.spend(team, cost):
			return
	if is_instance_valid(shop) and shop.has_method("generate_offers"):
		shop.generate_offers()
