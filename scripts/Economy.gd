extends Node
class_name Economy

signal balance_changed(team: int, coins: int)

@export_range(0, 999, 1) var starting_coins: int = 10


var _coins: Dictionary = {} 

func _ready() -> void:
	reset()

func reset() -> void:
	_coins.clear()
	_coins[0] = starting_coins
	_coins[1] = starting_coins
	emit_signal("balance_changed", 0, _coins[0])
	emit_signal("balance_changed", 1, _coins[1])

func _ensure_team(team: int) -> void:
	if not _coins.has(team):
		_coins[team] = starting_coins
		emit_signal("balance_changed", team, _coins[team])

func balance_of(team: int) -> int:
	return int(_coins.get(team, 0))

func can_afford(team: int, cost: int) -> bool:
	if cost <= 0:
		return true
	return balance_of(team) >= cost

func add(team: int, amount: int) -> void:
	_ensure_team(team)
	var new_balance: int = max(0, balance_of(team) + amount)
	if new_balance == _coins[team]:
		return
	_coins[team] = new_balance
	emit_signal("balance_changed", team, _coins[team])

func spend(team: int, cost: int) -> bool:
	if cost <= 0:
		return true
	if not can_afford(team, cost):
		return false
	_coins[team] = balance_of(team) - cost
	emit_signal("balance_changed", team, _coins[team])
	return true



func set_balance(team: int, coins: int) -> void:
	_ensure_team(team)
	_coins[team] = max(0, coins)
	emit_signal("balance_changed", team, _coins[team])

func transfer(from_team: int, to_team: int, amount: int) -> bool:
	if amount <= 0:
		return true
	if not spend(from_team, amount):
		return false
	add(to_team, amount)
	return true
