extends CanvasLayer
## LAST REBOUND: touch controls for phones and tablets.
##
## Left half of the screen: a floating joystick appears under your thumb and steers the ember.
## Right half: drag to orbit the camera.
## SLAM button: bottom right. Restart / Menu: top left, under the timer.

signal slam_pressed
signal restart_pressed
signal menu_pressed

const BONE := Color(0.93, 0.89, 0.8)
const EMBER := Color(1.0, 0.55, 0.2)
const FONT_SC := preload("res://assets/fonts/IMFellEnglishSC-Regular.ttf")

@export var stick_radius: float = 120.0
@export var look_sensitivity: float = 0.0055

## Steering output, like Input.get_vector(): x = right, y = back (up on screen is negative).
var move_vector := Vector2.ZERO
var camera_rig: Node3D

var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_index := -1
var _slam_index := -1
var _canvas: Control


class Overlay extends Control:
	var owner_ref

	func _draw() -> void:
		owner_ref._draw_overlay(self)

	func _process(_d: float) -> void:
		queue_redraw()


func _ready() -> void:
	layer = 5
	_canvas = Overlay.new()
	_canvas.owner_ref = self
	_canvas.anchor_right = 1.0
	_canvas.anchor_bottom = 1.0
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)


func _vp_size() -> Vector2:
	return _canvas.get_viewport_rect().size


func _slam_center() -> Vector2:
	var s := _vp_size()
	return Vector2(s.x - 270.0, s.y - 160.0)


func _slam_radius() -> float:
	return 78.0


func _button_rects() -> Array:
	# [restart, menu]: top left, under the timer.
	return [Rect2(28, 78, 150, 58), Rect2(190, 78, 130, 58)]


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_touch(event)
	elif event is InputEventScreenDrag:
		_drag(event)


func _touch(e: InputEventScreenTouch) -> void:
	var s := _vp_size()
	if e.pressed:
		var rects := _button_rects()
		if rects[0].has_point(e.position):
			restart_pressed.emit()
			get_viewport().set_input_as_handled()
			return
		if rects[1].has_point(e.position):
			menu_pressed.emit()
			get_viewport().set_input_as_handled()
			return
		if e.position.distance_to(_slam_center()) < _slam_radius() * 1.25:
			_slam_index = e.index
			slam_pressed.emit()
		elif e.position.x < s.x * 0.45 and _stick_index == -1:
			_stick_index = e.index
			_stick_origin = e.position
			_stick_pos = e.position
			move_vector = Vector2.ZERO
		elif _look_index == -1:
			_look_index = e.index
		get_viewport().set_input_as_handled()
	else:
		if e.index == _stick_index:
			_stick_index = -1
			move_vector = Vector2.ZERO
		if e.index == _look_index:
			_look_index = -1
		if e.index == _slam_index:
			_slam_index = -1


func _drag(e: InputEventScreenDrag) -> void:
	if e.index == _stick_index:
		var d := e.position - _stick_origin
		if d.length() > stick_radius:
			# The base follows the thumb if you push past the edge.
			_stick_origin = e.position - d.normalized() * stick_radius
			d = e.position - _stick_origin
		_stick_pos = e.position
		var v := d / stick_radius
		move_vector = v if v.length() > 0.12 else Vector2.ZERO
		get_viewport().set_input_as_handled()
	elif e.index == _look_index and camera_rig:
		camera_rig.look_delta(e.relative * look_sensitivity)
		get_viewport().set_input_as_handled()


func release_all() -> void:
	_stick_index = -1
	_look_index = -1
	_slam_index = -1
	move_vector = Vector2.ZERO


func _draw_overlay(c: Control) -> void:
	var s := _vp_size()
	# Joystick: a hint ring when idle, a live stick while held.
	if _stick_index >= 0:
		c.draw_circle(_stick_origin, stick_radius, Color(0, 0, 0, 0.22))
		c.draw_arc(_stick_origin, stick_radius, 0, TAU, 64, Color(BONE, 0.35), 2.0, true)
		c.draw_circle(_stick_pos, 46.0, Color(EMBER, 0.55))
		c.draw_arc(_stick_pos, 46.0, 0, TAU, 40, Color(1, 0.85, 0.6, 0.8), 2.0, true)
	else:
		var home := Vector2(230.0, s.y - 210.0)
		c.draw_arc(home, stick_radius * 0.8, 0, TAU, 64, Color(BONE, 0.16), 2.0, true)
		c.draw_circle(home, 34.0, Color(BONE, 0.12))
		c.draw_string(FONT_SC, home + Vector2(-60, stick_radius * 0.8 + 34), "steer", HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(BONE, 0.35))

	# Slam button
	var sc := _slam_center()
	var held := _slam_index >= 0
	c.draw_circle(sc, _slam_radius(), Color(EMBER, 0.45 if held else 0.18))
	c.draw_arc(sc, _slam_radius(), 0, TAU, 64, Color(EMBER, 0.9 if held else 0.55), 3.0, true)
	c.draw_string(FONT_SC, sc + Vector2(-70, 10), "Slam", HORIZONTAL_ALIGNMENT_CENTER, 140, 32, Color(BONE, 0.85))

	# Restart / Menu
	var labels := ["Restart", "Menu"]
	var rects := _button_rects()
	for i in 2:
		var r: Rect2 = rects[i]
		c.draw_rect(r, Color(0, 0, 0, 0.3))
		c.draw_rect(r, Color(BONE, 0.35), false, 1.5)
		c.draw_string(FONT_SC, r.position + Vector2(0, 39), labels[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, Color(BONE, 0.85))
