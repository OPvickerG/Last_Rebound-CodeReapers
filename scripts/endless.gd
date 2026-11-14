extends Node
## LAST REBOUND: the endless tower (the "Last Rebound" mode).
##
## Gongs are generated above you forever. Difficulty is a function of height (t: 0 at the
## base, 1 at 320 m and beyond): gongs shrink, gaps grow, more gongs swing or are cracked,
## gusts come more often, and the abyss climbs faster. One life: the abyss ends the run.
##
## XP: +5 per new gong, times a combo that grows while you keep climbing (up to x5) and
## resets if you slip back down. Slam landings, braziers and every 50 m add bonuses.

signal run_ended(summary: Dictionary)

const PLATFORM_SCENE := preload("res://scenes/Platform.tscn")
const MELODY := [-5, 0, 3, 7, 5, 8, 7, 10, 12, 15, 12, 10, 7, 8, 5, 3, 0, 3, 7, 12]
const T_FULL := 320.0  # height where difficulty maxes out

var gm: Node3D
var player: RigidBody3D
var spine: Node3D
var storm: Node3D
var hud: CanvasLayer
var audio: Node
var abyss: Node3D

var running := false
var run_xp := 0
var combo := 1
var best_combo := 1
var gongs_reached := 0
var slams := 0
var highest := 0.0

var _last_y := 0.0
var _last_angle := 0.0
var _dir := 1.0
var _n := 0
var _best_index := 0
var _last_cracked := false
var _milestone := 50.0
var _grace := 3.0
var _rng := RandomNumberGenerator.new()


func start() -> void:
	_rng.randomize()
	var start_pad: Node3D = gm.platforms[0]
	_last_y = start_pad.global_position.y
	_last_angle = atan2(start_pad.global_position.x, start_pad.global_position.z)
	_generate_until(60.0)
	abyss = preload("res://scripts/abyss.gd").new()
	abyss.follow = player
	abyss.speed = 0.0
	gm.add_child(abyss)
	abyss.start(-22.0)
	hud.set_abyss(abyss)
	storm.set_wind([12.0, 18.0, 2.0, 8.0])
	running = true


func _difficulty(y: float) -> float:
	return clampf(y / T_FULL, 0.0, 1.0)


func _generate_until(y_target: float) -> void:
	while _last_y < y_target:
		_spawn_next()
	spine.extend_to(_last_y + 8.0)


func _spawn_next() -> void:
	_n += 1
	var t := _difficulty(_last_y)
	var dy := _rng.randf_range(5.0, 6.4) + t * 1.6
	var launch := 10.6 + t * 1.2
	if _rng.randf() < 0.15:
		_dir = -_dir
	_last_angle += deg_to_rad(_rng.randf_range(46.0, 60.0)) * _dir
	var r := _rng.randf_range(6.8, 8.2)
	_last_y += dy
	var g = PLATFORM_SCENE.instantiate()
	g.name = "Endless%03d" % _n
	g.position = Vector3(sin(_last_angle) * r, _last_y, cos(_last_angle) * r)
	g.diameter = lerpf(5.0, 3.1, t) * _rng.randf_range(0.92, 1.08)
	g.thickness = 0.5
	g.launch_height = launch
	g.note = MELODY[_n % MELODY.size()]
	if _n % 10 == 0:
		g.kind = Platform.Kind.CHECKPOINT  # a brazier every 10 gongs: bonus XP, no respawn
	gm.add_child(g)
	g.add_to_group("endless")
	# Hazards scale with height.
	if _n > 2 and _rng.randf() < lerpf(0.12, 0.65, t):
		g.swing_amp = _rng.randf_range(10.0, 14.0 + 10.0 * t)
		g.swing_speed = _rng.randf_range(0.45, 0.55 + 0.35 * t)
		g.swing_phase = _rng.randf() * TAU
		g.start_motion()
	var crack: bool = _n > 4 and not _last_cracked and g.kind != Platform.Kind.CHECKPOINT and _rng.randf() < lerpf(0.0, 0.35, t)
	if crack:
		g.cracked = true
	_last_cracked = crack
	gm.platforms.append(g)


const Platform := preload("res://scripts/platform.gd")


func _physics_process(delta: float) -> void:
	if not running:
		return
	var y := player.global_position.y
	highest = maxf(highest, y)
	_generate_until(y + 70.0)

	# The abyss: slow at the base, faster with height, and it catches up if you get far ahead.
	_grace -= delta
	var t := _difficulty(highest)
	var speed := 0.0 if _grace > 0.0 else lerpf(0.6, 1.5, t)
	var lead: float = y - abyss.height
	if lead > 40.0:
		speed *= 2.4
	abyss.speed = speed

	# Gusts get more frequent and stronger as you climb.
	storm.wind_cfg = [lerpf(12.0, 6.0, t), lerpf(18.0, 10.0, t), lerpf(2.0, 2.6, t), lerpf(8.0, 15.0, t)]

	# Milestones
	if highest >= _milestone:
		_award(50, "%d m  +50" % int(_milestone), Color(1.0, 0.85, 0.5))
		_milestone += 50.0

	# Tidy up far below.
	var floor_y: float = abyss.height - 30.0
	spine.cull_below(floor_y)
	for p in get_tree().get_nodes_in_group("endless"):
		if p.visible and p.global_position.y < floor_y:
			p.visible = false
			p.collision_layer = 0
			p.process_mode = Node.PROCESS_MODE_DISABLED

	if y < maxf(abyss.height + 0.2, -25.0):
		_end_run()


func on_gong_landed(gong: Node, slam: bool) -> void:
	if not running:
		return
	var idx: int = gm.platforms.find(gong)
	if idx < 0:
		return
	if idx > _best_index:
		var climbed := idx - _best_index
		for i in climbed:
			_award(5 * combo, "+%d" % (5 * combo), Color(1.0, 0.75, 0.4))
			combo = mini(combo + 1, 5)
		best_combo = maxi(best_combo, combo)
		gongs_reached += climbed
		_best_index = idx
		if slam:
			slams += 1
			_award(3 * combo, "Slam  +%d" % (3 * combo), Color(1.0, 0.55, 0.25))
		if gong.kind == Platform.Kind.CHECKPOINT:
			_award(25, "Brazier  +25", Color(1.0, 0.6, 0.2))
	elif idx < _best_index - 1 and combo > 1:
		combo = 1
		hud.popup("Combo lost", Color(0.75, 0.72, 0.65))


func _award(xp: int, label: String, color: Color) -> void:
	run_xp += xp
	hud.popup(label, color)


func _end_run() -> void:
	running = false
	abyss.speed = 0.0
	run_ended.emit({
		"height": highest,
		"xp": run_xp,
		"gongs": gongs_reached,
		"best_combo": best_combo,
		"slams": slams,
	})
