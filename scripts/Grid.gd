extends Node2D
class_name Grid

@export var grid_width: int = 7
@export var grid_height: int = 5
@export var hex_size: float = 32.0

@export var blue_side_color: Color = Color(0.72, 0.83, 1.00)
@export var red_side_color: Color  = Color(1.00, 0.78, 0.78)
@export var neutral_color: Color   = Color(0.80, 0.80, 0.80)

@export var TileScene: PackedScene
@export var UnitScene: PackedScene
@export var show_demo_spawns: bool = false

# tiles[q][r] => Tile
var tiles: Dictionary = {}
var bench_blue: Array[Tile] = []
var bench_red:  Array[Tile] = []

func _ready() -> void:
	add_to_group("grid")
	_build_grid()
	_build_bench_blue(5)
	_build_bench_red(5)
	if show_demo_spawns and UnitScene:
		_demo_spawn()

# -----------------------------------------------------------------------------
# Construcción de tablero
# -----------------------------------------------------------------------------
func _build_grid() -> void:
	tiles.clear()
	var mid: int = int(floor(grid_width / 2.0))
	for q: int in range(grid_width):
		tiles[q] = {}
		var row: Dictionary = tiles[q]
		for r: int in range(grid_height):
			var t: Tile = _make_tile(q, r)
			# Color / lado
			if q < mid:
				t.is_blue = true
				t.is_red = false
				t.base_color = blue_side_color
			elif q > mid:
				t.is_blue = false
				t.is_red = true
				t.base_color = red_side_color
			else:
				t.is_blue = false
				t.is_red = false
				t.base_color = neutral_color
			add_child(t)
			t.position = _axial_to_world(q, r, hex_size)
			if t.has_method("_update_visual"):
				t._update_visual()
			row[r] = t
		tiles[q] = row

func _make_tile(q: int, r: int) -> Tile:
	var tile: Tile = TileScene.instantiate() as Tile if TileScene != null else Tile.new()
	tile.q = q
	tile.r = r
	tile.is_bench = false
	tile.occupied = false
	tile.occupant = null
	return tile

# Axial -> mundo (HEX plano/flat-top)
func _axial_to_world(q: int, r: int, size: float) -> Vector2:
	var x: float = size * (1.5 * float(q))
	var y: float = size * (sqrt(3.0) * (float(r) + 0.5 * float(q)))
	return Vector2(x, y)

# -----------------------------------------------------------------------------
# Banquillos
# -----------------------------------------------------------------------------
func _grid_bounds() -> Dictionary:
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for q: int in tiles.keys():
		var row: Dictionary = tiles[q]
		for r: int in row.keys():
			var t: Tile = row[r]
			var p: Vector2 = t.global_position
			min_x = min(min_x, p.x)
			max_x = max(max_x, p.x)
			min_y = min(min_y, p.y)
			max_y = max(max_y, p.y)
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}

func _build_bench_blue(bench_count: int) -> void:
	bench_blue.clear()
	if bench_count <= 0:
		return
	var bounds := _grid_bounds()
	var gap_y: float = hex_size * 1.5
	var center_y: float = (bounds["min_y"] + bounds["max_y"]) * 0.5
	var start_y: float = center_y - (bench_count - 1) * 0.5 * gap_y
	var bench_x: float = float(bounds["min_x"]) - hex_size * 2.2
	for i: int in range(bench_count):
		var t: Tile = _make_tile(-100 - i, 0) # id fuera de rejilla
		t.is_blue = true
		t.is_red = false
		t.is_bench = true
		t.base_color = blue_side_color.lerp(Color.WHITE, 0.35)
		add_child(t)
		t.global_position = Vector2(bench_x, start_y + i * gap_y)
		if t.has_method("_update_visual"):
			t._update_visual()
		bench_blue.append(t)

func _build_bench_red(bench_count: int) -> void:
	bench_red.clear()
	if bench_count <= 0:
		return
	var bounds := _grid_bounds()
	var gap_y: float = hex_size * 1.5
	var center_y: float = (bounds["min_y"] + bounds["max_y"]) * 0.5
	var start_y: float = center_y - (bench_count - 1) * 0.5 * gap_y
	var bench_x: float = float(bounds["max_x"]) + hex_size * 2.2
	for i: int in range(bench_count):
		var t: Tile = _make_tile(100 + i, 0) # id fuera de rejilla
		t.is_blue = false
		t.is_red = true
		t.is_bench = true
		t.base_color = red_side_color.lerp(Color.WHITE, 0.35)
		add_child(t)
		t.global_position = Vector2(bench_x, start_y + i * gap_y)
		if t.has_method("_update_visual"):
			t._update_visual()
		bench_red.append(t)

func get_free_bench_tile(team: int) -> Tile:
	var bench: Array[Tile] = bench_blue if team == 0 else bench_red
	for t: Tile in bench:
		if not t.occupied:
			return t
	return null

func place_unit_on_bench(u: Node2D, team: int) -> bool:
	var t: Tile = get_free_bench_tile(team)
	if t == null:
		return false

	# Preferible: que la propia unidad gestione vaciar/ocupar
	if u.has_method("place_on_tile"):
		u.place_on_tile(t)
	else:
		# Fallback manteniendo coherencia de ocupación
		u.global_position = t.global_position
		if t.has_method("set_occupied"):
			t.set_occupied(true, u)
		else:
			t.occupied = true
			t.occupant = u
		if "current_tile" in u:
			u.current_tile = t

	return true

# -----------------------------------------------------------------------------
# Ordenación y despliegue automático
# -----------------------------------------------------------------------------
func _cmp_by_x_asc(a: Tile, b: Tile) -> bool:
	return a.global_position.x < b.global_position.x

func _cmp_by_x_desc(a: Tile, b: Tile) -> bool:
	return a.global_position.x > b.global_position.x

func _play_tiles_for_team(team: int) -> Array[Tile]:
	var out: Array[Tile] = []
	for q: int in tiles.keys():
		var row: Dictionary = tiles[q]
		for r: int in row.keys():
			var t: Tile = row[r]
			if t.is_bench:
				continue
			if team == 0 and t.is_blue:
				out.append(t)
			elif team == 1 and t.is_red:
				out.append(t)
	if team == 0:
		out.sort_custom(Callable(self, "_cmp_by_x_asc"))
	else:
		out.sort_custom(Callable(self, "_cmp_by_x_desc"))
	return out

func auto_deploy_from_bench(team: int, max_units: int = 999) -> void:
	var bench: Array[Tile] = bench_blue if team == 0 else bench_red
	var play_tiles: Array[Tile] = _play_tiles_for_team(team)
	var placed: int = 0
	for bt: Tile in bench:
		if bt.occupied and bt.occupant != null:
			var u: Node2D = bt.occupant
			var dest: Tile = null
			for pt: Tile in play_tiles:
				if not pt.occupied:
					dest = pt
					break
			if dest == null:
				break
			if bt.has_method("set_occupied"):
				bt.set_occupied(false)
			u.global_position = dest.global_position
			if "current_tile" in u:
				u.current_tile = dest
			if dest.has_method("set_occupied"):
				dest.set_occupied(true, u)
			placed += 1
			if placed >= max_units:
				break

# -----------------------------------------------------------------------------
# Consultas
# -----------------------------------------------------------------------------
func bench_tiles_for_team(team: int) -> Array[Tile]:
	return bench_blue if team == 0 else bench_red

# Asigna una ecuación a una casilla y refresca su visual
func set_tile_equation(tile: Tile, eq: Equation) -> bool:
	if tile == null or tile.is_bench:
		return false
	# Requiere una unidad encima (aliada o enemiga)
	if tile.occupant == null or not (tile.occupant is Unit):
		return false
	tile.set_equation(eq)
	return true


# Devuelve la Tile más cercana a 'pos' (tablero + banquillos)
func get_tile_at_position(pos: Vector2) -> Tile:
	var best: Tile = null
	var best_d2: float = INF
	# tablero
	for q: int in tiles.keys():
		var row: Dictionary = tiles[q]
		for r: int in row.keys():
			var t: Tile = row[r]
			var d2: float = t.global_position.distance_squared_to(pos)
			if d2 < best_d2:
				best_d2 = d2
				best = t
	# banquillos
	for t: Tile in bench_blue:
		var d2b: float = t.global_position.distance_squared_to(pos)
		if d2b < best_d2:
			best_d2 = d2b
			best = t
	for t: Tile in bench_red:
		var d2r: float = t.global_position.distance_squared_to(pos)
		if d2r < best_d2:
			best_d2 = d2r
			best = t
	return best

# Solo tablero (sin banquillos)
func get_grid_tile_at_position(pos: Vector2) -> Tile:
	var best: Tile = null
	var best_d2: float = INF
	for q: int in tiles.keys():
		var row: Dictionary = tiles[q]
		for r: int in row.keys():
			var t: Tile = row[r]
			var d2: float = t.global_position.distance_squared_to(pos)
			if d2 < best_d2:
				best_d2 = d2
				best = t
	return best

# Vecinos HEX plano (flat-top): E, SE, SW, W, NW, NE
func neighbors_of(t: Tile) -> Array[Tile]:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0),   # E
		Vector2i(0, 1),   # SE
		Vector2i(-1, 1),  # SW
		Vector2i(-1, 0),  # W
		Vector2i(0, -1),  # NW
		Vector2i(1, -1)   # NE
	]
	var out: Array[Tile] = []
	for d: Vector2i in dirs:
		var q2: int = t.q + d.x
		var r2: int = t.r + d.y
		if tiles.has(q2):
			var row: Dictionary = tiles[q2]
			if row.has(r2):
				out.append(row[r2])
	return out

# -----------------------------------------------------------------------------
# Pathfinding
# -----------------------------------------------------------------------------
func _tile_key(t: Tile) -> String:
	return str(t.q) + ":" + str(t.r)

func _hex_distance(a: Tile, b: Tile) -> float:
	var dq: int = abs(a.q - b.q)
	var dr: int = abs(a.r - b.r)
	var ds: int = abs((-a.q - a.r) - (-b.q - b.r))
	return float(max(dq, max(dr, ds)))

func find_path(start: Tile, goal: Tile, allow_goal_occupied: bool = true) -> Array[Tile]:
	if start == null or goal == null:
		return []
	if start == goal:
		return [start]

	var open: Dictionary = {}       # String -> Tile
	var came_from: Dictionary = {}  # String -> Tile
	var g_score: Dictionary = {}    # String -> float
	var f_score: Dictionary = {}    # String -> float

	var start_k: String = _tile_key(start)
	open[start_k] = start
	g_score[start_k] = 0.0
	f_score[start_k] = _hex_distance(start, goal)

	while open.size() > 0:
		var current_key: String = ""
		var current_tile: Tile = null
		var best_f: float = INF
		for k in open.keys():
			var f: float = f_score.get(k, INF)
			if f < best_f:
				best_f = f
				current_key = String(k)
				current_tile = open[k]
		if current_tile == goal:
			var path: Array[Tile] = [current_tile]
			while came_from.has(current_key):
				current_tile = came_from[current_key]
				current_key = _tile_key(current_tile)
				path.push_front(current_tile)
			return path

		open.erase(current_key)
		var cur_neighbors: Array[Tile] = neighbors_of(current_tile)
		for n: Tile in cur_neighbors:
			var n_key: String = _tile_key(n)
			# si está ocupado y no es la meta (o no permitimos ocupada), saltar
			if n.occupied and (n != goal or not allow_goal_occupied):
				continue

			var current_g: float = float(g_score.get(current_key, INF))
			var tentative: float = current_g + 1.0
			var n_g: float = float(g_score.get(n_key, INF))

			if tentative < n_g:
				came_from[n_key] = current_tile
				g_score[n_key] = tentative
				f_score[n_key] = tentative + _hex_distance(n, goal)
				open[n_key] = n

	return []

# -----------------------------------------------------------------------------
# Utilidades de bounds/centro del tablero (sin banquillos por defecto)
# -----------------------------------------------------------------------------
func board_rect(include_benches: bool = false) -> Rect2:
	var first: bool = true
	var min_x: float = 0.0
	var max_x: float = 0.0
	var min_y: float = 0.0
	var max_y: float = 0.0

	for q: int in tiles.keys():
		var row: Dictionary = tiles[q]
		for r: int in row.keys():
			var t: Tile = row[r]
			var p: Vector2 = t.global_position
			if first:
				first = false
				min_x = p.x; max_x = p.x
				min_y = p.y; max_y = p.y
			else:
				min_x = min(min_x, p.x); max_x = max(max_x, p.x)
				min_y = min(min_y, p.y); max_y = max(max_y, p.y)

	if include_benches:
		for bt: Tile in bench_blue:
			var p2: Vector2 = bt.global_position
			min_x = min(min_x, p2.x); max_x = max(max_x, p2.x)
			min_y = min(min_y, p2.y); max_y = max(max_y, p2.y)
		for rt: Tile in bench_red:
			var p3: Vector2 = rt.global_position
			min_x = min(min_x, p3.x); max_x = max(max_x, p3.x)
			min_y = min(min_y, p3.y); max_y = max(max_y, p3.y)

	var size: Vector2 = Vector2(max_x - min_x, max_y - min_y)
	return Rect2(Vector2(min_x, min_y), size)

func board_center(include_benches: bool = false) -> Vector2:
	var rect: Rect2 = board_rect(include_benches)
	return rect.position + rect.size * 0.5

# -----------------------------------------------------------------------------
# Demo
# -----------------------------------------------------------------------------
func _demo_spawn() -> void:
	if UnitScene == null:
		return
	var blue_tile: Tile = (tiles[0] as Dictionary)[int(grid_height / 2)]
	var red_tile:  Tile = (tiles[grid_width - 1] as Dictionary)[int(grid_height / 2)]

	var ub: Node2D = UnitScene.instantiate()
	if "team" in ub:
		ub.team = 0
	add_child(ub)
	ub.global_position = blue_tile.global_position
	if blue_tile.has_method("set_occupied"):
		blue_tile.set_occupied(true, ub)

	var ur: Node2D = UnitScene.instantiate()
	if "team" in ur:
		ur.team = 1
	add_child(ur)
	ur.global_position = red_tile.global_position
	if red_tile.has_method("set_occupied"):
		red_tile.set_occupied(true, ur)

func _attach_placeholder_if_invisible(u: Node2D) -> void:
	var has_visual: bool = false
	for child in u.get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			has_visual = true
			break
	if has_visual:
		return
	var poly: Polygon2D = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0, -10), Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0)
	])
	poly.color = Color(1, 1, 0, 1)
	u.add_child(poly)
	if u is CanvasItem:
		(u as CanvasItem).z_index = 100
