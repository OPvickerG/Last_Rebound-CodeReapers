extends CanvasLayer
## LAST REBOUND: HUD. An altitude rail, story lines, the title card, letterbox and lightning flash.

const FONT_SC := preload("res://assets/fonts/IMFellEnglishSC-Regular.ttf")
const FONT := preload("res://assets/fonts/IMFellEnglish-Regular.ttf")
const FONT_IT := preload("res://assets/fonts/IMFellEnglish-Italic.ttf")
const BONE := Color(0.93, 0.89, 0.8)
const EMBER := Color(1.0, 0.55, 0.2)
const ASH := Color(0.6, 0.58, 0.55)

signal difficulty_chosen(level: int)
signal ember_changed(ember_name: String)

var _root: Control
var _vignette: TextureRect
var _flash: ColorRect
var _dim: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _time: Label
var _story: Label
var _title: Label
var _subtitle: Label
var _hint: Label
var _results: Label
var _rail: Rail
var _story_tween: Tween
var _difficulty_name := ""
var _menu: Control
var _menu_tagline: Label
var _menu_best: Label
var _menu_bests := {}
var _profile := {}
var _ember_button: Button
var _popups := 0
var _touch := false
const TOUCH_HINT := "Left thumb  steer    ·    Right thumb  look    ·    Slam  button"


class Rail extends Control:
	var platforms: Array = []
	var player: Node3D
	var best := 0.0
	var max_h := 82.0
	var min_h := 0.0
	var font: Font
	var abyss: Node3D

	func _process(_d: float) -> void:
		queue_redraw()

	func _y(h: float) -> float:
		return lerpf(size.y - 10.0, 10.0, clampf((h - min_h) / (max_h - min_h), 0.0, 1.0))

	func _draw() -> void:
		if player == null:
			return
		var x := size.x - 18.0
		draw_line(Vector2(x, _y(min_h)), Vector2(x, _y(max_h)), Color(0.93, 0.89, 0.8, 0.22), 1.0)
		for p in platforms:
			if not is_instance_valid(p) or p.collapsed or not p.visible:
				continue
			var ty: float = p.get_top_y()
			if ty < min_h or ty > max_h:
				continue
			var y := _y(ty)
			var w: float = clampf(p.diameter * 1.6, 4.0, 14.0)
			match p.kind:
				1:  # checkpoint
					if p.activated:
						draw_circle(Vector2(x, y), 4.0, Color(1.0, 0.55, 0.2))
					else:
						draw_arc(Vector2(x, y), 4.0, 0, TAU, 16, Color(0.93, 0.89, 0.8, 0.5), 1.0)
				3:  # summit
					draw_arc(Vector2(x, y - 6), 6.0, PI, TAU, 12, Color(1.0, 0.8, 0.45, 0.9), 1.5)
					draw_line(Vector2(x - 6, y - 6), Vector2(x + 6, y - 6), Color(1.0, 0.8, 0.45, 0.9), 1.5)
				_:
					var c := Color(1.0, 0.3, 0.1, 0.9) if p.cracked else Color(0.75, 0.55, 0.3, 0.75)
					draw_line(Vector2(x - w * 0.5, y), Vector2(x + w * 0.5, y), c, 2.0)
		if abyss and abyss.visible and abyss.height > min_h - 1.0:
			var ay := _y(abyss.height)
			draw_rect(Rect2(Vector2(x - 12, ay), Vector2(24, _y(min_h) - ay + 1)), Color(1.0, 0.25, 0.08, 0.18))
			draw_line(Vector2(x - 14, ay), Vector2(x + 14, ay), Color(1.0, 0.35, 0.1, 0.95), 2.0)
		if best > 1.0:
			draw_line(Vector2(x - 10, _y(best)), Vector2(x + 10, _y(best)), Color(0.93, 0.89, 0.8, 0.35), 1.0)
		var ph := player.global_position.y
		var py := _y(ph)
		for i in 4:
			draw_circle(Vector2(x, py), 9.0 - i * 2.0, Color(1.0, 0.5, 0.15, 0.12 + i * 0.2))
		draw_circle(Vector2(x, py), 2.5, Color(1, 0.92, 0.7))
		if font:
			draw_string(font, Vector2(x - 74, py + 7), "%d m" % maxi(int(ph), 0), HORIZONTAL_ALIGNMENT_RIGHT, 56, 20, Color(0.93, 0.89, 0.8, 0.85))


func _ready() -> void:
	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Vignette
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.add_point(0.55, Color(0, 0, 0, 0.0))
	g.set_color(g.get_point_count() - 1, Color(0, 0, 0, 0.78))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 256
	gt.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = gt
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.anchor_right = 1.0
	_vignette.anchor_bottom = 1.0
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vignette)

	_rail = Rail.new()
	_rail.font = FONT
	_rail.anchor_left = 1.0
	_rail.anchor_right = 1.0
	_rail.anchor_top = 0.14
	_rail.anchor_bottom = 0.86
	_rail.offset_left = -130
	_rail.offset_right = -24
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rail)

	_time = _label(FONT_SC, 26, BONE, HORIZONTAL_ALIGNMENT_LEFT)
	_time.position = Vector2(36, 26)
	_time.size = Vector2(600, 40)

	_story = _label(FONT_IT, 40, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_story, 1.0, -240, -160)
	_story.modulate.a = 0.0

	_title = _label(FONT_SC, 132, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_title.text = "Last Rebound"
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(_title, 0.5, -160, 40)
	_title.modulate.a = 0.0
	_subtitle = _label(FONT_IT, 36, EMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.text = "Rise.  Ring the bell."
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(_subtitle, 0.5, 40, 100)
	_subtitle.modulate.a = 0.0

	_hint = _label(FONT, 22, Color(BONE, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_hint.text = "WASD  steer    ·    Mouse  look    ·    Space  slam    ·    R  restart    ·    M  menu"
	_place(_hint, 1.0, -64, -26)
	_hint.modulate.a = 0.0

	_results = _label(FONT_SC, 34, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_results.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_place(_results, 0.5, 120, 400)
	_results.modulate.a = 0.0

	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.03, 0.02, 0.0)
	_dim.anchor_right = 1.0
	_dim.anchor_bottom = 1.0
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	_root.move_child(_dim, 1)

	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.anchor_right = 1.0
	_bar_top.offset_bottom = 0
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color.BLACK
	_bar_bottom.anchor_top = 1.0
	_bar_bottom.anchor_right = 1.0
	_bar_bottom.anchor_bottom = 1.0
	_bar_bottom.offset_top = 0
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_bottom)
	# Letterbox bars sit under the text but over the world.
	_root.move_child(_bar_top, 2)
	_root.move_child(_bar_bottom, 3)

	_flash = ColorRect.new()
	_flash.color = Color(0.85, 0.9, 1.0, 0.0)
	_flash.anchor_right = 1.0
	_flash.anchor_bottom = 1.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)


## Full-width row anchored at `anchor_y` (0 = top, 1 = bottom), from offset `top` to `bottom` px.
func _place(c: Control, anchor_y: float, top: float, bottom: float) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = anchor_y
	c.anchor_bottom = anchor_y
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.offset_top = top
	c.offset_bottom = bottom


func _label(font: Font, size: int, color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = color
	ls.shadow_color = Color(0, 0, 0, 0.75)
	ls.shadow_size = 10
	ls.shadow_offset = Vector2(0, 3)
	l.label_settings = ls
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


# ----------------------------------------------------------------- API
func setup(platforms: Array, player: Node3D) -> void:
	_rail.platforms = platforms
	_rail.player = player


func update_stats(elapsed: float, falls: int, best: float) -> void:
	_rail.best = best
	_time.text = "%s     %s     %s" % [_difficulty_name, format_time(elapsed), ("%d falls" % falls) if falls != 1 else "1 fall"]


func set_touch_mode(on: bool) -> void:
	_touch = on
	if on:
		_hint.text = TOUCH_HINT


func set_difficulty(difficulty_name: String) -> void:
	_difficulty_name = difficulty_name


## Endless HUD: height, run XP, combo; the rail scrolls with you.
func update_endless(y: float, highest: float, xp: int, combo: int, abyss_h: float) -> void:
	_rail.best = highest
	_rail.min_h = maxf(-5.0, y - 40.0)
	_rail.max_h = _rail.min_h + 80.0
	_time.text = "%s     %d m     %d XP     x%d" % [_difficulty_name, maxi(int(y), 0), xp, combo]


## Floating reward text under the stats line.
func popup(text: String, color: Color) -> void:
	var l := _label(FONT_SC, 30, color, HORIZONTAL_ALIGNMENT_LEFT)
	l.position = Vector2(40, 84 + (_popups % 3) * 34)
	l.size = Vector2(500, 40)
	_popups += 1
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 30.0, 1.4)
	tw.tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)


func show_endless_results(s: Dictionary) -> void:
	_title.text = "The Abyss Took You"
	_title.label_settings.font_size = 96
	_subtitle.text = "%d m  ·  %d gongs  ·  best combo x%d" % [int(s["height"]), s["gongs"], s["best_combo"]]
	_subtitle.label_settings.font_color = BONE
	create_tween().tween_property(_dim, "color:a", 0.5, 1.5)
	show_title()
	var lines := "+%d XP" % s["xp"]
	var la: int = s["level_after"]
	if la > s["level_before"]:
		lines += "\nLevel up!  %d  ->  %d   ·   %s" % [s["level_before"], la, Difficulty.rank_for_level(la)]
	else:
		lines += "\nLevel %d   ·   %s   ·   %d XP to next level" % [la, Difficulty.rank_for_level(la), Difficulty.xp_for_level(la + 1) - int(s["total_xp"])]
	lines += "\nNew best height!" if s["new_best"] else "\nBest  %d m" % int(s["best_height"])
	for u in s["unlocked"]:
		lines += "\nNew ember unlocked:  %s" % u
	lines += "\n\nTap  Restart  or  Menu" if _touch else "\n\nR  climb again      M  menu"
	_results.text = lines
	create_tween().tween_property(_results, "modulate:a", 1.0, 1.2).set_delay(1.0)


func set_abyss(node: Node3D) -> void:
	_rail.abyss = node


# ----------------------------------------------------------------- difficulty menu
func show_menu(bests: Dictionary, profile: Dictionary = {}) -> void:
	_menu_bests = bests
	_profile = profile
	_title.text = "Last Rebound"
	_title.modulate.a = 1.0
	_left_column(_title, -300, -160)
	_title.label_settings.font_size = 104
	_subtitle.text = "Choose your storm"
	_subtitle.label_settings.font_color = BONE
	_left_column(_subtitle, -160, -110)
	_subtitle.modulate.a = 0.85

	_menu = VBoxContainer.new()
	_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu.add_theme_constant_override("separation", 2)
	_menu.alignment = BoxContainer.ALIGNMENT_BEGIN
	_left_column(_menu, -100, 230)
	_root.add_child(_menu)
	var first: Button
	for lv in Difficulty.ORDER:
		var p: Dictionary = Difficulty.get_preset(lv)
		var b := Button.new()
		b.text = p["name"]
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_override("font", FONT_SC)
		b.add_theme_font_size_override("font_size", 42)
		b.add_theme_color_override("font_color", Color(BONE, 0.45))
		b.add_theme_color_override("font_hover_color", EMBER)
		b.add_theme_color_override("font_focus_color", EMBER)
		b.add_theme_color_override("font_pressed_color", Color(1, 0.85, 0.6))
		b.add_theme_color_override("font_hover_pressed_color", Color(1, 0.85, 0.6))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.focus_entered.connect(_menu_focus.bind(lv))
		b.mouse_entered.connect(b.grab_focus)
		b.pressed.connect(_menu_pick.bind(lv))
		_menu.add_child(b)
		if lv == Difficulty.Level.NORMAL:
			first = b
		if lv == Difficulty.Level.HARD:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 14)
			_menu.add_child(gap)

	# Ember colour picker (colours unlock with Endless levels).
	_ember_button = Button.new()
	_ember_button.flat = true
	_ember_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ember_button.add_theme_font_override("font", FONT_IT)
	_ember_button.add_theme_font_size_override("font_size", 28)
	_ember_button.add_theme_color_override("font_color", Color(BONE, 0.5))
	_ember_button.add_theme_color_override("font_hover_color", EMBER)
	_ember_button.add_theme_color_override("font_focus_color", EMBER)
	_ember_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_ember_button.text = "Ember:  %s" % _profile.get("ember", "Classic")
	_ember_button.focus_entered.connect(_ember_focus)
	_ember_button.mouse_entered.connect(_ember_button.grab_focus)
	_ember_button.pressed.connect(_ember_cycle)
	_menu.add_child(_ember_button)

	_menu_tagline = _label(FONT_IT, 30, Color(0.95, 0.75, 0.5), HORIZONTAL_ALIGNMENT_LEFT)
	_left_column(_menu_tagline, 240, 282)
	_menu_best = _label(FONT, 22, Color(BONE, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	_left_column(_menu_best, 284, 316)
	_hint.text = "Tap a storm to begin" if _touch else "Up / Down  choose    ·    Enter or click  begin"
	_hint.modulate.a = 0.8
	first.grab_focus.call_deferred()


func _menu_focus(lv: int) -> void:
	var p: Dictionary = Difficulty.get_preset(lv)
	_menu_tagline.text = p["tagline"]
	if lv == Difficulty.Level.ENDLESS:
		var xp: int = _profile.get("xp", 0)
		var plv := Difficulty.level_for_xp(xp)
		var into := xp - Difficulty.xp_for_level(plv)
		var need := Difficulty.xp_for_level(plv + 1) - Difficulty.xp_for_level(plv)
		_menu_best.text = "Level %d  ·  %s  ·  %d / %d XP  ·  Best %d m" % [plv, Difficulty.rank_for_level(plv), into, need, int(_profile.get("best_height", 0.0))]
		return
	var best: float = _menu_bests.get(lv, INF)
	_menu_best.text = ("Best  " + format_time(best)) if best < INF else "Not yet climbed"


func _ember_focus() -> void:
	var plv := Difficulty.level_for_xp(_profile.get("xp", 0))
	var names := []
	for e in Difficulty.unlocked_embers(plv):
		names.append(e[1])
	_menu_tagline.text = "Level up in Last Rebound to unlock new embers."
	_menu_best.text = "Unlocked:  " + ",  ".join(names)


func _ember_cycle() -> void:
	var plv := Difficulty.level_for_xp(_profile.get("xp", 0))
	var list := Difficulty.unlocked_embers(plv)
	var current: String = _profile.get("ember", "Classic")
	var idx := 0
	for i in list.size():
		if list[i][1] == current:
			idx = i
	var next: String = list[(idx + 1) % list.size()][1]
	_profile["ember"] = next
	_ember_button.text = "Ember:  %s" % next
	ember_changed.emit(next)


func _menu_pick(lv: int) -> void:
	difficulty_chosen.emit(lv)
	_menu.queue_free()
	_menu_tagline.queue_free()
	_menu_best.queue_free()
	_hint.modulate.a = 0.0
	_hint.text = TOUCH_HINT if _touch else "WASD  steer    ·    Mouse  look    ·    Space  slam    ·    R  restart    ·    M  menu"
	var tw0 := create_tween().set_parallel(true)
	tw0.tween_property(_title, "modulate:a", 0.0, 0.6)
	tw0.tween_property(_subtitle, "modulate:a", 0.0, 0.6)
	await tw0.finished
	_place(_title, 0.5, -160, 40)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.label_settings.font_size = 132
	_place(_subtitle, 0.5, 40, 100)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.text = "Rise.  Ring the bell."
	_subtitle.label_settings.font_color = EMBER


## Left-hand column (menu layout), offsets relative to the vertical centre.
func _left_column(c: Control, top: float, bottom: float) -> void:
	c.anchor_left = 0.07
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.offset_top = top
	c.offset_bottom = bottom
	if c is Label:
		(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func show_story(text: String, seconds: float = 3.5) -> void:
	if _story_tween:
		_story_tween.kill()
	_story.text = text
	_story_tween = create_tween()
	_story_tween.tween_property(_story, "modulate:a", 1.0, 0.6)
	_story_tween.tween_interval(seconds)
	_story_tween.tween_property(_story, "modulate:a", 0.0, 1.0)


func show_title() -> void:
	_title.scale = Vector2.ONE
	_title.pivot_offset = _title.size * 0.5
	var tw := create_tween().set_parallel(true)
	_title.modulate.a = 1.0
	_title.scale = Vector2(1.18, 1.18)
	tw.tween_property(_title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_subtitle, "modulate:a", 1.0, 1.2).set_delay(0.9)


func hide_title() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_title, "modulate:a", 0.0, 1.2)
	tw.tween_property(_subtitle, "modulate:a", 0.0, 1.0)


func show_hint(seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(_hint, "modulate:a", 1.0, 0.8)
	tw.tween_interval(seconds)
	tw.tween_property(_hint, "modulate:a", 0.0, 1.5)


func set_letterbox(on: bool, seconds: float = 1.0) -> void:
	var h := get_viewport().get_visible_rect().size.y * 0.11 if on else 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_bar_top, "offset_bottom", h, seconds)
	tw.tween_property(_bar_bottom, "offset_top", -h, seconds)
	tw.tween_property(_rail, "modulate:a", 0.0 if on else 1.0, seconds)
	tw.tween_property(_time, "modulate:a", 0.0 if on else 1.0, seconds)


func flash(strength: float) -> void:
	_flash.color.a = maxf(_flash.color.a, strength)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.45)


func show_results(elapsed: float, falls: int, best_time: float, record: bool, difficulty_name: String = "") -> void:
	_title.text = "The Bell Has Rung"
	_title.label_settings.font_size = 96
	_subtitle.text = "The storm is over.  You rose."
	_subtitle.label_settings.font_color = BONE
	create_tween().tween_property(_dim, "color:a", 0.45, 2.0)
	show_title()
	var lines := "%s   ·   %s   ·   %d %s" % [difficulty_name, format_time(elapsed), falls, "fall" if falls == 1 else "falls"]
	lines += "\nNew best time" if record else "\nBest  %s" % format_time(best_time)
	lines += "\n\nTap  Restart  or  Menu" if _touch else "\n\nR  climb again      M  change difficulty"
	_results.text = lines
	create_tween().tween_property(_results, "modulate:a", 1.0, 1.5).set_delay(1.5)


static func format_time(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
