extends Node2D 
class_name Unit

@export var stats: UnitStats
@export var team: int = 0
@export var move_tween_time: float = 0.12
@export var auto_attack_for_players: bool = false
@export var shape_size: float = 22.0

@onready var body: Polygon2D = $Body
@onready var hpbar: Node = $HealthBar
@onready var atk_timer: Timer = $AttackTimer
@onready var drag_area: Area2D = $DragArea

# ---------------- Tooltip UI ----------------
var _hover_card: PanelContainer = null
var _hover_title: Label = null
var _hover_attack: RichTextLabel = null
var _hover_hp: Label = null
var _eq_title: Label = null
var _eq_flow: HFlowContainer = null
var _hover_tween: Tween = null

var current_hp: int = 1
var dead: bool = false

# Dragging
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

# Grid / tile
var current_tile: Tile = null

# AI
var target: Unit = null

# Pathfinding
var path: Array = []              # Array<Tile>
var path_idx: int = 0
var desired_next_tile: Tile = null
var repath_cooldown: float = 0.25
var _repath_timer: float = 0.0

# Build phase
var build_phase_enabled: bool = true

signal died(unit: Unit)

const DEFAULT_MAX_HP := 5
const DEFAULT_ATTACK := 1
const DEFAULT_ATTACK_RANGE := 64.0
const DEFAULT_ATTACK_COOLDOWN := 0.8
const DEFAULT_MOVE_SPEED := 80.0
const DEFAULT_COLOR := Color(0.8, 0.8, 0.8)
const DEFAULT_TYPE := "square"

# --- Buff temporal por ronda ---
var round_attack_bonus: float = 0.0

func reset_round_bonuses() -> void:
	round_attack_bonus = 0.0

func add_round_attack_bonus(v: float) -> void:
	round_attack_bonus += v

func get_attack() -> float:
	# Usa ATK() como única fuente de verdad
	return float(ATK())

func _stat(name: String, default):
	if stats == null:
		return default
	var v = stats.get(name)
	return default if v == null else v

func MAX_HP() -> int:       return int(_stat("max_hp",            DEFAULT_MAX_HP))

# 🔥 IMPORTANTE: ahora incluye el bonus de ronda aplicado por ecuaciones
func ATK() -> int:
	var base := float(_stat("attack", DEFAULT_ATTACK))
	return int(round(base + round_attack_bonus))

func ATK_RANGE() -> float:  return float(_stat("attack_range",    DEFAULT_ATTACK_RANGE))
func ATK_CD() -> float:     return float(_stat("attack_cooldown", DEFAULT_ATTACK_COOLDOWN))
func MOVE_SPD() -> float:   return float(_stat("move_speed",      DEFAULT_MOVE_SPEED))
func BASE_COLOR() -> Color: return Color(_stat("color",           DEFAULT_COLOR))
func TYPE_STR() -> String:  return String(_stat("unit_type",      DEFAULT_TYPE))

func _ready() -> void:
	z_index = 10
	if body: body.z_index = 10

	_apply_visual_from_stats()
	_apply_team_tint()

	current_hp = MAX_HP()
	_update_healthbar()

	add_to_group("units")
	add_to_group("team_%d" % team)

	set_build_phase(true) # start in build phase
	_ensure_area2d_for_hover()
	_create_hover_card()

	if team == 1 and drag_area:
		drag_area.monitoring = false
		drag_area.monitorable = false

	if not atk_timer:
		atk_timer = Timer.new()
		add_child(atk_timer)
	atk_timer.one_shot = true

func _process(delta: float) -> void:
	# mantener esto para que la tarjeta siga a la unidad
	if _hover_card != null and _hover_card.visible:
		_position_hover_card()

	if not dead and current_hp <= 0:
		_die()
		return
	_repath_timer = max(0.0, _repath_timer - delta)


func _physics_process(delta: float) -> void:
	if dead or build_phase_enabled:
		return
	ai_think_and_attack()
	var next_pos := propose_next_position(delta)
	commit_position(next_pos)

# ───────────── IA ─────────────
func ai_think_and_attack() -> void:
	if dead or is_dragging or build_phase_enabled or (current_tile != null and current_tile.is_bench):
		return
		
	if target == null or not is_instance_valid(target) or not target._is_alive():
		target = _find_closest_target()
	if target == null:
		return

	if current_tile == null:
		_current_tile_from_grid()
		if current_tile != null:
			global_position = current_tile.global_position

	if _in_attack_range_of(target):
		_try_act_on_target(target)
		desired_next_tile = null
		return

	var goal_tile: Tile = target.current_tile
	if goal_tile == null or goal_tile.is_bench:
		var g := _grid()
		if g != null:
			goal_tile = g.get_grid_tile_at_position(target.global_position)

	var approach: Tile = _best_approach_tile(goal_tile)

	if _need_repath(approach):
		_compute_path_to(approach)

	desired_next_tile = _next_free_step()

func _need_repath(goal_tile: Tile) -> bool:
	if _repath_timer > 0.0:
		return false
	if goal_tile == null:
		return true
	if path.is_empty():
		return true
	if path.size() > 0 and path.back() != goal_tile:
		return true
	if path_idx < path.size():
		var next_t: Tile = path[path_idx]
		if "occupied" in next_t and next_t.occupied:
			return true
	return false

func _compute_path_to(goal_tile: Tile) -> void:
	var g := _grid()
	if g == null:
		path = []; path_idx = 0; return

	if current_tile == null or current_tile.is_bench:
		current_tile = g.get_grid_tile_at_position(global_position)

	if current_tile == null or goal_tile == null:
		path = []; path_idx = 0; return

	path = g.find_path(current_tile, goal_tile, true)
	path_idx = 1 if path.size() >= 2 else path.size()
	_repath_timer = repath_cooldown

func _next_free_step() -> Tile:
	if path_idx >= path.size():
		return null
	var next_t: Tile = path[path_idx]
	if "occupied" in next_t and next_t.occupied:
		return null
	return next_t

func _best_approach_tile(goal_tile: Tile) -> Tile:
	var g := _grid()
	if g == null or goal_tile == null:
		return null

	var neighbors: Array = g.neighbors_of(goal_tile)
	var candidates: Array = []
	for t in neighbors:
		var tile := t as Tile
		if tile == null or tile.is_bench:
			continue
		var occ: bool = ("occupied" in tile and tile.occupied)
		if not occ:
			candidates.append(tile)

	if candidates.size() == 0:
		var best: Tile = null
		var best_d2: float = INF
		for t2 in neighbors:
			var tt: Tile = t2 as Tile
			if tt == null or tt.is_bench: continue
			var d2: float = tt.global_position.distance_squared_to(global_position)
			if d2 < best_d2:
				best_d2 = d2
				best = tt
		return best

	var best_free: Tile = null
	var best_free_d2: float = INF
	for free_tile in candidates:
		var d2f: float = free_tile.global_position.distance_squared_to(global_position)
		if d2f < best_free_d2:
			best_free_d2 = d2f
			best_free = free_tile
	return best_free

# ───────────── Movimiento ─────────────
func propose_next_position(delta: float) -> Vector2:
	if dead or is_dragging or build_phase_enabled:
		return _center_of_current_or_self()

	if target and is_instance_valid(target):
		if _in_attack_range_of(target):
			return _center_of_current_or_self()

	if desired_next_tile == null:
		return _center_of_current_or_self()

	var to: Vector2 = desired_next_tile.global_position
	var dir: Vector2 = (to - global_position)
	var dist_step: float = MOVE_SPD() * delta
	if dir.length() <= dist_step or move_tween_time <= 0.0:
		return to
	else:
		return global_position + dir.normalized() * dist_step

func commit_position(pos: Vector2) -> void:
	if dead or is_dragging or build_phase_enabled:
		if current_tile != null:
			global_position = current_tile.global_position
		else:
			global_position = pos
		return

	global_position = pos

	if desired_next_tile != null and global_position.distance_to(desired_next_tile.global_position) < 0.5:
		_free_current_tile()
		_occupy_tile(desired_next_tile)
		current_tile = desired_next_tile
		desired_next_tile = null
		path_idx = min(path_idx + 1, path.size())
	elif desired_next_tile == null and current_tile != null:
		global_position = current_tile.global_position

# ───────────── Objetivos ─────────────
func _is_healer() -> bool:
	var v = _stat("is_healer", null)
	if v != null and typeof(v) == TYPE_BOOL:
		return v
	return TYPE_STR().to_lower() == "cross"

func _should_retarget(t: Unit) -> bool:
	if not _is_healer():
		return false
	return (not t._is_alive()) or (t.current_hp >= t.MAX_HP())

func _find_closest_target() -> Unit:
	if _is_healer():
		var best: Unit = null
		var best_d2: float = INF
		for candidate in get_tree().get_nodes_in_group("team_%d" % team):
			if candidate == null or not candidate is Unit:
				continue
			var u := candidate as Unit
			if not u._is_alive() or u == self:
				continue
			if u.current_hp >= u.MAX_HP():
				continue
			var d2: float = (u.global_position - global_position).length_squared()
			if d2 < best_d2:
				best_d2 = d2
				best = u
		return best
	else:
		var best2: Unit = null
		var best_d2b: float = INF
		for candidate in get_tree().get_nodes_in_group("team_%d" % (1 - team)):
			if candidate == null or not candidate is Unit:
				continue
			var u2 := candidate as Unit
			if not u2._is_alive():
				continue
			var d2b: float = (u2.global_position - global_position).length_squared()
			if d2b < best_d2b:
				best_d2b = d2b
				best2 = u2
		return best2

# ───────────── Visuals ─────────────
func _apply_visual_from_stats() -> void:
	if not body:
		return
	body.color = BASE_COLOR()
	body.polygon = _polygon_for_type(TYPE_STR(), shape_size)
	body.position = Vector2.ZERO
	body.antialiased = true
	if body.has_method("queue_redraw"):
		body.queue_redraw()

func _apply_team_tint() -> void:
	if not body:
		return
	var team_col := Color(0.28, 0.58, 1.00) if team == 0 else Color(1.00, 0.36, 0.36)
	var base := body.color
	body.color = Color(base.r * team_col.r, base.g * team_col.g, base.b * team_col.b, base.a)

func _polygon_for_type(t: String, r: float) -> PackedVector2Array:
	t = t.to_lower()
	match t:
		"square":   return _regular_ngon(4, r, PI / 4.0)
		"triangle": return _regular_ngon(3, r, -PI / 2.0)
		"circle":   return _regular_ngon(24, r, 0.0)
		"cross":    return _cross_points(r, r * 0.45)
		"star":     return _star_points(5, r, r * 0.45, -PI / 2.0)
		_:          return _regular_ngon(6, r, 0.0)

func _regular_ngon(n: int, r: float, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := phase + TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

func _cross_points(r: float, half_thick: float) -> PackedVector2Array:
	var a := half_thick
	var R := r
	return PackedVector2Array([
		Vector2(-a, -R), Vector2(a, -R),
		Vector2(a, -a),  Vector2(R, -a),
		Vector2(R, a),   Vector2(a, a),
		Vector2(a, R),   Vector2(-a, R),
		Vector2(-a, a),  Vector2(-R, a),
		Vector2(-R, -a), Vector2(-a, -a),
	])

func _star_points(points: int, r_outer: float, r_inner: float, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var total := points * 2
	for i in range(total):
		var r := r_outer if i % 2 == 0 else r_inner
		var a := phase + TAU * float(i) / float(total)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

# ───────────── Golpear/Curar ─────────────
func _try_act_on_target(victim: Unit) -> void:
	if not atk_timer.is_stopped():
		return
	if not is_instance_valid(victim) or not victim._is_alive():
		return

	var healer := _is_healer()
	var ranged := _is_ranged()

	if healer:
		if victim.team != team:
			return
		if victim.current_hp >= victim.MAX_HP():
			return

	if ranged:
		if healer: _show_heal_beam_vfx(victim)
		else:      _show_ranged_vfx(victim)
	else:
		if healer: _show_heal_melee_vfx(victim)
		else:      _show_melee_vfx(victim)

	if healer:
		victim.heal(ATK())
	else:
		if victim.team == team:
			return
		victim.take_damage(ATK(), self)

	atk_timer.start(ATK_CD())

func _is_ranged() -> bool:
	return ATK_RANGE() >= shape_size * 3.5

# ───────────── Vida / Muerte ─────────────
func take_damage(amount: int, _from: Unit = null) -> void:
	if dead:
		return
	current_hp = max(0, current_hp - amount)
	_update_healthbar()
	if current_hp <= 0 and not dead:
		_die()

func heal(amount: int) -> void:
	if dead:
		return
	var before := current_hp
	current_hp = clamp(current_hp + amount, 0, MAX_HP())
	if current_hp != before:
		_update_healthbar()
		_heal_flash(self)

func _die() -> void:
	if dead:
		return
	dead = true
	set_process(false)
	set_physics_process(false)
	if drag_area:
		drag_area.monitoring = false
		drag_area.monitorable = false
	_free_current_tile()
	emit_signal("died", self)
	queue_free()

func _is_alive() -> bool:
	return not dead and current_hp > 0

func _update_healthbar() -> void:
	if hpbar and hpbar.has_method("set_values"):
		hpbar.set_values(current_hp, MAX_HP())

# ───────────── VFX ─────────────
func _show_ranged_vfx(victim: Unit) -> void:
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = (body.color if body else Color(1, 1, 1))
	line.points = PackedVector2Array([global_position, victim.global_position])
	var root := get_tree().get_current_scene()
	if root == null: root = self
	root.add_child(line)
	var tl := line.create_tween()
	tl.tween_property(line, "modulate:a", 0.0, 0.14)
	tl.parallel().tween_property(line, "width", 0.0, 0.14)
	tl.finished.connect(func(): line.queue_free())
	_hit_flash(victim)

func _show_melee_vfx(victim: Unit) -> void:
	var dir := (victim.global_position - global_position).normalized()
	var start_pos := global_position
	var lunge_pos := start_pos + dir * 10.0
	var tw := create_tween()
	tw.tween_property(self, "global_position", lunge_pos, 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", start_pos, 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_hit_flash(victim)

func _show_heal_beam_vfx(victim: Unit) -> void:
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = Color(0.5, 1.0, 0.5)
	line.points = PackedVector2Array([global_position, victim.global_position])
	var root := get_tree().get_current_scene()
	if root == null: root = self
	root.add_child(line)
	var tl := line.create_tween()
	tl.tween_property(line, "modulate:a", 0.0, 0.18)
	tl.parallel().tween_property(line, "width", 0.0, 0.18)
	tl.finished.connect(func(): line.queue_free())
	_heal_flash(victim)

func _show_heal_melee_vfx(victim: Unit) -> void:
	var dir := (victim.global_position - global_position).normalized()
	var start_pos := global_position
	var lunge_pos := start_pos + dir * 8.0
	var tw := create_tween()
	tw.tween_property(self, "global_position", lunge_pos, 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", start_pos, 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_heal_flash(victim)

func _hit_flash(u: Unit) -> void:
	if u == null or not is_instance_valid(u) or u.body == null:
		return
	var b := u.body
	var tb := b.create_tween()
	tb.tween_property(b, "modulate", Color(1, 1, 1, 0.4), 0.05)
	tb.tween_property(b, "modulate", Color(1, 1, 1, 1.0), 0.10)

func _heal_flash(u: Unit) -> void:
	if u == null or not is_instance_valid(u) or u.body == null:
		return
	var b := u.body
	var tb := b.create_tween()
	tb.tween_property(b, "modulate", Color(0.6, 1.0, 0.6, 1.0), 0.06)
	tb.tween_property(b, "modulate", Color(1, 1, 1, 1.0), 0.10)

# ───────────── Drag & snap (build phase only) ─────────────
func _input(event: InputEvent) -> void:
	if team != 0 or dead or not build_phase_enabled:
		return
	
	var main := get_tree().get_first_node_in_group("main")
	if main != null and main.has_method("is_placing_equation") and main.is_placing_equation():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _mouse_over_unit():
				is_dragging = true
				drag_offset = global_position - get_global_mouse_position()
				_free_current_tile()
		else:
			if is_dragging:
				is_dragging = false
				_snap_to_nearest_blue(get_global_mouse_position())
	elif event is InputEventMouseMotion and is_dragging:
		global_position = get_global_mouse_position() + drag_offset

func _mouse_over_unit() -> bool:
	return (get_global_mouse_position() - global_position).length() <= max(18.0, shape_size * 1.2)

func _snap_to_nearest_blue(mouse_pos: Vector2) -> void:
	var tile := _nearest_free_blue_tile(mouse_pos)
	if tile == null:
		return
	_occupy_tile(tile)
	current_tile = tile

	if move_tween_time > 0.0:
		var tw: Tween = create_tween()
		tw.tween_property(self, "global_position", tile.global_position, move_tween_time)
	else:
		global_position = tile.global_position

func _nearest_free_blue_tile(pos: Vector2) -> Tile:
	var best: Tile = null
	var best_d2: float = INF
	var root := get_parent()
	if root == null: root = get_tree().get_current_scene()
	if root == null: return null

	for n in root.get_children():
		if n is Tile:
			var t := n as Tile
			if not t.is_blue: continue
			if "occupied" in t and t.occupied: continue
			var d2: float = (t.global_position - pos).length_squared()
			if d2 < best_d2:
				best_d2 = d2
				best = t
		if n.get_child_count() > 0:
			for m in n.get_children():
				if m is Tile:
					var tt := m as Tile
					if not tt.is_blue: continue
					if "occupied" in tt and tt.occupied: continue
					var dd2: float = (tt.global_position - pos).length_squared()
					if dd2 < best_d2:
						best_d2 = dd2
						best = tt
	return best

func place_on_tile(t: Tile) -> void:
	if t == null:
		return

	# Libera la casilla anterior si estaba ocupada
	if current_tile != null and current_tile.has_method("set_occupied"):
		current_tile.set_occupied(false)

	# Mueve la unidad a la nueva tile
	current_tile = t
	global_position = t.global_position

	# Marca ocupación y actualiza tooltip
	t.set_occupied(true, self)   # <-- aquí va esta línea
	refresh_hover_card()         # <-- y esta


# ---- Tile distance / range helpers ----
func _tile_distance(a: Tile, b: Tile) -> int:
	if a == null or b == null:
		return 9999
	var dq := a.q - b.q
	var dr := a.r - b.r
	var ds := -(a.q + a.r) - (-(b.q + b.r))
	return (abs(dq) + abs(dr) + abs(ds)) / 2

func refresh_hover_card() -> void:
	if _hover_card == null:
		return
	# puedes actualizar siempre...
	_update_hover_card()
	# ...o solo si está visible:
	# if _hover_card.visible:
	# 	_update_hover_card()

func _in_attack_range_of(u: Unit) -> bool:
	if current_tile != null and not current_tile.is_bench and u.current_tile != null and not u.current_tile.is_bench:
		var max_tiles := 2 if _is_ranged() else 1
		if team == 1:
			max_tiles = 1
		return _tile_distance(current_tile, u.current_tile) <= max_tiles
	return global_position.distance_to(u.global_position) <= ATK_RANGE()

# ───────────── Build phase toggle / occupancy ─────────────
func set_build_phase(enabled: bool) -> void:
	build_phase_enabled = enabled
	set_physics_process(!enabled) # AI on when round starts

	if not enabled and current_tile == null:
		var g := _grid()
		if g:
			var snap := g.get_grid_tile_at_position(global_position)
			if snap != null:
				_occupy_tile(snap)
				current_tile = snap
				global_position = snap.global_position

	if not enabled and is_dragging:
		is_dragging = false
	if drag_area:
		var allow_drag := enabled and team == 0
		drag_area.monitoring = allow_drag
		drag_area.monitorable = allow_drag
	modulate = Color(1,1,1,1) if enabled else Color(1,1,1,0.92)

func _nearest_side_grid_tile(side_team: int) -> Tile:
	var g := _grid()
	if g == null: return null
	var best: Tile = null
	var best_d2: float = INF
	for q in range(g.grid_width):
		if not g.tiles.has(q): continue
		for r in range(g.grid_height):
			if not g.tiles[q].has(r): continue
			var t: Tile = g.tiles[q][r]
			if side_team == 0 and not t.is_blue: continue
			if side_team == 1 and not t.is_red: continue
			var d2: float = t.global_position.distance_squared_to(global_position)
			if d2 < best_d2:
				best_d2 = d2
				best = t
	return best

func _free_current_tile() -> void:
	if current_tile:
		if "occupied" in current_tile: current_tile.occupied = false
		if "occupant" in current_tile and current_tile.occupant == self:
			current_tile.occupant = null

func _occupy_tile(t: Tile) -> void:
	_free_current_tile()
	if "occupied" in t: t.occupied = true
	if "occupant" in t: t.occupant = self

func _current_tile_from_grid() -> void:
	var g := _grid()
	if g:
		var t := g.get_grid_tile_at_position(global_position)
		if t != null:
			current_tile = t

func _center_of_current_or_self() -> Vector2:
	if current_tile != null:
		return current_tile.global_position
	return global_position

func _grid() -> Grid:
	var gs := get_tree().get_nodes_in_group("grid")
	return gs[0] if gs.size() > 0 else null

# --- HOVER CARD / TOOLTIP ---

func _ensure_area2d_for_hover() -> void:
	var area := get_node_or_null("Area2D")
	if area == null:
		area = Area2D.new()
		area.name = "Area2D"
		var cs := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 24.0
		cs.shape = shape
		area.add_child(cs)
		add_child(area)
	if not area.mouse_entered.is_connected(_on_mouse_enter):
		area.mouse_entered.connect(_on_mouse_enter)
	if not area.mouse_exited.is_connected(_on_mouse_exit):
		area.mouse_exited.connect(_on_mouse_exit)

func _create_hover_card() -> void:
	if _hover_card != null:
		return

	_hover_card = PanelContainer.new()
	_hover_card.visible = false
	_hover_card.z_index = 1000

	# estilo panel
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.10, 0.12, 0.95)           # fondo oscuro
	sb.border_color = Color(0.23, 0.25, 0.30, 1.0)        # borde
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	sb.corner_radius_bottom_left = 10
	_hover_card.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(240, 0)
	vb.add_theme_constant_override("separation", 6)

	# título
	_hover_title = Label.new()
	_hover_title.add_theme_font_size_override("font_size", 18)
	_hover_title.add_theme_color_override("font_color", Color(1,1,1,1))
	vb.add_child(_hover_title)

	# línea ataque (RichText para colorear el valor final)
	_hover_attack = RichTextLabel.new()
	_hover_attack.bbcode_enabled = true
	_hover_attack.scroll_active = false
	_hover_attack.fit_content = true
	_hover_attack.clip_contents = false
	_hover_attack.add_theme_font_size_override("normal_font_size", 16)
	vb.add_child(_hover_attack)

	# línea HP
	_hover_hp = Label.new()
	_hover_hp.add_theme_font_size_override("font_size", 16)
	_hover_hp.add_theme_color_override("font_color", Color(0.85,0.88,0.95,1))
	vb.add_child(_hover_hp)

	# título ecuaciones
	_eq_title = Label.new()
	_eq_title.text = "Equations:"
	_eq_title.add_theme_font_size_override("font_size", 14)
	_eq_title.add_theme_color_override("font_color", Color(0.75,0.78,0.85,1))
	vb.add_child(_eq_title)

	# chips de ecuaciones (flujo automático)
	_eq_flow = HFlowContainer.new()
	_eq_flow.add_theme_constant_override("h_separation", 6)
	_eq_flow.add_theme_constant_override("v_separation", 6)
	vb.add_child(_eq_flow)

	_hover_card.add_child(vb)
	add_child(_hover_card)


func _on_mouse_enter() -> void:
	_update_hover_card()
	_hover_card.visible = true
	_position_hover_card()
	if _hover_tween != null and _hover_tween.is_running():
		_hover_tween.kill()
	_hover_card.scale = Vector2(0.9, 0.9)
	_hover_card.modulate = Color(1,1,1,0)
	_hover_tween = create_tween()
	_hover_tween.tween_property(_hover_card, "scale", Vector2(1,1), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hover_tween.parallel().tween_property(_hover_card, "modulate", Color(1,1,1,1), 0.12)

func _on_mouse_exit() -> void:
	if _hover_tween != null and _hover_tween.is_running():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(_hover_card, "modulate", Color(1,1,1,0), 0.10)
	_hover_tween.tween_callback(Callable(self, "_hide_hover_card"))

func _hide_hover_card() -> void:
	_hover_card.visible = false

func _position_hover_card() -> void:
	_hover_card.global_position = global_position + Vector2(0, -64)


func _rebuild_eq_chips(labels: Array[String]) -> void:
	# limpiar
	for c in _eq_flow.get_children():
		c.queue_free()

	for i in range(labels.size()):
		var txt: String = labels[i]
		var kind: String = _kind_from_label(txt)
		var chip := _make_chip(txt, kind)
		_eq_flow.add_child(chip)

func _make_chip(txt: String, kind: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# colores por tipo
	if kind == "plus":
		sb.bg_color = Color(0.11, 0.36, 0.15, 1.0)
	elif kind == "minus":
		sb.bg_color = Color(0.36, 0.14, 0.14, 1.0)
	elif kind == "times":
		sb.bg_color = Color(0.15, 0.20, 0.58, 1.0)
	elif kind == "div":
		sb.bg_color = Color(0.31, 0.20, 0.18, 1.0)
	else:
		sb.bg_color = Color(0.16, 0.18, 0.21, 1.0)
	sb.border_color = Color(0,0,0,0.7)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	p.add_theme_stylebox_override("panel", sb)

	var lab := Label.new()
	lab.text = txt
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color(1,1,1,1))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 2)
	pad.add_theme_constant_override("margin_bottom", 2)
	pad.add_child(lab)
	p.add_child(pad)
	return p

func _kind_from_label(txt: String) -> String:
	var s: String = txt.strip_edges()
	if s.begins_with("+"):
		return "plus"
	if s.begins_with("-"):
		return "minus"
	if s.begins_with("x") or s.begins_with("×") or s.begins_with("*"):
		return "times"
	if s.begins_with("d") or s.begins_with("÷") or s.begins_with("/"):
		return "div"
	return "other"

func _team_accent() -> Color:
	# azul / rojo
	if "team" in self and int(team) == 1:
		return Color(0.85, 0.33, 0.33, 1.0)
	return Color(0.30, 0.70, 0.40, 1.0)

func _update_hover_card() -> void:
	if _hover_card == null:
		return

	# título
	var team_name: String = "Blue"
	if "team" in self and int(team) == 1:
		team_name = "Red"
	_hover_title.text = "%s Unit" % team_name

	# acento sutil en el borde del panel (según equipo)
	var sb_panel := _hover_card.get_theme_stylebox("panel") as StyleBoxFlat
	if sb_panel != null:
		sb_panel.border_color = _team_accent()

	# stats base
	var atk: float = 0.0
	var hp: float = 0.0
	if stats != null:
		if "attack" in stats:
			atk = float(stats.attack)
		if "health" in stats:
			hp = float(stats.health)
		elif "hp" in stats:
			hp = float(stats.hp)

	# ecuaciones acumuladas
	var mod_atk: float = atk
	var labels: Array[String] = []
	if current_tile != null and "equations" in current_tile and not current_tile.equations.is_empty():
		# pliega todas
		var v: float = atk
		for i in range(current_tile.equations.size()):
			var eq := current_tile.equations[i]
			if eq != null:
				if eq.has_method("apply"):
					v = float(eq.apply(v))
				if "label" in eq:
					labels.append(String(eq.label))
		mod_atk = v

	# línea ataque con color
	var delta: float = mod_atk - atk
	var color_name: String = "white"
	if delta > 0.0:
		color_name = "green"
	elif delta < 0.0:
		color_name = "red"
	var sign: String = "+"
	if delta < 0.0:
		sign = "-"
	var abs_delta: float = absf(delta)

	_hover_attack.bbcode_text = "[b]Attack:[/b] %.0f → [color=%s]%.0f[/color] (%s%.0f)" % [
		atk, color_name, mod_atk, sign, abs_delta
	]

	# HP
	_hover_hp.text = "HP: %.0f" % hp

	# chips ecuaciones
	_eq_title.visible = not labels.is_empty()
	_eq_flow.visible = not labels.is_empty()
	_rebuild_eq_chips(labels)
