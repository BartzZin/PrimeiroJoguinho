extends Control
signal chosen(effect_id: String)
signal cancelled
var panel: PanelContainer
var option_ids: Array = []

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("142137")
	style.border_color = Color("c8a965")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

func present(effects: Array, point: Vector2):
	var box = VBoxContainer.new()
	panel.add_child(box)
	for effect in effects:
		option_ids.append(effect.id)
		var option = Button.new()
		option.name = "Choose_" + effect.id
		option.text = "Remover " + ("escudo" if effect.kind == "shield" else "congelamento")
		option.custom_minimum_size = Vector2(240, 44)
		option.pressed.connect(func(): chosen.emit(effect.id))
		box.add_child(option)
	panel.reset_size()
	panel.position = Vector2(clampf(point.x, 12, maxf(12, size.x - panel.size.x - 12)), clampf(point.y, 12, maxf(12, size.y - panel.size.y - 12)))
	box.get_child(0).grab_focus()

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		cancelled.emit()
		accept_event()

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancelled.emit()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancelled.emit()
		get_viewport().set_input_as_handled()
