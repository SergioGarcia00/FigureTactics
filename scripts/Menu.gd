extends Control
class_name Menu

@onready var start_button: Button = $TitleContainer/ButtonContainer/StartButton
@onready var how_to_play_button: Button = $TitleContainer/ButtonContainer/HowToPlayButton
@onready var quit_button: Button = $TitleContainer/ButtonContainer/QuitButton


var how_to_play_dialog: AcceptDialog

func _ready() -> void:
	
	start_button.pressed.connect(_on_start_button_pressed)
	how_to_play_button.pressed.connect(_on_how_to_play_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	

	_setup_how_to_play_dialog()
	
	
	if OS.get_name() == "HTML5" or OS.get_name() == "Web":
		quit_button.visible = false

func _setup_how_to_play_dialog() -> void:
	how_to_play_dialog = AcceptDialog.new()
	how_to_play_dialog.title = "How to Play FigureTactics"
	how_to_play_dialog.dialog_text = """
FigureTactics - Mathematical Battle Arena

BASIC GAMEPLAY:
• Buy units from the shop and place them on your bench
• Use equations to buff your units or debuff enemies
• Start the round to watch automatic combat
• Survive to earn coins and build a stronger army

CONTROLS:
• Drag units from bench to blue hexagons
• Click equation cards, then click on units to apply them
• Use Start/Rest buttons to control rounds

UNIT TYPES:
• Square: High HP, low damage (Tank)
• Circle: Balanced stats (All-rounder)  
• Triangle: High damage, low HP (Assassin)
• Cross: Healer (Support)

EQUATIONS:
• Apply mathematical operations to unit stats
• Use strategically to counter enemy compositions

TIP: Combine unit types and equations for powerful synergies!
"""
	how_to_play_dialog.size = Vector2(500, 400)
	add_child(how_to_play_dialog)

func _on_start_button_pressed() -> void:
	
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.tween_callback(_load_main_scene)

func _load_main_scene() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_how_to_play_pressed() -> void:
	how_to_play_dialog.popup_centered()

func _on_quit_button_pressed() -> void:
	
	var quit_dialog = AcceptDialog.new()
	quit_dialog.title = "Quit Game"
	quit_dialog.dialog_text = "Are you sure you want to quit?"
	quit_dialog.confirmed.connect(_quit_game)
	add_child(quit_dialog)
	quit_dialog.popup_centered()

func _quit_game() -> void:
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  
		if how_to_play_dialog.visible:
			how_to_play_dialog.hide()
		else:
			
			_on_quit_button_pressed()
