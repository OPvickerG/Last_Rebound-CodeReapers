extends Node3D
## LAST REBOUND: an orbit camera that follows the ember and avoids the stone, with cinematic modes.

enum Mode { FOLLOW, CINEMATIC, ORBIT }

@export var target: Node3D
@export var follow_speed: float = 8.0
@export var mouse_sensitivity: float = 0.003
@export var distance: float = 9.0
@export var min_pitch: float = -1.25
@export var max_pitch: float = 0.6

var mode: Mode = Mode.FOLLOW
var yaw: float = 0.0
var pitch: float = -0.32
var orbit_center := Vector3.ZERO
var orbit_radius := 24.0
var orbit_height := 4.0

var _shake := 0.0
var _orbit_angle := 0.0

@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	snap()


func _unhandled_input(event: InputEvent) -> void:
	# Touches also arrive as fake mouse events; the touch controls handle those instead.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if mode == Mode.FOLLOW and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, min_pitch, max_pitch)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_shake = move_toward(_shake, 0.0, delta * 2.2)
	var amount := _shake * _shake * 0.4
	var jitter := Vector3(randf_range(-amount, amount), randf_range(-amount, amount), randf_range(-amount, amount))

	if mode == Mode.ORBIT:
		_orbit_angle += delta * 0.1
		global_position = orbit_center
		var p := orbit_center + Vector3(sin(_orbit_angle) * orbit_radius, orbit_height, cos(_orbit_angle) * orbit_radius)
		cam.global_position = p + jitter
		cam.look_at(orbit_center + Vector3(0, 2, 0))
		cam.fov = lerpf(cam.fov, 62.0, delta)
		return

	var speed := follow_speed if mode == Mode.FOLLOW else 14.0
	global_position = global_position.lerp(target.global_position, clampf(speed * delta, 0.0, 1.0))
	rotation = Vector3(0, yaw, 0)

	# Orbit offset from pitch, then pull in if stone is in the way.
	var local := Vector3(0, -sin(pitch) * distance + 1.0, cos(pitch) * distance)
	var desired := global_transform * local
	var from := global_position + Vector3(0, 0.6, 0)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, desired, 2)
	var hit := space.intersect_ray(q)
	if hit:
		desired = hit.position + (from - desired).normalized() * 0.6
	cam.global_position = desired + jitter
	cam.look_at(from + Vector3(0, 0.4, 0))

	# FOV opens up when you're moving fast: speed you can feel.
	var v := (target as RigidBody3D).linear_velocity.length() if target is RigidBody3D else 0.0
	cam.fov = lerpf(cam.fov, 70.0 + clampf(v - 14.0, 0.0, 20.0) * 0.6, clampf(delta * 3.0, 0, 1))


## Orbit by a drag on a touch screen (radians).
func look_delta(rel: Vector2) -> void:
	if mode != Mode.FOLLOW:
		return
	yaw -= rel.x
	pitch = clampf(pitch - rel.y, min_pitch, max_pitch)


## Impact feedback. `strength` is 0..1.
func shake(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.2))


func snap() -> void:
	if target:
		global_position = target.global_position
	reset_physics_interpolation()


func set_cinematic(new_yaw: float, new_pitch: float) -> void:
	mode = Mode.CINEMATIC
	yaw = new_yaw
	pitch = new_pitch


func tween_pitch(to: float, seconds: float) -> void:
	create_tween().tween_property(self, "pitch", to, seconds).set_trans(Tween.TRANS_SINE)


func follow(new_yaw: float) -> void:
	mode = Mode.FOLLOW
	yaw = new_yaw


func orbit(center: Vector3, radius: float, height: float, start_angle: float) -> void:
	mode = Mode.ORBIT
	orbit_center = center
	orbit_radius = radius
	orbit_height = height
	_orbit_angle = start_angle
