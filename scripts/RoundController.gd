extends Node

signal round_started
signal round_reset

var build_phase: bool = true
var round_active: bool = false

func start_round() -> void:
	build_phase = false
	round_active = true
	_update_units_build_phase(false)
	emit_signal("round_started")

func reset_round_to_build_phase() -> void:
	build_phase = true
	round_active = false
	_update_units_build_phase(true)
	emit_signal("round_reset")

func _update_units_build_phase(enabled: bool) -> void:
	var units := get_tree().get_nodes_in_group("units")
	for u in units:
		if u.has_method("set_build_phase"):
			u.set_build_phase(enabled)
