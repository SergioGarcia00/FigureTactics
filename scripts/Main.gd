extends Node2D

@onready var grid: Grid = $Grid
@onready var cam: Camera2D = $Camera2D
@onready var start_button: Button = $"CanvasLayer/StartButton"
@onready var reset_button: Button = $"CanvasLayer/ResetButton"
@onready var economy: Node = get_node_or_null("Economy")
@onready var blue_label: Label = $"CanvasLayer/TopBar/BlueCoinsLabel" if has_node("CanvasLayer/TopBar/BlueCoinsLabel") else null
@onready var random_red_button: Button = $"CanvasLayer/TopBar/Next"
@onready var shop: Shop = $"CanvasLayer/RightDock/HBoxContainer/Shop"
@onready var eq_shop: EquationShop = $"CanvasLayer/RightDock/HBoxContainer/EquationShop"

var _pending_equation: Equation = null
var _placing_equation := false
var _selected_tile: Tile = null

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
	add_to_group("main")

	
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


	if is_instance_valid(economy):
		if economy.has_signal("balance_changed") and not economy.balance_changed.is_connected(_on_balance_changed):
			economy.balance_changed.connect(_on_balance_changed)
		if is_instance_valid(blue_label):
			var coins := 0
			if economy.has_method("balance_of"):
				coins = int(economy.balance_of(0))
			_update_blue_label(coins)
	
	if is_instance_valid(random_red_button) and not random_red_button.pressed.is_connected(_on_random_red_pressed):
		random_red_button.pressed.connect(_on_random_red_pressed)

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

	if is_instance_valid(eq_shop):
		eq_shop.set_pool(EQ_POOL)
		if not eq_shop.equation_buy_requested.is_connected(_on_equation_buy):
			eq_shop.equation_buy_requested.connect(_on_equation_buy)
		if not eq_shop.reroll_requested.is_connected(_on_equation_reroll):
			eq_shop.reroll_requested.connect(_on_equation_reroll)
		eq_shop.generate_offers()

	if get_tree().get_nodes_in_group("units").is_empty():
		_spawn_random_teams(NUM_BLUE, NUM_RED)
	_debug_report_units()

	await get_tree().process_frame
	_center_and_fit_camera(false, 64.0)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _process(_delta: float) -> void:
	
	if _placing_equation and _pending_equation != null:
		_highlight_valid_equation_targets()

func _highlight_valid_equation_targets() -> void:
	
	for q in grid.tiles:
		for r in grid.tiles[q]:
			var tile: Tile = grid.tiles[q][r] as Tile
			if tile and tile.has_method("reset_color"):
				tile.reset_color()

	var hover_tile: Tile = _tile_under_mouse()
	if hover_tile and _can_apply_equation_on_tile(hover_tile, 0):
		if hover_tile.has_method("highlight"):
			if hover_tile.is_blue:
				hover_tile.highlight(Color(0.3, 0.8, 0.3))  # You
			else:
				hover_tile.highlight(Color(0.8, 0.3, 0.3))  # Enemy
	elif hover_tile and hover_tile.has_method("highlight"):
		hover_tile.highlight(Color(0.5, 0.5, 0.5, 0.5))  # invalid

func is_placing_equation() -> bool:
	return _placing_equation and _pending_equation != null

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


# ========= ECUATIONS =========
func _on_equation_buy(eq: Equation) -> void:
	_pending_equation = eq
	_placing_equation = true
	if _selected_tile and _can_apply_equation_on_tile(_selected_tile, 0):
		_apply_equation_on_tile(_selected_tile, eq)


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


func _input(event: InputEvent) -> void:
	if not _placing_equation or _pending_equation == null:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var t: Tile = _tile_under_mouse()
		if t != null and _can_apply_equation_on_tile(t, 0):
			_apply_equation_on_tile(t, _pending_equation)
		else:
			print("Invalid target - pick a non-bench hex that has any unit on it")
		get_viewport().set_input_as_handled()
		return

	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) \
	or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		_pending_equation = null
		_placing_equation = false
		if _selected_tile:
			_selected_tile.unmark_selected()
			_selected_tile = null
		for q in grid.tiles:
			for r in grid.tiles[q]:
				var tile: Tile = grid.tiles[q][r] as Tile
				if tile and tile.has_method("reset_color"):
					tile.reset_color()
		get_viewport().set_input_as_handled()


func _tile_under_mouse() -> Tile:
	var world_pos: Vector2 = get_global_mouse_position()
	var t: Tile = grid.get_grid_tile_at_position(world_pos) as Tile
	if t != null:
		return t
	var local_pos: Vector2 = grid.to_local(world_pos)
	return grid.get_grid_tile_at_position(local_pos) as Tile



func _can_apply_equation_on_tile(t: Tile, team: int) -> bool:
	if t == null:
		return false
	if t.is_bench:
		return false
	if t.occupant != null and (t.occupant is Unit):
		return true
	if "occupied" in t and t.occupied:
		return true
	return false


func _on_tile_selected_for_equation(tile: Tile) -> void:
	if _placing_equation and _pending_equation != null:
		return

	if _selected_tile and is_instance_valid(_selected_tile) and _selected_tile != tile:
		_selected_tile.unmark_selected()
	_selected_tile = tile
	if _selected_tile:
		_selected_tile.mark_selected()



func _on_tile_drop_equation(tile: Tile, eq: Equation) -> void:
	if _can_apply_equation_on_tile(tile, 0):
		_apply_equation_on_tile(tile, eq)


func _apply_equation_on_tile(tile: Tile, eq: Equation) -> bool:
	if tile == null or eq == null:
		print("DEBUG: Tile or Equation is null")
		return false
	if not _can_apply_equation_on_tile(tile, 0):
		print("DEBUG: Cannot apply equation to this tile")
		return false

	var price := 1
	if "cost" in eq:
		price = int(eq.cost)

	if is_instance_valid(economy):
		if economy.has_method("can_afford") and not economy.can_afford(0, price):
			print("DEBUG: Cannot afford equation (need %d)" % price)
			push_warning("No tienes suficientes monedas (%d)." % price)
			return false
		if economy.has_method("spend") and not economy.spend(0, price):
			print("DEBUG: Failed to spend coins")
			return false

	print("DEBUG: Attempting to set equation on tile")
	if grid.set_tile_equation(tile, eq):
		print("DEBUG: Equation successfully set on tile")

		if _selected_tile:
			_selected_tile.unmark_selected()
		_selected_tile = null
		_pending_equation = null
		_placing_equation = false

		for q in grid.tiles:
			for r in grid.tiles[q]:
				var t2: Tile = grid.tiles[q][r] as Tile
				if t2 and t2.has_method("reset_color"):
					t2.reset_color()

		if is_instance_valid(eq_shop) and eq_shop.has_method("consume_offer"):
			eq_shop.consume_offer(eq)

		var target_type := "aliado" if tile.is_blue else "enemigo"
		push_warning("Ecuación %s aplicada a unidad %s." % [eq.label, target_type])
		return true

	print("DEBUG: grid.set_tile_equation returned false")
	push_warning("No se pudo aplicar en esa casilla.")
	return false


# --- Layout ---
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


# --- Helpers ---
func _set_build_phase_for_all(enabled: bool) -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit:
			(u as Unit).set_build_phase(enabled)


func _apply_tile_buffs_for_team(team: int) -> void:
	for q in grid.tiles.keys():
		var row: Dictionary = grid.tiles[q]
		for r in row.keys():
			var t: Tile = row[r] as Tile
			_apply_tile_buff_on_tile(t, team)
	for t in grid.bench_tiles_for_team(team):
		_apply_tile_buff_on_tile(t, team)


func _apply_tile_buff_on_tile(t: Tile, team: int) -> void:
	if t == null: return
	if not t.occupied or t.occupant == null or not (t.occupant is Unit): return
	var u := t.occupant as Unit
	if u.team != team: return

	var base_attack: float = 0.0
	if u.stats != null and "attack" in u.stats:
		base_attack = float(u.stats.attack)

	if not ("equations" in t) or t.equations.is_empty():
		return

	var modified: float = t.apply_all_equations(base_attack)
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
		var t: Tile = tnode as Tile
		if t == null: 
			continue
		var is_blue_flag := false
		if "is_blue" in t:
			is_blue_flag = t.is_blue
		if is_blue_flag and (not ("is_bench" in t and t.is_bench)):
			blue_out.append(t)
		else:
			non_blue.append(t)


	var had_explicit_red := false
	for tnode in non_blue:
		var tr: Tile = tnode as Tile
		if tr == null: 
			continue
		var is_red_flag := false
		if "is_red" in tr:
			is_red_flag = tr.is_red
		if is_red_flag and not ("is_bench" in tr and tr.is_bench):
			red_out.append(tr)
			had_explicit_red = true

	if not had_explicit_red:
		var min_x := INF
		var max_x := -INF
		for tnode in non_blue:
			var t2: Tile = tnode as Tile
			if t2 == null: 
				continue
			var x := float(t2.global_position.x)
			if x < min_x: min_x = x
			if x > max_x: max_x = x
		var cutoff := (min_x + max_x) * 0.5
		for tnode in non_blue:
			var t3: Tile = tnode as Tile
			if t3 == null: 
				continue
			
			if float(t3.global_position.x) > cutoff and not ("is_bench" in t3 and t3.is_bench):
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


# --- Shop UNITS ---
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

func _clear_team_units(team: int) -> void:
	# Free all units of given team and free their tiles
	for n in get_tree().get_nodes_in_group("team_%d" % team):
		if n is Unit:
			var u: Unit = n
			# Make sure their current tile is freed
			if u.current_tile != null:
				if u.current_tile.has_method("set_occupied"):
					u.current_tile.set_occupied(false)
				else:
					u.current_tile.occupied = false
					if "occupant" in u.current_tile and u.current_tile.occupant == u:
						u.current_tile.occupant = null
			u.queue_free()

func _spawn_random_red(n_red: int) -> void:
	# Reuse your existing tile collection + pools
	if grid == null:
		return
	var blue_tiles: Array = []
	var red_tiles: Array  = []
	_collect_tiles_with_fallback(grid, blue_tiles, red_tiles)
	red_tiles.shuffle()
	n_red = min(n_red, red_tiles.size())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for j in range(n_red):
		var v: Unit = UNIT_SCN.instantiate()
		v.team = 1
		v.stats = STATS_POOL[rng.randi_range(0, STATS_POOL.size() - 1)]
		add_child(v)
		# Use your existing placement method
		if v.has_method("place_on_tile"):
			v.place_on_tile(red_tiles[j])
		else:
			v.global_position = red_tiles[j].global_position
			if red_tiles[j].has_method("set_occupied"):
				red_tiles[j].set_occupied(true, v)
			else:
				red_tiles[j].occupied = true
				red_tiles[j].occupant = v
			if "current_tile" in v:
				v.current_tile = red_tiles[j]
func _on_random_red_pressed() -> void:
	# Optional: if a round is running, bounce back to build/reset state
	if round_active:
		_on_reset_pressed()

	_clear_team_units(1)             # remove existing red units
	_spawn_random_red(NUM_RED)       # spawn new random red combo
