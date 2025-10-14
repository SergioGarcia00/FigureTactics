# res://resources/Equation.gd
extends Resource
class_name Equation

enum Op { ADD, SUB, MUL, DIV }

@export var op: Op = Op.ADD
@export var amount: float = 0.0
@export var label: String = ""   # texto para UI, p.ej. "+3", "×4"
@export var cost: int = 1        # precio en la tienda

func apply(value: float) -> float:
	match op:
		Op.ADD: return value + amount
		Op.SUB: return value - amount
		Op.MUL: return value * amount
		Op.DIV: return (value / amount) if amount != 0.0 else value
	return value

func op_symbol() -> String:
	match op:
		Op.ADD: return "+"
		Op.SUB: return "-"
		Op.MUL: return "×"
		Op.DIV: return "÷"
	return "?"
