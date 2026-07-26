class_name SettingsMenu
extends CanvasLayer

@export var debug_hud: Control

@onready var overlay: Control = $Overlay
@onready var hud_checkbox: CheckBox = $Overlay/CenterContainer/MenuPanel/VBox/OptionsContainer/DebugHUDCheckBox

var is_menu_open: bool = false

func _ready() -> void:
	overlay.visible = false
	if not debug_hud:
		debug_hud = get_node_or_null("/root/TestWorld/DebugHUD") as Control
		if not debug_hud and is_inside_tree():
			debug_hud = get_tree().root.find_child("DebugHUD", true, false) as Control
	
	if hud_checkbox and not hud_checkbox.toggled.is_connected(_on_debug_hud_check_box_toggled):
		hud_checkbox.toggled.connect(_on_debug_hud_check_box_toggled)
		
	if debug_hud and hud_checkbox:
		hud_checkbox.set_pressed_no_signal(debug_hud.visible)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		# Toggle open/close on Start/Options button (Button 6)
		if event.button_index == JOY_BUTTON_START and event.pressed:
			toggle_menu()
			get_viewport().set_input_as_handled()
		# Close menu with Back/B/Circle button (Button 1) when already open
		elif event.button_index == JOY_BUTTON_B and event.pressed and is_menu_open:
			toggle_menu()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		# Keyboard fallback for opening/closing settings menu with Escape
		if event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
			toggle_menu()
			get_viewport().set_input_as_handled()

func toggle_menu() -> void:
	is_menu_open = not is_menu_open
	overlay.visible = is_menu_open
	get_tree().paused = is_menu_open
	if is_menu_open:
		if debug_hud and hud_checkbox:
			hud_checkbox.set_pressed_no_signal(debug_hud.visible)
		# Grab focus on the checkbox immediately so controller face buttons and D-pad can interact without a mouse
		hud_checkbox.grab_focus()
	else:
		if hud_checkbox:
			hud_checkbox.release_focus()

func _on_debug_hud_check_box_toggled(toggled_on: bool) -> void:
	if debug_hud:
		debug_hud.visible = toggled_on
