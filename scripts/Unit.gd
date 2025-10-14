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

	if team == 1 and drag_area:
		drag_area.monitoring = false
		drag_area.monitorable = false

	if not atk_timer:
		atk_timer = Timer.new()
		add_child(atk_timer)
	atk_timer.one_shot = true

func _process(delta: float) -> void:
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

func place_on_tile(tile: Tile) -> void:
	if tile == null: return
	_occupy_tile(tile)
	current_tile = tile
	global_position = tile.global_position

# ---- Tile distance / range helpers ----
func _tile_distance(a: Tile, b: Tile) -> int:
	if a == null or b == null:
		return 9999
	var dq := a.q - b.q
	var dr := a.r - b.r
	var ds := -(a.q + a.r) - (-(b.q + b.r))
	return (abs(dq) + abs(dr) + abs(ds)) / 2

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
