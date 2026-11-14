@tool
extends AnimatableBody3D
## LAST REBOUND: a bronze gong bolted to the tower on a stone arm.
##
## Every gong is an instrument. It rings its own note when you land, so the climb plays a melody.
## Physics: the engine bounces the orb, then the gong tops its upward speed up to `launch_height`.
##
## Hazards (set by the difficulty): a gong can SWING on its arm around the tower, or be CRACKED:
## it holds one landing, crumbles, and reforms a few seconds later.

signal checkpoint_reached(platform: Node3D)

enum Kind { NORMAL, CHECKPOINT, BOOST, SUMMIT }

const SPINE_RADIUS := 1.2
const BRONZE := Color(0.52, 0.34, 0.15)
const HEAT := Color(1.0, 0.42, 0.1)

@export var diameter: float = 5.0:
	set(v):
		diameter = v
		_rebuild()
@export var thickness: float = 0.5:
	set(v):
		thickness = v
		_rebuild()
@export var kind: Kind = Kind.NORMAL:
	set(v):
		kind = v
		_rebuild()
## How high above the pad the orb's rebound peaks (meters).
@export var launch_height: float = 10.0
## Pitch of this gong, in semitones relative to D4.
@export var note: int = 0
## Build a stone arm back to the tower's spine.
@export var has_arm: bool = true:
	set(v):
		has_arm = v
		_rebuild()

var activated := false
var collapsed := false

## Swing: amplitude (degrees around the tower) and speed (rad/s). 0 = still.
var swing_amp := 0.0
var swing_speed := 0.0
var swing_phase := 0.0
var cracked := false:
	set(v):
		cracked = v
		_rebuild()
var broken := false

var _motion_active := false
var _base_angle := 0.0
var _radius := 0.0
var _clock := 0.0

var _visual: Node3D
var _heat_material: StandardMaterial3D
var _heat := 0.0
var _wobble := Vector3.ZERO      # angular offset (radians)
var _wobble_vel := Vector3.ZERO
var _ring: AudioStreamPlayer3D
var _fire: GPUParticles3D
var _fire_light: OmniLight3D
var _t := 0.0

static var _bronze_mat: StandardMaterial3D
static var _bronze_dark_mat: StandardMaterial3D
static var _stone_mat: StandardMaterial3D
static var _bell_stream: AudioStream
static var _cracked_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("platforms")
	_rebuild()


# ----------------------------------------------------------------- gameplay API
func get_launch_speed() -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return sqrt(2.0 * g * launch_height)


func get_respawn_point() -> Vector3:
	return global_position + Vector3(0, thickness * 0.5 + 1.6, 0)


func get_top_y() -> float:
	return global_position.y + thickness * 0.5


func on_player_landed(_player: Node, impact_speed: float) -> void:
	ring(clampf(impact_speed / 16.0, 0.35, 1.3))
	if cracked and not broken:
		_crumble()
	if kind == Kind.CHECKPOINT and not activated:
		activated = true
		_light_brazier()
		checkpoint_reached.emit(self)


## Ring the gong. `strength` is about 0..1.3.
func ring(strength: float = 1.0) -> void:
	_heat = maxf(_heat, clampf(strength, 0.2, 1.4))
	var axis := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	_wobble_vel += axis * 0.9 * strength
	if _ring and kind != Kind.SUMMIT:
		_ring.pitch_scale = pow(2.0, note / 12.0)
		_ring.volume_db = linear_to_db(clampf(strength, 0.15, 1.2)) - 2.0
		_ring.play()


## The tower collapses: fall into the abyss.
func collapse(delay: float) -> void:
	if collapsed:
		return
	collapsed = true
	_motion_active = false
	var tw := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_interval(delay)
	tw.tween_callback(func():
		collision_layer = 0
		for c in get_children():
			if c is StaticBody3D:
				c.collision_layer = 0
	)
	var spin := Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
	tw.tween_method(func(k: float):
		position.y -= k * k * 1.6
		rotation = spin * k * 0.6
	, 0.0, 1.0, 3.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(hide)


## Start swinging (called when play begins, so the intro fall line stays clear).
func start_motion() -> void:
	if swing_amp <= 0.0 or collapsed:
		return
	var flat := Vector2(position.x, position.z)
	_radius = flat.length()
	_base_angle = atan2(position.x, position.z)
	_motion_active = _radius > 0.5


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _motion_active:
		return
	_clock += delta
	var a := _base_angle + deg_to_rad(swing_amp) * sin(_clock * swing_speed + swing_phase)
	position = Vector3(sin(a) * _radius, position.y, cos(a) * _radius)
	rotation.y = a - _base_angle


## Cracked gong: shudder, drop away, reform.
func _crumble() -> void:
	broken = true
	if _ring:
		_ring.pitch_scale = pow(2.0, note / 12.0) * 0.5
		_ring.play()
	var tw := create_tween()
	tw.tween_method(func(k: float): _visual.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.08 * (1.0 - k), 0.0, 1.0, 0.35)
	tw.tween_callback(func(): collision_layer = 0)
	tw.tween_property(_visual, "position", Vector3(0, -14, 0), 0.9).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): _visual.visible = false)
	tw.tween_interval(3.6)
	tw.tween_callback(func():
		_visual.position = Vector3.ZERO
		_visual.visible = true
		_visual.scale = Vector3(0.2, 0.2, 0.2)
		collision_layer = 1
		broken = false
		_heat = 1.4
	)
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ----------------------------------------------------------------- per-frame
func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _visual == null:
		return
	_t += delta
	# Damped spring wobble: the gong shudders after a hit.
	var accel := -_wobble * 140.0 - _wobble_vel * 5.0
	_wobble_vel += accel * delta
	_wobble += _wobble_vel * delta
	_visual.rotation = _wobble * 0.08

	_heat = move_toward(_heat, 0.0, delta * 0.9)
	var base := 0.06
	if cracked:
		base = 0.35 + sin(_t * 5.0) * 0.12
	if kind == Kind.BOOST:
		base = 0.55 + sin(_t * 3.0) * 0.25
	_heat_material.emission_energy_multiplier = (base + _heat) * 3.0

	if _fire_light and activated:
		_fire_light.light_energy = 3.2 + sin(_t * 17.0) * 0.35 + sin(_t * 7.3) * 0.5


# ----------------------------------------------------------------- building
func _rebuild() -> void:
	if not is_inside_tree():
		return
	_make_materials()
	for c in get_children():
		if c.name.begins_with("_gen"):
			remove_child(c)
			c.queue_free()

	var r := diameter * 0.5
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node:
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = thickness
		shape_node.shape = cyl
	var mesh_node := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_node:
		mesh_node.mesh = null  # visuals are generated below

	_visual = Node3D.new()
	_visual.name = "_genVisual"
	add_child(_visual)

	var top := thickness * 0.5
	if kind == Kind.SUMMIT:
		_add_mesh(_visual, _cyl(r, r * 0.92, thickness), _stone_mat, Vector3.ZERO)
		_add_mesh(_visual, _torus(r - 0.35, r, 24), _stone_mat, Vector3(0, top, 0))
	else:
		# Gong body + rim + boss + engraved ring. Cracked gongs glow through their fractures.
		_add_mesh(_visual, _cyl(r, r * 0.97, thickness), _cracked_mat if cracked else _bronze_mat, Vector3.ZERO)
		_heat_material = _bronze_dark_mat.duplicate()
		_heat_material.emission_enabled = true
		_heat_material.emission = HEAT
		_heat_material.emission_energy_multiplier = 0.0
		_add_mesh(_visual, _torus(r - 0.22, r + 0.02, 48), _heat_material, Vector3(0, top - 0.02, 0))
		_add_mesh(_visual, _torus(r * 0.52, r * 0.52 + 0.07, 40), _heat_material, Vector3(0, top, 0))
		var boss := SphereMesh.new()
		boss.radius = minf(0.55, r * 0.18)
		boss.height = boss.radius * 0.7
		boss.radial_segments = 24
		boss.rings = 8
		_add_mesh(_visual, boss, _heat_material, Vector3(0, top, 0))
		# Underside lip, slightly darker, so the gong reads as a dish from below.
		_add_mesh(_visual, _cyl(r * 0.9, r * 0.6, 0.25), _bronze_dark_mat, Vector3(0, -thickness * 0.5 - 0.12, 0))
	if _heat_material == null:
		_heat_material = _bronze_dark_mat.duplicate()
		_heat_material.emission_enabled = true

	if has_arm:
		_build_arm()
	if kind == Kind.CHECKPOINT:
		_build_brazier()

	if not Engine.is_editor_hint():
		if _bell_stream == null:
			_bell_stream = load("res://audio/bell_hit.wav")
		_ring = AudioStreamPlayer3D.new()
		_ring.name = "_genRing"
		_ring.stream = _bell_stream
		_ring.unit_size = 14.0
		_ring.max_db = 3.0
		_ring.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(_ring)


func _build_arm() -> void:
	var flat := Vector3(global_position.x, 0, global_position.z)
	var dist := flat.length()
	if dist < SPINE_RADIUS + 0.5:
		return
	var inward := -flat.normalized()
	# Local direction (the platform itself is not rotated in the tower).
	var arm_len := dist - SPINE_RADIUS + 0.3
	var mid := inward * (arm_len * 0.5 - 0.15)
	var arm_h := 0.9
	var y := -thickness * 0.5 - arm_h * 0.5 - 0.05

	var body := StaticBody3D.new()
	body.collision_layer = 3  # also on layer 2, so the camera stays in front of the arms
	body.name = "_genArm"
	add_child(body)
	body.position = Vector3(mid.x, y, mid.z)
	body.rotation.y = atan2(inward.x, inward.z)
	var box := BoxMesh.new()
	box.size = Vector3(0.9, arm_h, arm_len)
	_add_mesh(body, box, _stone_mat, Vector3.ZERO)
	# Brace that tapers under the arm.
	var brace := BoxMesh.new()
	brace.size = Vector3(0.6, 1.6, arm_len * 0.45)
	_add_mesh(body, brace, _stone_mat, Vector3(0, -1.0, arm_len * 0.25))
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	col.shape = bs
	body.add_child(col)
	body.add_to_group("stone")


func _build_brazier() -> void:
	var r := diameter * 0.5
	var flat := Vector3(global_position.x, 0, global_position.z)
	var outward := flat.normalized() if flat.length() > 0.1 else Vector3(0, 0, 1)
	var side := outward.cross(Vector3.UP).normalized()
	var base := (outward * 0.25 + side).normalized() * (r - 0.15)
	var holder := Node3D.new()
	holder.name = "_genBrazier"
	_visual.add_child(holder)
	holder.position = Vector3(base.x, thickness * 0.5, base.z)
	_add_mesh(holder, _cyl(0.16, 0.22, 1.3), _bronze_dark_mat, Vector3(0, 0.65, 0))
	_add_mesh(holder, _cyl(0.5, 0.2, 0.35), _bronze_dark_mat, Vector3(0, 1.45, 0))
	var coals := _cyl(0.42, 0.42, 0.06)
	_add_mesh(holder, coals, _heat_material, Vector3(0, 1.6, 0))

	_fire = _make_fire()
	_fire.position = Vector3(0, 1.65, 0)
	_fire.emitting = false
	holder.add_child(_fire)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.55, 0.22)
	_fire_light.light_energy = 0.0
	_fire_light.omni_range = 9.0
	_fire_light.position = Vector3(0, 2.1, 0)
	holder.add_child(_fire_light)


func _light_brazier() -> void:
	if _fire:
		_fire.emitting = true
	if _fire_light:
		_fire_light.light_energy = 3.2
	_heat = 1.4


func _make_fire() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 46
	p.lifetime = 0.9
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.25
	m.direction = Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = 1.2
	m.initial_velocity_max = 2.4
	m.gravity = Vector3(0, 1.5, 0)
	m.scale_min = 0.5
	m.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	g.set_color(1, Color(0.6, 0.08, 0.02, 0.0))
	g.add_point(0.35, Color(1.0, 0.5, 0.12, 0.9))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.7)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.albedo_texture = _soft_dot()
	quad.material = qm
	p.draw_pass_1 = quad
	return p


# ----------------------------------------------------------------- helpers
static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(top_r: float, bottom_r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = 48
	c.rings = 1
	return c


func _torus(inner: float, outer: float, seg: int) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = seg
	t.ring_segments = 8
	return t


static func _make_materials() -> void:
	if _bronze_mat != null:
		return
	# Bronze with verdigris patches.
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.02
	noise.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.2, 0.3, 0.27))
	ramp.add_point(0.22, Color(0.26, 0.24, 0.16))
	ramp.add_point(0.4, BRONZE * 0.7)
	ramp.set_color(ramp.get_point_count() - 1, BRONZE * 1.1)
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.seamless = true
	tex.width = 512
	tex.height = 512
	var rough_noise := NoiseTexture2D.new()
	rough_noise.noise = noise
	rough_noise.seamless = true

	_bronze_mat = StandardMaterial3D.new()
	_bronze_mat.albedo_texture = tex
	_bronze_mat.metallic = 0.55
	_bronze_mat.roughness = 0.5
	_bronze_mat.roughness_texture = rough_noise
	_bronze_mat.uv1_triplanar = true
	_bronze_mat.uv1_scale = Vector3(0.35, 0.35, 0.35)

	_bronze_dark_mat = StandardMaterial3D.new()
	_bronze_dark_mat.albedo_color = BRONZE * 0.75
	_bronze_dark_mat.metallic = 0.6
	_bronze_dark_mat.roughness = 0.4

	_stone_mat = make_stone_material()

	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_CELLULAR
	cn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cn.frequency = 0.05
	var cramp := Gradient.new()
	cramp.set_color(0, Color(1.0, 0.35, 0.08))
	cramp.add_point(0.05, Color(0.5, 0.06, 0.02))
	cramp.add_point(0.12, Color(0, 0, 0))
	cramp.set_color(cramp.get_point_count() - 1, Color(0, 0, 0))
	var ctex := NoiseTexture2D.new()
	ctex.noise = cn
	ctex.color_ramp = cramp
	ctex.seamless = true
	_cracked_mat = StandardMaterial3D.new()
	_cracked_mat.albedo_color = BRONZE * 0.45
	_cracked_mat.metallic = 0.5
	_cracked_mat.roughness = 0.65
	_cracked_mat.emission_enabled = true
	_cracked_mat.emission = Color(1, 1, 1)
	_cracked_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	_cracked_mat.emission_texture = ctex
	_cracked_mat.emission_energy_multiplier = 2.5
	_cracked_mat.uv1_triplanar = true
	_cracked_mat.uv1_scale = Vector3(0.35, 0.35, 0.35)


static func make_stone_material() -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.seed = 3
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.03
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.06, 0.06, 0.065))
	ramp.set_color(1, Color(0.2, 0.2, 0.21))
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.color_ramp = ramp
	tex.seamless = true
	var nrm := NoiseTexture2D.new()
	nrm.noise = n
	nrm.as_normal_map = true
	nrm.bump_strength = 6.0
	nrm.seamless = true
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.normal_enabled = true
	m.normal_texture = nrm
	m.normal_scale = 0.8
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	return m
