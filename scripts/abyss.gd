extends Node3D
## LAST REBOUND: the abyss. A churning, glowing floor that climbs the tower on Hard and Last Rebound.
## Touch it and you fall back to your last brazier.

@export var speed: float = 0.8
@export var follow: Node3D

var active := false
var height := -40.0

var _mat: StandardMaterial3D
var _light: OmniLight3D
var _rumble: AudioStreamPlayer
var _t := 0.0


func _ready() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.02
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.42, 0.1))
	ramp.add_point(0.035, Color(0.55, 0.07, 0.02))
	ramp.add_point(0.09, Color(0.03, 0.0, 0.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(0, 0, 0))
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.seamless = true
	tex.width = 512
	tex.height = 512

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.02, 0.01, 0.01)
	_mat.emission_enabled = true
	_mat.emission = Color(1, 1, 1)
	_mat.emission_texture = tex
	_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY  # texture drives the glow (default ADD washes it white)
	_mat.emission_energy_multiplier = 2.2
	_mat.uv1_scale = Vector3(24, 24, 24)
	_mat.roughness = 1.0

	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# A second, slower layer a little higher, so the surface churns.
	var mat2: StandardMaterial3D = _mat.duplicate()
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat2.albedo_color = Color(0.0, 0.0, 0.0, 0.5)
	mat2.uv1_scale = Vector3(13, 13, 13)
	mat2.emission_enabled = false
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi2 := MeshInstance3D.new()
	mi2.mesh = plane
	mi2.material_override = mat2
	mi2.position.y = 0.6
	mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi2.name = "Upper"
	add_child(mi2)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.3, 0.1)
	_light.light_energy = 3.0
	_light.omni_range = 26.0
	add_child(_light)

	_rumble = AudioStreamPlayer.new()
	var w: AudioStreamWAV = load("res://audio/wind_loop.wav")
	_rumble.stream = w
	_rumble.pitch_scale = 0.35
	_rumble.volume_db = -60.0
	add_child(_rumble)
	visible = false


func start(from_height: float) -> void:
	height = from_height
	active = true
	visible = true
	_rumble.play()


func reset_below(y: float, gap: float) -> void:
	height = minf(height, y - gap)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_mat.uv1_offset = Vector3(_t * 0.01, _t * 0.006, 0)
	var upper := get_node("Upper") as MeshInstance3D
	(upper.material_override as StandardMaterial3D).uv1_offset = Vector3(-_t * 0.017, _t * 0.004, 0)
	position = Vector3(0, height, 0)
	if follow:
		_light.global_position = Vector3(follow.global_position.x, height + 3.0, follow.global_position.z)
		var dist := follow.global_position.y - height
		_light.light_energy = clampf(4.0 - dist * 0.15, 0.4, 4.0)
		_rumble.volume_db = lerpf(-8.0, -40.0, clampf(dist / 30.0, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	if active:
		height += speed * delta


func stop() -> void:
	active = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "height", height - 60.0, 6.0).set_ease(Tween.EASE_IN)
	tw.tween_property(_rumble, "volume_db", -60.0, 3.0)
