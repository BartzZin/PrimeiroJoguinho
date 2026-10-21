extends Control

signal setting_changed(key: String, value: Variant)
signal open_logs_requested

var anchor_button: Control
var panel: PanelContainer
var content: VBoxContainer
var logs_checkbox: CheckBox
var quality: OptionButton
var toggles = {}


func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style = StyleBoxFlat.new()
	style.bg_color = Color("111d30")
	style.border_color = Color("6a7890")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.custom_minimum_size.x = 302
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	var title = Label.new()
	title.text = "CONFIGURAÇÕES"
	title.add_theme_font_size_override("font_size", 19)
	content.add_child(title)
	logs_checkbox = add_toggle("Ativar logs detalhados", "detailed_logs")
	var help = Label.new()
	help.text = "Erros essenciais são registrados mesmo com esta opção desligada."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 14)
	content.add_child(help)
	var folder = Button.new()
	folder.text = "Abrir pasta de logs"
	folder.custom_minimum_size.y = 40
	folder.pressed.connect(func(): open_logs_requested.emit())
	content.add_child(folder)
	var quality_label = Label.new()
	quality_label.text = "Qualidade gráfica"
	content.add_child(quality_label)
	quality = OptionButton.new()
	for option in ["Baixo • sem sombras", "Médio • suavização 2×", "Alto • suavização 4×"]:
		quality.add_item(option)
	quality.custom_minimum_size.y = 40
	quality.item_selected.connect(func(index): setting_changed.emit("quality", index))
	content.add_child(quality)
	add_toggle("Animações de movimento", "animations")
	add_toggle("Visão superior", "top_view")
	add_toggle("Tela cheia (F11)", "fullscreen")
	resized.connect(reposition)
	hide()


func add_toggle(text_value: String, key: String) -> CheckBox:
	var control = CheckBox.new()
	control.text = text_value
	control.custom_minimum_size.y = 40
	control.add_theme_font_size_override("font_size", 17)
	control.toggled.connect(func(value): setting_changed.emit(key, value))
	content.add_child(control)
	toggles[key] = control
	return control


func present(values: Dictionary):
	for key in toggles:
		toggles[key].set_pressed_no_signal(values[key])
	quality.select(values.quality)


func toggle(values: Dictionary):
	if visible:
		hide()
	else:
		present(values)
		show()
		reposition.call_deferred()
		logs_checkbox.grab_focus()


func reposition():
	if panel == null or anchor_button == null:
		return
	var width = minf(350, maxf(200, size.x - 24))
	panel.size = Vector2(width, minf(content.get_combined_minimum_size().y + 28, size.y - 24))
	var anchor = anchor_button.get_global_rect()
	panel.position = Vector2(clampf(anchor.end.x - width, 12, maxf(12, size.x - width - 12)), maxf(12, anchor.position.y - panel.size.y - 8))


func _gui_input(event):
	if visible and event is InputEventMouseButton and event.pressed:
		if not panel.get_rect().has_point(event.position):
			hide()
			accept_event()


func _input(event):
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
