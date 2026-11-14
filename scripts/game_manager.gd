extends Node3D
## LAST REBOUND: game director.
##
## INTRO   The ember rests beside the great bell. Lightning knocks it off.
##         It falls the full height of the tower (each gong rings as it passes)
##         and slams into the bottom gong. Title.
## PLAY    Climb. Checkpoint braziers light. At the last checkpoint, lightning
##         splits the tower and everything below you falls into the abyss.
## FINALE  Touch the great bell. The storm breaks and the sun comes up.
##
## Before all that: MENU, where you pick a mode (see difficulty.gd).
## The fourth mode, Last Rebound, skips the story: an endless tower and XP (endless.gd).

enum State { MENU, INTRO, PLAY, FINALE, ENDED }

@export var player: RigidBody3D
@export var camera_rig: Node3D
@export var audio: Node
@export var storm: Node3D
@export var hud: CanvasLayer
@export var great_bell: Node3D
@export var spine: Node3D
@export var fall_limit: float = -25.0
@export var checkpoint_fall_margin: float = 18.0
## Reaching the checkpoint at or above this height triggers the collapse.
@export var collapse_trigger_height: float = 59.0
@export var collapse_cut_height: float = 57.0

const Platform := preload("res://scripts/platform.gd")
const SAVE_PATH := "user://last_rebound.cfg"
const INTRO_ANGLE := 15.0  # degrees: the fall line through the tower that misses every gong

static var skip_intro := false
## -1 means "not chosen yet": show the menu.
static var level := -1

var state: State = State.INTRO
var platforms: Array = []
var start_pad: Node3D
var start_position: Vector3
var respawn_position: Vector3
var checkpoint_height: float = -INF
var checkpoints := 0
var highest := 0.0
var falls := 0
var elapsed := 0.0
var collapsed := false
var best_time := INF
var preset: Dictionary
var abyss: Node3D
var touch: CanvasLayer  # on-screen controls (phones, or --touch)
var endless: Node  # set in Last Rebound mode
var profile := {"xp": 0, "best_height": 0.0, "runs": 0, "ember": "Classic"}
var _wind_warned := false

var _intro_falling := false
var _intro_prev_y := 0.0


func _ready() -> void:
	_load_profile()
	var skin: Array = Difficulty.ember_by_name(profile["ember"])
	player.apply_skin(skin[2], skin[3])
	for a in OS.get_cmdline_user_args():  # e.g. -- --difficulty=hard (skips the menu)
		if a.begins_with("--difficulty="):
			level = Difficulty.from_id(a.substr(13))
	for p in get_tree().get_nodes_in_group("platforms"):
		platforms.append(p)
	platforms.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	start_pad = platforms[0]
	for p in platforms:
		p.checkpoint_reached.connect(_on_checkpoint_reached)
	player.impacted.connect(_on_player_impacted)
	player.slammed.connect(func(): audio.play("slam", -3.0))
	great_bell.rung.connect(_on_bell_rung)
	hud.setup(platforms, player)
	hud.difficulty_chosen.connect(_on_difficulty_chosen)
	hud.ember_changed.connect(_on_ember_changed)
	storm.gust_started.connect(_on_gust)
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") \
			or OS.get_cmdline_user_args().has("--touch"):
		_setup_touch()
	start_position = player.global_position
	respawn_position = start_position

	if level < 0:
		_show_menu()
	elif level == Difficulty.Level.ENDLESS:
		_apply_difficulty()
		_start_endless()
	else:
		_apply_difficulty()
		if skip_intro:
			_begin_play(false)
		else:
			_run_intro()


func _setup_touch() -> void:
	touch = preload("res://scripts/touch_controls.gd").new()
	touch.camera_rig = camera_rig
	touch.visible = false
	add_child(touch)
	touch.slam_pressed.connect(player.try_slam)
	touch.restart_pressed.connect(_restart)
	touch.menu_pressed.connect(_to_menu)
	hud.set_touch_mode(true)


func _restart() -> void:
	skip_intro = true
	get_tree().reload_current_scene()


func _to_menu() -> void:
	level = -1
	skip_intro = false
	get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	if touch:
		touch.visible = state == State.PLAY or state == State.FINALE or state == State.ENDED
		player.touch_vector = touch.move_vector if state == State.PLAY else Vector2.ZERO


# ----------------------------------------------------------------- difficulty
func _show_menu() -> void:
	state = State.MENU
	_pose_at_bell()
	var bests := {}
	for lv in Difficulty.ORDER:
		bests[lv] = _load_best_for(Difficulty.get_preset(lv)["id"])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_menu(bests, profile)


func _on_difficulty_chosen(chosen: int) -> void:
	if state != State.MENU:
		return
	level = chosen
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_difficulty()
	if level == Difficulty.Level.ENDLESS:
		_start_endless()
	else:
		_run_intro()


func _on_ember_changed(ember_name: String) -> void:
	profile["ember"] = ember_name
	var skin: Array = Difficulty.ember_by_name(ember_name)
	player.apply_skin(skin[2], skin[3])
	_save_profile()


func _on_gust(_dir: Vector3) -> void:
	if state == State.PLAY and not _wind_warned:
		_wind_warned = true
		hud.show_story("The wind rises. Watch the rain.", 2.2)


func _apply_difficulty() -> void:
	preset = Difficulty.get_preset(level)
	best_time = _load_best_for(preset["id"])
	player.move_force = preset["move_force"]
	player.max_horizontal_speed = preset["max_speed"]
	storm.min_interval = preset["lightning"][0]
	storm.max_interval = preset["lightning"][1]
	hud.set_difficulty(preset["name"])
	if level == Difficulty.Level.ENDLESS:
		return
	storm.set_wind(preset["wind"])
	var swinging: Dictionary = preset["swinging"]
	var cracked: Array = preset["cracked"]
	var cps: Array = preset["checkpoints"]
	for p in platforms:
		if p.kind == Platform.Kind.SUMMIT:
			continue
		p.diameter = p.diameter * preset["gong_scale"]
		p.launch_height += preset["launch_bonus"]
		if p.kind != Platform.Kind.BOOST:
			p.kind = Platform.Kind.CHECKPOINT if cps.has(String(p.name)) else Platform.Kind.NORMAL
		var nm := String(p.name)
		if swinging.has(nm):
			p.swing_amp = swinging[nm][0]
			p.swing_speed = swinging[nm][1]
			p.swing_phase = randf() * TAU
		if cracked.has(nm):
			p.cracked = true
	if preset["abyss_speed"] > 0.0:
		abyss = preload("res://scripts/abyss.gd").new()
		abyss.speed = preset["abyss_speed"]
		abyss.follow = player
		add_child(abyss)
		hud.set_abyss(abyss)


func _pose_at_bell() -> void:
	var a := deg_to_rad(INTRO_ANGLE)
	var top: Vector3 = great_bell.global_position + Vector3(sin(a) * 3.5, 0.62, cos(a) * 3.5)
	player.set_intro(true)
	player.freeze = true
	player.global_position = top
	player.reset_physics_interpolation()
	camera_rig.set_cinematic(a, 0.32)
	camera_rig.snap()
	hud.set_letterbox(true, 0.01)
	audio.targets = [-12.0, -60.0, -60.0]


func _unhandled_input(event: InputEvent) -> void:
	if state == State.MENU:
		return
	if event.is_action_pressed("restart"):
		_restart()
	elif event.is_action_pressed("menu"):
		_to_menu()
	elif state == State.INTRO and (event.is_action_pressed("ui_accept") or event.is_action_pressed("jump") \
			or (event is InputEventScreenTouch and event.pressed)):
		_skip_intro_now()


# ----------------------------------------------------------------- intro
func _run_intro() -> void:
	state = State.INTRO
	var a := deg_to_rad(INTRO_ANGLE)
	_pose_at_bell()
	hud.show_story("The bell has not rung in a thousand storms.", 2.6)

	await get_tree().create_timer(3.4).timeout
	if state != State.INTRO:
		return
	storm.strike(great_bell.global_position + Vector3(0, 8, 0), true)
	great_bell.ring(0.35)
	audio.play("great_bell", -10.0)
	camera_rig.shake(0.8)
	player.freeze = false
	player.linear_velocity = Vector3(sin(a), 0, cos(a)) * 1.2 + Vector3.UP * 4.0
	camera_rig.tween_pitch(-1.05, 1.2)
	_intro_prev_y = player.global_position.y
	_intro_falling = true
	await get_tree().create_timer(0.9).timeout
	if state == State.INTRO:
		hud.show_story("It fell.", 1.6)


func _intro_physics() -> void:
	if not _intro_falling:
		return
	var y := player.global_position.y
	# Steer onto the fall line (radius 6 at INTRO_ANGLE), which threads past every gong.
	var a := deg_to_rad(INTRO_ANGLE)
	var r := lerpf(3.5, 6.0, clampf((great_bell.global_position.y + 0.6 - y) / 6.0, 0.0, 1.0))
	var target := Vector3(sin(a) * r, 0, cos(a) * r)
	var p := player.global_position
	player.linear_velocity.x = (target.x - p.x) * 5.0
	player.linear_velocity.z = (target.z - p.z) * 5.0
	# Every gong you pass rings: the melody plays in reverse as you fall.
	for pad in platforms:
		var top: float = pad.get_top_y() + 0.6
		if _intro_prev_y > top and y <= top and pad != start_pad:
			pad.ring(0.75)
	_intro_prev_y = y
	audio.set_fall_speed(-player.linear_velocity.y)
	if y < 6.0:
		player.set_intro(false)
		player.controls_enabled = false
		_intro_falling = false


func _intro_landed() -> void:
	audio.play("title_hit", 0.0)
	audio.duck(1.2)
	storm.flash = 1.0
	hud.flash(0.7)
	camera_rig.shake(1.2)
	hud.show_title()
	camera_rig.tween_pitch(-0.3, 2.0)
	await get_tree().create_timer(3.4).timeout
	if state != State.INTRO:
		return
	hud.hide_title()
	_begin_play(true)


func _skip_intro_now() -> void:
	_intro_falling = false
	player.set_intro(false)
	player.freeze = false
	player.respawn(start_position)
	hud.hide_title()
	_begin_play(false)
	camera_rig.snap.call_deferred()


# ----------------------------------------------------------------- play
func _begin_play(from_intro: bool) -> void:
	state = State.PLAY
	player.set_intro(false)
	player.controls_enabled = true
	hud.set_letterbox(false, 1.2)
	var p := player.global_position
	camera_rig.follow(atan2(p.x, p.z))
	camera_rig.tween_pitch(-0.3, 0.8)
	audio.targets = [-3.0, -60.0, -60.0]
	if not from_intro:
		hud.show_story("Rise.  Ring the bell.", 2.5)
	hud.show_hint(9.0)
	for g in platforms:
		g.start_motion()
	if abyss:
		abyss.start(-26.0)
		if from_intro:
			hud.show_story("Something stirs below.", 2.5)


func _physics_process(delta: float) -> void:
	if state == State.PLAY and storm.wind_force != Vector3.ZERO:
		player.apply_central_force(storm.wind_force)
	match state:
		State.INTRO:
			_intro_physics()
		State.PLAY:
			_play_physics(delta)
		State.FINALE:
			audio.set_fall_speed(0.0)


func _play_physics(delta: float) -> void:
	elapsed += delta
	var y := player.global_position.y
	highest = maxf(highest, y)
	var gust: float = storm.wind_force.length() / 15.0
	if endless:
		hud.update_endless(y, highest, endless.run_xp, endless.combo, abyss.height if abyss else -INF)
		audio.set_intensity(smoothstep(4.0, 40.0, highest), smoothstep(40.0, 110.0, highest))
		audio.set_fall_speed(-player.linear_velocity.y, gust)
		return
	hud.update_stats(elapsed, falls, highest)

	var pulse := smoothstep(6.0, 28.0, highest)
	var strings := 1.0 if collapsed else smoothstep(36.0, 58.0, highest)
	audio.set_intensity(pulse, strings)
	audio.set_fall_speed(-player.linear_velocity.y, gust)

	var kill := maxf(fall_limit, checkpoint_height - checkpoint_fall_margin)
	if abyss:
		kill = maxf(kill, abyss.height)
	if y < kill:
		_reset_player()


func _reset_player() -> void:
	falls += 1
	player.respawn(respawn_position)
	if abyss:
		abyss.reset_below(respawn_position.y, preset["abyss_gap"])
	camera_rig.snap.call_deferred()
	audio.play("respawn", -4.0)
	var lines := ["Again.", "The tower remembers.", "Fall. Rise.", "Again.", "You have done this before."]
	hud.show_story(lines[(falls - 1) % lines.size()], 1.8)


func _on_player_impacted(speed: float, collider: Node, top_hit: bool) -> void:
	camera_rig.shake(speed / 32.0)
	if collider and collider.is_in_group("stone"):
		audio.play("stone_hit", linear_to_db(clampf(speed / 18.0, 0.2, 1.0)) - 2.0, randf_range(0.85, 1.1))
	if state == State.INTRO and collider == start_pad and top_hit:
		_intro_landed()
	if endless and top_hit and collider and collider.has_method("get_launch_speed"):
		endless.on_gong_landed(collider, player.last_landing_was_slam)


func _on_checkpoint_reached(platform) -> void:
	var h: float = platform.global_position.y
	if h <= checkpoint_height:
		return
	checkpoints += 1
	checkpoint_height = h
	respawn_position = platform.get_respawn_point()
	audio.play("ignite", -2.0)
	if h >= collapse_trigger_height and not collapsed:
		_collapse()
		return
	var lines := ["", "Every fall taught you the height.", "The storm is watching now."]
	if checkpoints < lines.size():
		hud.show_story(lines[checkpoints], 3.0)


func _collapse() -> void:
	collapsed = true
	await get_tree().create_timer(0.7).timeout
	storm.strike(Vector3(0, collapse_cut_height - 1.0, 0), true)
	audio.play("collapse", 0.0)
	audio.duck(0.6)
	camera_rig.shake(1.2)
	hud.show_story("There is no way back down.", 3.5)
	spine.collapse_below(collapse_cut_height, 0.1)
	for p in platforms:
		if p.global_position.y < collapse_cut_height:
			p.collapse(0.2 + (collapse_cut_height - p.global_position.y) * 0.02 + randf() * 0.2)


# ----------------------------------------------------------------- finale
func _on_bell_rung() -> void:
	if state == State.FINALE:
		return
	state = State.FINALE
	player.controls_enabled = false
	if abyss:
		abyss.stop()
	audio.play("great_bell", -3.0)
	audio.to_finale()
	storm.begin_dawn(9.0)
	hud.flash(0.5)
	hud.set_letterbox(true, 2.0)
	camera_rig.shake(0.6)
	camera_rig.orbit(great_bell.global_position + Vector3(0, 4, 0), 34.0, 1.0, atan2(player.global_position.x, player.global_position.z))
	var record := elapsed < best_time
	if record:
		best_time = elapsed
		_save_best()
	await get_tree().create_timer(3.0).timeout
	hud.show_results(elapsed, falls, best_time, record, preset["name"])


# ----------------------------------------------------------------- endless
func _start_endless() -> void:
	# Clear the story tower: keep only the bottom gong; the bell and the rest go.
	for p in platforms.duplicate():
		if p != start_pad:
			platforms.erase(p)
			p.queue_free()
	great_bell.queue_free()
	start_pad.launch_height = 9.5
	_intro_falling = false
	player.set_intro(false)
	player.freeze = false
	player.respawn(start_position)
	hud.hide_title()
	hud.set_letterbox(false, 0.6)
	state = State.PLAY
	player.controls_enabled = true
	camera_rig.follow(atan2(start_position.x, start_position.z))
	camera_rig.tween_pitch(-0.3, 0.6)
	camera_rig.snap.call_deferred()
	audio.targets = [-3.0, -60.0, -60.0]
	endless = preload("res://scripts/endless.gd").new()
	endless.gm = self
	endless.player = player
	endless.spine = spine
	endless.storm = storm
	endless.hud = hud
	endless.audio = audio
	add_child(endless)
	endless.start()
	abyss = endless.abyss
	endless.run_ended.connect(_on_endless_ended)
	hud.show_story("The tower never ends. The abyss never stops.", 3.0)
	hud.show_hint(8.0)


func _on_endless_ended(summary: Dictionary) -> void:
	state = State.ENDED
	player.controls_enabled = false
	player.freeze = true
	storm.strike(player.global_position + Vector3(0, 2, 0), true)
	audio.play("collapse", -4.0)
	camera_rig.shake(1.0)
	var level_before := Difficulty.level_for_xp(profile["xp"])
	profile["xp"] += int(summary["xp"])
	profile["runs"] += 1
	var new_best: bool = summary["height"] > profile["best_height"]
	if new_best:
		profile["best_height"] = summary["height"]
	_save_profile()
	var level_after := Difficulty.level_for_xp(profile["xp"])
	var unlocked := []
	for e in Difficulty.EMBERS:
		if e[0] > level_before and e[0] <= level_after:
			unlocked.append(e[1])
	summary["new_best"] = new_best
	summary["best_height"] = profile["best_height"]
	summary["level_before"] = level_before
	summary["level_after"] = level_after
	summary["total_xp"] = profile["xp"]
	summary["unlocked"] = unlocked
	await get_tree().create_timer(1.2).timeout
	hud.show_endless_results(summary)


func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		for k in profile.keys():
			profile[k] = cfg.get_value("profile", k, profile[k])


func _save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	for k in profile.keys():
		cfg.set_value("profile", k, profile[k])
	cfg.save(SAVE_PATH)


func _load_best_for(id: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return cfg.get_value("records", "best_" + id, INF)
	return INF


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("records", "best_" + preset["id"], best_time)
	cfg.save(SAVE_PATH)
