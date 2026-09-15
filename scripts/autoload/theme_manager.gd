extends Node

signal theme_changed

const THEME_NAMES: Array[String] = ["light", "soft", "dark"]
const DEFAULT_THEME := "dark"

const PALETTES: Dictionary = {
	"dark": {
		"window": Color(0.09, 0.095, 0.12),
		"panel": Color(0.12, 0.13, 0.16),
		"sunken": Color(0.07, 0.075, 0.09),
		"dialog": Color(0.16, 0.17, 0.22),
		"input": Color(0.10, 0.11, 0.14),
		"surface": Color(0.18, 0.19, 0.24),
		"border": Color(0.24, 0.26, 0.32),
		"text": Color(0.88, 0.90, 0.94),
		"muted": Color(0.64, 0.68, 0.74),
		"disabled": Color(0.42, 0.45, 0.50),
		"accent": Color(0.25, 0.55, 1.0),
		"accent_text": Color(1, 1, 1),
		"hover": Color(0.185, 0.205, 0.265),
		"pressed": Color(0.25, 0.28, 0.35),
		"selected": Color(0.22, 0.28, 0.42),
		"danger": Color(1, 0.45, 0.45),
		"warning": Color(1, 0.8, 0.35),
		"success": Color(0.5, 0.9, 0.6),
		"bubble_user": Color(0.28, 0.42, 0.6),
		"bubble_agent": Color(0.2, 0.21, 0.27),
		"bubble_system": Color(0.3, 0.28, 0.22),
		"read": Color(1, 1, 1),
		"deleted": Color(0.9, 0.3, 0.3),
		"created": Color(0.4, 0.55, 0.95),
		"modified": Color(1.0, 0.8, 0.2),
	},
	"soft": {
		"window": Color(0.30, 0.32, 0.36),
		"panel": Color(0.37, 0.39, 0.44),
		"sunken": Color(0.28, 0.30, 0.34),
		"dialog": Color(0.42, 0.44, 0.49),
		"input": Color(0.31, 0.33, 0.37),
		"surface": Color(0.46, 0.48, 0.54),
		"border": Color(0.52, 0.55, 0.60),
		"text": Color(0.96, 0.97, 0.99),
		"muted": Color(0.78, 0.80, 0.84),
		"disabled": Color(0.62, 0.64, 0.68),
		"accent": Color(0.42, 0.62, 0.95),
		"accent_text": Color(1, 1, 1),
		"hover": Color(0.44, 0.47, 0.53),
		"pressed": Color(0.50, 0.53, 0.60),
		"selected": Color(0.42, 0.50, 0.65),
		"danger": Color(1, 0.55, 0.5),
		"warning": Color(1, 0.82, 0.45),
		"success": Color(0.6, 0.92, 0.7),
		"bubble_user": Color(0.36, 0.50, 0.68),
		"bubble_agent": Color(0.44, 0.46, 0.52),
		"bubble_system": Color(0.5, 0.46, 0.36),
		"read": Color(0.95, 0.96, 0.98),
		"deleted": Color(1, 0.4, 0.4),
		"created": Color(0.6, 0.75, 1.0),
		"modified": Color(1, 0.85, 0.4),
	},
	"light": {
		"window": Color(0.84, 0.86, 0.89),
		"panel": Color(0.96, 0.97, 0.98),
		"sunken": Color(0.89, 0.90, 0.93),
		"dialog": Color(0.99, 0.99, 1.0),
		"input": Color(1, 1, 1),
		"surface": Color(0.90, 0.91, 0.94),
		"border": Color(0.74, 0.76, 0.80),
		"text": Color(0.12, 0.13, 0.16),
		"muted": Color(0.42, 0.45, 0.50),
		"disabled": Color(0.62, 0.65, 0.70),
		"accent": Color(0.16, 0.42, 0.82),
		"accent_text": Color(1, 1, 1),
		"hover": Color(0.90, 0.92, 0.95),
		"pressed": Color(0.82, 0.85, 0.90),
		"selected": Color(0.72, 0.80, 0.94),
		"danger": Color(0.78, 0.12, 0.12),
		"warning": Color(0.62, 0.45, 0.0),
		"success": Color(0.10, 0.5, 0.20),
		"bubble_user": Color(0.70, 0.82, 0.96),
		"bubble_agent": Color(0.90, 0.91, 0.94),
		"bubble_system": Color(0.95, 0.91, 0.80),
		"read": Color(0.25, 0.27, 0.32),
		"deleted": Color(0.78, 0.12, 0.12),
		"created": Color(0.10, 0.32, 0.75),
		"modified": Color(0.62, 0.45, 0.0),
	},
}

var current_theme: String = DEFAULT_THEME


func _ready() -> void:
	apply_theme(DEFAULT_THEME)


func is_valid_theme(name: String) -> bool:
	return name in THEME_NAMES


func palette(name: String = "") -> Dictionary:
	var key := name if not name.is_empty() else current_theme
	return PALETTES.get(key, PALETTES[DEFAULT_THEME])


func color(key: String) -> Color:
	return palette().get(key, Color.WHITE)


func apply_theme(name: String) -> void:
	if not is_valid_theme(name):
		name = DEFAULT_THEME
	current_theme = name
	if is_inside_tree():
		get_tree().root.theme = build_theme(palette(name))
	theme_changed.emit()


func build_theme(p: Dictionary) -> Theme:
	var theme := Theme.new()
	theme.set_type_variation("DialogPanel", "PanelContainer")
	theme.set_type_variation("SunkenPanel", "PanelContainer")
	theme.set_type_variation("MutedLabel", "Label")

	theme.set_stylebox("panel", "PanelContainer", _flat(p["panel"], 8, p["border"], 1, 10.0, 10.0))
	theme.set_stylebox("panel", "Panel", _flat(p["panel"], 8, p["border"], 1, 10.0, 10.0))
	theme.set_stylebox("panel", "DialogPanel", _flat(p["dialog"], 10, p["border"], 1, 16.0, 16.0))
	theme.set_stylebox("panel", "SunkenPanel", _flat(p["sunken"], 6, p["border"], 1, 6.0, 6.0))
	theme.set_stylebox("panel", "PopupPanel", _flat(p["dialog"], 8, p["border"], 1, 4.0, 4.0))

	theme.set_color("font_color", "Label", p["text"])
	theme.set_color("font_color", "MutedLabel", p["muted"])
	theme.set_color("default_color", "RichTextLabel", p["text"])
	theme.set_color("font_color", "RichTextLabel", p["text"])
	theme.set_color("selection_color", "RichTextLabel", p["selected"])

	_build_buttons(theme, p)
	_build_inputs(theme, p)
	_build_popups(theme, p)
	_build_tabs(theme, p)
	_build_lists(theme, p)

	theme.set_stylebox("background", "ProgressBar", _flat(p["sunken"], 4, p["border"], 0, 0.0, 0.0))
	theme.set_stylebox("fill", "ProgressBar", _flat(p["accent"], 4, p["border"], 0, 0.0, 0.0))
	theme.set_color("font_color", "ProgressBar", p["text"])

	theme.set_stylebox("separator", "HSeparator", _line(p["border"]))
	theme.set_stylebox("separator", "VSeparator", _line(p["border"]))

	for dialog_type in ["AcceptDialog", "ConfirmationDialog", "FileDialog"]:
		theme.set_stylebox("panel", dialog_type, _flat(p["dialog"], 10, p["border"], 1, 16.0, 16.0))
		theme.set_color("font_color", dialog_type, p["text"])

	theme.set_color("title_color", "Window", p["text"])
	theme.set_stylebox("embedded_border", "Window", _flat(p["dialog"], 0, p["border"], 1, 0.0, 0.0))
	theme.set_stylebox("panel", "TooltipPanel", _flat(p["dialog"], 4, p["border"], 1, 6.0, 4.0))
	theme.set_color("font_color", "TooltipLabel", p["text"])
	return theme


func _build_buttons(theme: Theme, p: Dictionary) -> void:
	for type_name in ["Button", "OptionButton", "CheckBox", "CheckButton", "MenuButton"]:
		theme.set_stylebox("normal", type_name, _flat(p["surface"], 6, p["border"], 1, 10.0, 5.0))
		theme.set_stylebox("hover", type_name, _flat(p["hover"], 6, p["border"], 1, 10.0, 5.0))
		theme.set_stylebox("pressed", type_name, _flat(p["pressed"], 6, p["border"], 1, 10.0, 5.0))
		theme.set_stylebox("disabled", type_name, _flat(p["surface"].darkened(0.12), 6, p["border"], 1, 10.0, 5.0))
		theme.set_stylebox("focus", type_name, _flat(Color(0, 0, 0, 0), 6, p["accent"], 2, 10.0, 5.0))
		theme.set_color("font_color", type_name, p["text"])
		theme.set_color("font_hover_color", type_name, p["text"])
		theme.set_color("font_pressed_color", type_name, p["accent_text"])
		theme.set_color("font_focus_color", type_name, p["text"])
		theme.set_color("font_disabled_color", type_name, p["disabled"])


func _build_inputs(theme: Theme, p: Dictionary) -> void:
	for type_name in ["LineEdit", "TextEdit", "CodeEdit"]:
		theme.set_stylebox("normal", type_name, _flat(p["input"], 6, p["border"], 1, 8.0, 4.0))
		theme.set_stylebox("focus", type_name, _flat(p["input"], 6, p["accent"], 1, 8.0, 4.0))
		theme.set_stylebox("read_only", type_name, _flat(p["sunken"], 6, p["border"], 1, 8.0, 4.0))
		theme.set_color("font_color", type_name, p["text"])
		theme.set_color("font_placeholder_color", type_name, p["muted"])
		theme.set_color("font_selected_color", type_name, p["accent_text"])
		theme.set_color("font_readonly_color", type_name, p["muted"])
		theme.set_color("caret_color", type_name, p["text"])
		theme.set_color("selection_color", type_name, p["selected"])


func _build_popups(theme: Theme, p: Dictionary) -> void:
	theme.set_stylebox("panel", "PopupMenu", _flat(p["dialog"], 6, p["border"], 1, 0.0, 0.0))
	theme.set_stylebox("hover", "PopupMenu", _flat(p["hover"], 4, p["border"], 0, 0.0, 0.0))
	theme.set_stylebox("separator", "PopupMenu", _line(p["border"]))
	theme.set_color("font_color", "PopupMenu", p["text"])
	theme.set_color("font_hover_color", "PopupMenu", p["text"])
	theme.set_color("font_disabled_color", "PopupMenu", p["disabled"])
	theme.set_color("font_separator_color", "PopupMenu", p["muted"])


func _build_tabs(theme: Theme, p: Dictionary) -> void:
	theme.set_stylebox("panel", "TabContainer", _flat(p["panel"], 8, p["border"], 1, 0.0, 0.0))
	theme.set_stylebox("tabbar_background", "TabContainer", _flat(p["panel"], 8, p["border"], 0, 0.0, 0.0))
	theme.set_stylebox("tab_selected", "TabContainer", _flat(p["dialog"], 6, p["border"], 1, 10.0, 4.0))
	theme.set_stylebox("tab_unselected", "TabContainer", _flat(p["sunken"], 6, p["border"], 1, 10.0, 4.0))
	theme.set_stylebox("tab_hovered", "TabContainer", _flat(p["hover"], 6, p["border"], 1, 10.0, 4.0))
	theme.set_color("font_selected_color", "TabContainer", p["text"])
	theme.set_color("font_unselected_color", "TabContainer", p["muted"])
	theme.set_color("font_hovered_color", "TabContainer", p["text"])
	theme.set_color("font_disabled_color", "TabContainer", p["disabled"])


func _build_lists(theme: Theme, p: Dictionary) -> void:
	for type_name in ["Tree", "ItemList"]:
		theme.set_stylebox("panel", type_name, _flat(p["sunken"], 6, p["border"], 1, 4.0, 4.0))
		theme.set_stylebox("selected", type_name, _flat(p["selected"], 4, p["border"], 0, 0.0, 0.0))
		theme.set_stylebox("selected_focus", type_name, _flat(p["selected"], 4, p["border"], 0, 0.0, 0.0))
		theme.set_color("font_color", type_name, p["text"])
		theme.set_color("font_selected_color", type_name, p["text"])
		theme.set_color("guide_color", type_name, p["border"])


func _flat(bg: Color, radius: int, border_color: Color, border_width: int, pad_h: float, pad_v: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_width > 0:
		sb.set_border_width_all(border_width)
		sb.border_color = border_color
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


func _line(border_color: Color) -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = border_color
	sb.thickness = 1
	return sb
