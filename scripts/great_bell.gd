extends Node3D
## LAST REBOUND: the great bell at the summit. Touch it and the storm ends.

signal rung

@export var pillar_spread: float = 3.6
@export var frame_height: float = 9.4

var _pivot: Node3D
var _swing := 0.0
var _swing_vel := 0.0
var _light: OmniLight3D
var _glow_mat: StandardMaterial3D
var _glow := 0.0
var _done := false

# Bell profile (radius, y) from the crown down the outside, round the lip, and back up the inside.
const PROFILE := [
	Vector2(0.0, 0.0), Vector2(0.75, 0.0), Vector2(1.18, -0.25), Vector2(1.32, -0.7),
	Vector2(1.33, -1.4), Vector2(1.44, -2.1), Vector2(1.72, -2.75), Vector2(2.18, -3.25),
	Vector2(2.48, -3.55), Vector2(2.5, -3.72), Vector2(2.22, -3.6), Vector2(1.92, -3.22),
	Vector2(1.56, -2.72), Vector2(1.22, -2.02), Vector2(1.13, -1.32), Vector2(1.06, -0.62),
	Vector2(0.8, -0.28), Vector2(0.0, -0.24),
]


func _ready() -> void:
	var stone: StandardMaterial3D = preload("res://scripts/platform.gd").make_stone_material()
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.42, 0.28, 0.12)
	bronze.metallic = 0.6
	bronze.roughness = 0.42
	bronze.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_mat = bronze.duplicate()
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1.0, 0.62, 0.25)
	_glow_mat.emission_energy_multiplier = 0.0

	# Stone belfry: two pillars and a lintel.
	for sx in [-1.0, 1.0]:
		_block(Vector3(0.95, frame_height, 0.95), Vector3(sx * pillar_spread, frame_height * 0.5, 0), stone)
		_block(Vector3(1.4, 0.5, 1.4), Vector3(sx * pillar_spread, 0.25, 0), stone)
		_block(Vector3(1.3, 0.4, 1.3), Vector3(sx * pillar_spread, frame_height - 0.2, 0), stone)
	_block(Vector3(pillar_spread * 2 + 1.6, 0.9, 1.15), Vector3(0, frame_height + 0.45, 0), stone)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0, frame_height - 0.05, 0)
	add_child(_pivot)
	var axle := CylinderMesh.new()
	axle.top_radius = 0.16
	axle.bottom_radius = 0.16
	axle.height = pillar_spread * 2
	var am := MeshInstance3D.new()
	am.mesh = axle
	am.material_override = bronze
	am.rotation.z = PI / 2
	_pivot.add_child(am)

	var bell := MeshInstance3D.new()
	bell.mesh = _lathe(PROFILE, 56)
	bell.material_override = _glow_mat
	bell.position = Vector3(0, -0.35, 0)
	_pivot.add_child(bell)
	var crown := TorusMesh.new()
	crown.inner_radius = 0.18
	crown.outer_radius = 0.36
	var cm := MeshInstance3D.new()
	cm.mesh = crown
	cm.material_override = bronze
	cm.rotation.x = PI / 2
	cm.position = Vector3(0, -0.15, 0)
	_pivot.add_child(cm)

	# Clapper
	var clapper := SphereMesh.new()
	clapper.radius = 0.38
	clapper.height = 0.76
	var cl := MeshInstance3D.new()
	cl.mesh = clapper
	cl.material_override = bronze
	cl.position = Vector3(0, -3.3, 0)
	_pivot.add_child(cl)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.35)
	_light.light_energy = 0.0
	_light.omni_range = 30.0
	_light.position = Vector3(0, frame_height - 2.5, 0)
	add_child(_light)

	# Trigger: touching the bell anywhere rings it.
	var area := Area3D.new()
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 2.7
	cs.shape = sph
	area.add_child(cs)
	area.position = Vector3(0, frame_height - 2.4, 0)
	add_child(area)
	area.body_entered.connect(func(b):
		if b is RigidBody3D and not _done:
			_done = true
			ring(1.0)
			rung.emit()
	)


func ring(strength: float) -> void:
	_swing_vel += 1.1 * strength
	_glow = maxf(_glow, strength)


func _process(delta: float) -> void:
	_swing_vel += (-_swing * 9.0 - _swing_vel * 0.35) * delta
	_swing += _swing_vel * delta
	_pivot.rotation.x = _swing * 0.35
	var target := 0.22 if _done else 0.0
	_glow = move_toward(_glow, target, delta * 0.35)
	_glow_mat.emission_energy_multiplier = _glow * 1.6
	_light.light_energy = _glow * 6.0


func _block(size: Vector3, pos: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 3
	body.position = pos
	body.add_to_group("stone")
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)


## Revolve a 2D profile (x = radius, y = height) around the Y axis.
static func _lathe(profile: Array, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var normals: Array[Vector2] = []
	for i in n:
		var a: Vector2 = profile[maxi(i - 1, 0)]
		var b: Vector2 = profile[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		normals.append(Vector2(-t.y, t.x))
	for i in n - 1:
		for s in segments:
			var a0 := TAU * s / segments
			var a1 := TAU * (s + 1) / segments
			var quad := [[i, a0], [i + 1, a0], [i + 1, a1], [i, a1]]
			var verts: Array[Vector3] = []
			var norms: Array[Vector3] = []
			for q in quad:
				var p: Vector2 = profile[q[0]]
				var nn: Vector2 = normals[q[0]]
				var ang: float = q[1]
				verts.append(Vector3(sin(ang) * p.x, p.y, cos(ang) * p.x))
				norms.append(Vector3(sin(ang) * nn.x, nn.y, cos(ang) * nn.x).normalized())
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(norms[idx])
				st.add_vertex(verts[idx])
	return st.commit()
