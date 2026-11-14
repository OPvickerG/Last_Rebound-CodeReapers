extends Node3D
## LAST REBOUND: the storm. Rain, lightning, thunder, and the dawn that ends it.

@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var camera_rig: Node3D
@export var audio: Node
@export var hud: CanvasLayer
@export var min_interval: float = 7.0
@export var max_interval: float = 15.0

var active := true
var flash := 0.0
var dawn := 0.0

signal gust_started(direction: Vector3)

## Wind gusts: [min gap s, max gap s, gust length s, force N]. Empty = calm.
var wind_cfg: Array = []
## The force the wind applies to the ember right now (the game manager applies it).
var wind_force := Vector3.ZERO
var _wind_next := 6.0
var _gust_time := 0.0
var _gust_len := 0.0
var _gust_dir := Vector3.ZERO
var _rain_mat: ParticleProcessMaterial

var _sky: ShaderMaterial
var _env: Environment
var _rain: GPUParticles3D
var _bolt: MeshInstance3D
var _bolt_mesh: ImmediateMesh
var _bolt_life := 0.0
var _next := 4.0
var _base_sun_energy := 0.0
var _base_ambient := 0.0
var _storm_fog: Color
var _storm_ambient: Color


func _ready() -> void:
	_env = world_environment.environment
	_sky = _env.sky.sky_material as ShaderMaterial
	_base_sun_energy = sun.light_energy
	_base_ambient = _env.ambient_light_energy
	_storm_fog = _env.fog_light_color
	_storm_ambient = _env.ambient_light_color
	_build_rain()
	_bolt_mesh = ImmediateMesh.new()
	_bolt = MeshInstance3D.new()
	_bolt.mesh = _bolt_mesh
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(3.2, 3.4, 4.2)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt.material_override = m
	_bolt.top_level = true
	add_child(_bolt)


func _process(delta: float) -> void:
	if camera_rig:
		_rain.global_position = camera_rig.global_position + Vector3(0, 14, 0)
	flash = move_toward(flash, 0.0, delta * 3.5)
	_sky.set_shader_parameter("flash", flash)
	_sky.set_shader_parameter("dawn", dawn)
	if dawn < 0.01:
		sun.light_energy = _base_sun_energy + flash * 3.5
		_env.ambient_light_energy = _base_ambient + flash * 1.4
	_bolt_life -= delta
	_bolt.visible = _bolt_life > 0.0 and fmod(_bolt_life, 0.09) > 0.03

	if active:
		_next -= delta
		if _next <= 0.0:
			_next = randf_range(min_interval, max_interval)
			strike()
	_update_wind(delta)


func set_wind(cfg: Array) -> void:
	wind_cfg = cfg
	if not cfg.is_empty():
		_wind_next = randf_range(cfg[0], cfg[1])


func _update_wind(delta: float) -> void:
	if wind_cfg.is_empty() or not active:
		wind_force = wind_force.move_toward(Vector3.ZERO, delta * 30.0)
		return
	if _gust_time > 0.0:
		_gust_time -= delta
		# Smooth rise and fall over the gust.
		var k := 1.0 - _gust_time / _gust_len
		var env := sin(clampf(k, 0.0, 1.0) * PI)
		wind_force = _gust_dir * wind_cfg[3] * env
	else:
		wind_force = Vector3.ZERO
		_wind_next -= delta
		if _wind_next <= 0.0:
			_wind_next = randf_range(wind_cfg[0], wind_cfg[1])
			_gust_len = wind_cfg[2]
			_gust_time = _gust_len
			var a := randf() * TAU
			_gust_dir = Vector3(sin(a), 0, cos(a))
			gust_started.emit(_gust_dir)
	# Rain slants with the wind: the warning you can see.
	if _rain_mat:
		var lean := wind_force / maxf(1.0, wind_cfg[3]) * 0.9
		_rain_mat.direction = Vector3(0.12 + lean.x, -1.0, 0.05 + lean.z).normalized()


## Lightning. With no target, it hits somewhere far out in the storm.
func strike(target := Vector3.INF, loud := false) -> void:
	var cam_pos: Vector3 = camera_rig.global_position if camera_rig else Vector3.ZERO
	if target == Vector3.INF:
		var a := randf() * TAU
		var d := randf_range(70.0, 140.0)
		target = cam_pos + Vector3(sin(a) * d, randf_range(-40, -10), cos(a) * d)
	_draw_bolt(Vector3(target.x + randf_range(-20, 20), target.y + 140.0, target.z + randf_range(-20, 20)), target)
	_bolt_life = 0.32
	var tw := create_tween()
	tw.tween_property(self, "flash", 1.4, 0.03)
	tw.tween_property(self, "flash", 0.25, 0.08)
	tw.tween_property(self, "flash", 1.1, 0.04)
	if hud:
		hud.flash(0.55 if loud else 0.22)
	var dist := cam_pos.distance_to(target)
	var delay := 0.05 if loud else clampf(dist / 343.0 * 2.5, 0.2, 1.8)
	if audio:
		audio.thunder(delay, 0.0 if loud else -4.0 - dist * 0.03)


func _draw_bolt(from: Vector3, to: Vector3) -> void:
	_bolt_mesh.clear_surfaces()
	var cam: Camera3D = get_viewport().get_camera_3d()
	var right := cam.global_basis.x if cam else Vector3.RIGHT
	var pts := _jagged(from, to, 22, 7.0)
	_strip(pts, right, 0.9)
	for i in 3:  # branches
		var k := randi_range(4, pts.size() - 6)
		var start: Vector3 = pts[k]
		var end := start + Vector3(randf_range(-25, 25), randf_range(-40, -18), randf_range(-25, 25))
		_strip(_jagged(start, end, 8, 4.0), right, 0.45)


func _jagged(a: Vector3, b: Vector3, steps: int, wander: float) -> Array:
	var pts := [a]
	for i in range(1, steps):
		var t := float(i) / steps
		var p := a.lerp(b, t) + Vector3(randf_range(-wander, wander), 0, randf_range(-wander, wander))
		pts.append(p)
	pts.append(b)
	return pts


func _strip(pts: Array, right: Vector3, width: float) -> void:
	_bolt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var w := width * (1.0 - float(i) / pts.size() * 0.6)
		_bolt_mesh.surface_add_vertex(pts[i] - right * w)
		_bolt_mesh.surface_add_vertex(pts[i] + right * w)
	_bolt_mesh.surface_end()


## The storm breaks: dawn over the tower.
func begin_dawn(seconds: float = 8.0) -> void:
	active = false
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "dawn", 1.0, seconds)
	tw.tween_property(_rain, "amount_ratio", 0.0, seconds * 0.5)
	tw.tween_property(sun, "light_color", Color(1.0, 0.72, 0.45), seconds)
	tw.tween_property(sun, "light_energy", 2.2, seconds)
	tw.tween_property(sun, "rotation_degrees", Vector3(-12, 160, 0), seconds)
	tw.tween_property(_env, "fog_light_color", Color(0.85, 0.55, 0.38), seconds)
	tw.tween_property(_env, "fog_density", 0.0035, seconds)
	tw.tween_property(_env, "ambient_light_color", Color(0.75, 0.6, 0.55), seconds)
	tw.tween_property(_env, "ambient_light_energy", 0.9, seconds)


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 1300 if OS.has_feature("mobile") else 2600
	_rain.lifetime = 1.1
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-30, -40, -30), Vector3(60, 60, 60))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(26, 1, 26)
	m.direction = Vector3(0.12, -1, 0.05)
	m.spread = 2.0
	m.initial_velocity_min = 32.0
	m.initial_velocity_max = 40.0
	m.gravity = Vector3(0, -10, 0)
	_rain.process_material = m
	_rain_mat = m
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.85)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.albedo_color = Color(0.62, 0.68, 0.8, 0.32)
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = qm
	_rain.draw_pass_1 = q
	add_child(_rain)
