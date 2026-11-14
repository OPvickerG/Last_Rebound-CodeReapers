extends RigidBody3D
## LAST REBOUND: the ember. A real physics body (gravity, collisions, rolling, rebound).
##
## The extra rules:
##  * Gongs top up your upward speed on a top hit (see platform.gd).
##  * SLAM (Space, in the air): drive yourself down hard. Landing a slam on a
##    gong launches you higher.

signal impacted(speed: float, collider: Node, top_hit: bool)
signal slammed

@export var move_force: float = 32.0
@export var max_horizontal_speed: float = 11.0
@export var camera_path: NodePath
@export var squash_amount: float = 0.35
@export var slam_speed: float = 26.0
@export var slam_bonus: float = 1.22

var camera: Camera3D
var controls_enabled := true
## Steering from the on-screen joystick (phones). Used when no keys are pressed.
var touch_vector := Vector2.ZERO
var slam_active := false
## True if the most recent top landing was a slam (read by the XP system).
var last_landing_was_slam := false

var _pending_respawn := false
var _respawn_position := Vector3.ZERO
var _impact_cooldown := 0.0
var _prev_velocity := Vector3.ZERO
var _squash := 0.0
var _airtime := 0.0
## Fastest recent fall speed. Continuous collision can zero the velocity in the
## same step as the hit, so the impact is measured from this instead.
var _recent_fall := 0.0
var _t := 0.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var glow: OmniLight3D = $Glow
@onready var trail: GPUParticles3D = $Trail


func _ready() -> void:
	if camera_path != NodePath():
		camera = get_node(camera_path) as Camera3D
	if OS.has_feature("mobile"):
		glow.shadow_enabled = false  # omni shadows are expensive on phones
	contact_monitor = true
	max_contacts_reported = 4


## During the intro the ember falls straight through the tower.
func set_intro(on: bool) -> void:
	collision_mask = 0 if on else 1
	collision_layer = 0 if on else 1
	controls_enabled = not on


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		try_slam()


## Slam: only in the air, once per bounce.
func try_slam() -> void:
	if controls_enabled and _airtime > 0.12 and not slam_active:
		slam_active = true
		var v := linear_velocity
		v.y = minf(v.y, -slam_speed)
		linear_velocity = v
		slammed.emit()


func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)
	_airtime += delta

	if camera == null or not controls_enabled:
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir.length_squared() < 0.01:
		input_dir = touch_vector.limit_length(1.0)
	var forward := -camera.global_basis.z
	var right := camera.global_basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	var direction := (right * input_dir.x - forward * input_dir.y).normalized()
	if direction.length_squared() > 0.01:
		apply_central_force(direction * move_force)

	# Limit horizontal speed without touching the vertical bounce.
	var horizontal := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if horizontal.length() > max_horizontal_speed:
		horizontal = horizontal.normalized() * max_horizontal_speed
		linear_velocity.x = horizontal.x
		linear_velocity.z = horizontal.z


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_respawn:
		_pending_respawn = false
		state.transform = Transform3D(Basis(), _respawn_position)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_prev_velocity = Vector3.ZERO
		slam_active = false
		reset_physics_interpolation.call_deferred()
		return

	if state.get_contact_count() > 0:
		_airtime = 0.0
	_recent_fall = maxf(_recent_fall * 0.8, -_prev_velocity.y)

	for i in state.get_contact_count():
		if _impact_cooldown > 0.0:
			break
		var collider = state.get_contact_collider_object(i) as Node3D
		if collider == null:
			continue
		var normal := state.get_contact_local_normal(i)
		var top_hit: bool = absf(normal.y) > 0.6 and state.transform.origin.y > collider.global_position.y
		var impact_speed := absf(_prev_velocity.dot(normal))
		if top_hit:
			impact_speed = maxf(impact_speed, _recent_fall)
		var on_gong: bool = top_hit and collider.has_method("get_launch_speed")
		# Gongs never let you rest: any top contact launches. Elsewhere, ignore rolling contacts.
		if impact_speed < 2.0 and not on_gong:
			continue

		_impact_cooldown = 0.12
		_recent_fall = 0.0

		if top_hit and collider.has_method("get_launch_speed"):
			# The engine has already applied the material bounce. The gong only tops it up.
			var launch: float = collider.get_launch_speed()
			if slam_active:
				launch *= slam_bonus
			var v := state.linear_velocity
			v.y = maxf(v.y, launch)
			state.linear_velocity = v
			collider.on_player_landed.call_deferred(self, impact_speed)
		if top_hit:
			_squash = clampf(impact_speed / 22.0, 0.15, 1.0)
			last_landing_was_slam = slam_active
			slam_active = false
		impacted.emit.call_deferred(impact_speed, collider, top_hit)
		break

	_prev_velocity = state.linear_velocity


func _process(delta: float) -> void:
	_t += delta
	# Squash along world-up on impact (visual only; the sphere's spin is invisible anyway).
	_squash = move_toward(_squash, 0.0, delta * 4.0)
	var s := sin(_squash * PI) * squash_amount * _squash
	var stretch := clampf(absf(linear_velocity.y) / 40.0, 0.0, 0.12)
	var y_scale := 1.0 - s + stretch
	var xz_scale := 1.0 + s * 0.6 - stretch * 0.5
	mesh.global_transform = Transform3D(Basis.from_scale(Vector3(xz_scale, y_scale, xz_scale)), global_position)
	# The ember breathes; a slam makes it flare.
	var flare := 2.0 if slam_active else 0.0
	glow.light_energy = 3.0 + sin(_t * 11.0) * 0.25 + sin(_t * 4.3) * 0.35 + flare
	trail.amount_ratio = clampf(0.35 + linear_velocity.length() / 25.0, 0.35, 1.0)


## Ember colour (unlocked with Endless XP).
func apply_skin(core: Color, light: Color) -> void:
	var mat := mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if mat:
		mat.emission = core
	glow.light_color = light
	var pm := trail.process_material as ParticleProcessMaterial
	if pm:
		var g := Gradient.new()
		g.set_color(0, core.lerp(Color.WHITE, 0.55))
		g.add_point(0.4, core)
		g.set_color(g.get_point_count() - 1, Color(core.darkened(0.6), 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt


func respawn(at: Vector3) -> void:
	_respawn_position = at
	_pending_respawn = true
	sleeping = false
