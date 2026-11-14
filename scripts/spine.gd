@tool
extends Node3D
## LAST REBOUND: the tower's stone spine. It's built from stacked drums, rising out of the abyss.
## Each drum is its own body, so the lower tower can crumble away.

@export var top_y: float = 74.7:
	set(v):
		top_y = v
		_rebuild()
@export var bottom_y: float = -45.0
@export var drum_height: float = 3.0
@export var seed_value: int = 4

var _drums: Array[StaticBody3D] = []
var _rng := RandomNumberGenerator.new()
var _built_top := 0.0
var _count := 0

static var _stone: StandardMaterial3D
static var _band: StandardMaterial3D
static var _window: StandardMaterial3D


func _ready() -> void:
	_rebuild()


func collapse_below(cut_y: float, base_delay: float = 0.0) -> void:
	for d in _drums:
		var y := d.position.y
		if y >= cut_y:
			continue
		var delay := base_delay + clampf((cut_y - y) * 0.018, 0.0, 1.6) + randf() * 0.15
		var spin := Vector3(randf_range(-1.2, 1.2), randf_range(-0.6, 0.6), randf_range(-1.2, 1.2))
		var drift := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.06
		var tw := d.create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func(): d.collision_layer = 0)
		tw.tween_method(func(k: float):
			d.position.y -= k * k * 1.5
			d.position += drift * k
			d.rotation = spin * k * 0.5
		, 0.0, 1.0, 3.8)
		tw.tween_callback(d.hide)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.name.begins_with("_gen"):
			remove_child(c)
			c.queue_free()
	_drums.clear()
	_materials()
	_rng.seed = seed_value
	_count = 0
	_built_top = bottom_y
	_build_until(top_y)


## Endless mode: keep stacking drums upward.
func extend_to(y_top: float) -> void:
	if y_top > _built_top + 0.01:
		_build_until(y_top)


## Endless mode: hide drums far below (they're behind the abyss anyway).
func cull_below(y: float) -> void:
	for d in _drums:
		if d.visible and d.position.y < y:
			d.visible = false
			d.collision_layer = 0


func get_top() -> float:
	return _built_top


func _build_until(top: float) -> void:
	var rng := _rng
	var y := _built_top
	var i := _count
	while y < top - 0.01:
		var h := minf(drum_height, top - y)
		var t := clampf(y / 75.0, 0.0, 1.0)
		var r := lerpf(1.65, 1.15, t) + rng.randf_range(-0.07, 0.07)
		var body := StaticBody3D.new()
		body.name = "_genDrum%d" % i
		body.collision_layer = 3  # layer 2 is "camera blockers"
		body.position = Vector3(0, y + h * 0.5, 0)
		body.rotation.y = rng.randf() * TAU
		body.add_to_group("stone")
		add_child(body)

		var cyl := CylinderMesh.new()
		cyl.top_radius = r * 0.97
		cyl.bottom_radius = r
		cyl.height = h - 0.18
		cyl.radial_segments = 14  # slightly faceted, hand-cut
		cyl.rings = 1
		_mesh(body, cyl, _stone, Vector3.ZERO)
		var band := CylinderMesh.new()
		band.top_radius = r + 0.12
		band.bottom_radius = r + 0.12
		band.height = 0.2
		band.radial_segments = 14
		_mesh(body, band, _band, Vector3(0, h * 0.5 - 0.1, 0))

		# Some drums have lit window slits: someone, somewhere, is still inside.
		if y > 2.0 and rng.randf() < 0.45:
			for w in range(rng.randi_range(1, 2)):
				var a := rng.randf() * TAU
				var slit := BoxMesh.new()
				slit.size = Vector3(0.18, h * 0.42, 0.05)
				var mi := _mesh(body, slit, _window, Vector3(sin(a) * (r - 0.01), rng.randf_range(-0.3, 0.3), cos(a) * (r - 0.01)))
				mi.rotation.y = a

		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = h
		col.shape = shape
		body.add_child(col)
		_drums.append(body)
		y += h
		i += 1
	_built_top = y
	_count = i


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _materials() -> void:
	if _stone:
		return
	_stone = preload("res://scripts/platform.gd").make_stone_material()
	_band = StandardMaterial3D.new()
	_band.albedo_color = Color(0.05, 0.05, 0.055)
	_band.roughness = 0.8
	_window = StandardMaterial3D.new()
	_window.albedo_color = Color(1.0, 0.6, 0.25)
	_window.emission_enabled = true
	_window.emission = Color(1.0, 0.5, 0.18)
	_window.emission_energy_multiplier = 2.2
