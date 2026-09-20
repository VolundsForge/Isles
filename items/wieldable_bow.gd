extends CogitoWieldable

@export var projectile_scene: PackedScene
@export var projectile_velocity: float = 32.0
@export var ads_fov: float = 62.0
@export var default_position: Vector3 = Vector3(0.28, -0.12, -0.42)
@export var sound_primary_use: AudioStream

@onready var arrow_point: Node3D = %ArrowPoint


func _ready() -> void:
	super._ready()
	if wieldable_mesh:
		wieldable_mesh.show()


func action_primary(_passed_item_reference: InventoryItemPD, _is_released: bool) -> void:
	if _is_released:
		return
	if animation_player and animation_player.is_playing():
		return
	var item := _passed_item_reference as WieldableItemPD
	if item == null:
		return
	if item.charge_current <= 0:
		item.send_empty_hint()
		return
	if animation_player:
		animation_player.play(anim_action_primary)
	if audio_stream_player_3d and sound_primary_use:
		audio_stream_player_3d.stream = sound_primary_use
		audio_stream_player_3d.play()
	item.subtract(1)
	_spawn_arrow(item)


func _spawn_arrow(item: WieldableItemPD) -> void:
	if projectile_scene == null or arrow_point == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_hit: Vector3 = player_interaction_component.get_camera_collision()
	var origin: Vector3 = arrow_point.global_position
	var direction: Vector3 = (camera_hit - origin).normalized()
	if direction.length_squared() < 0.0001:
		direction = -camera.global_transform.basis.z
	var projectile: Node3D = projectile_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin
	var up: Vector3 = Vector3.UP
	if absf(direction.dot(up)) > 0.95:
		up = camera.global_transform.basis.x
	projectile.look_at(origin + direction, up)
	if projectile is CogitoProjectile:
		(projectile as CogitoProjectile).damage_amount = item.wieldable_damage
		(projectile as CogitoProjectile).direction = direction
	if projectile is RigidBody3D:
		(projectile as RigidBody3D).linear_velocity = direction * projectile_velocity
		var player := CogitoSceneManager._current_player_node
		if player:
			(projectile as RigidBody3D).add_collision_exception_with(player)


func action_secondary(is_released: bool) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var tween := get_tree().create_tween()
	if is_released:
		tween.tween_property(camera, "fov", 75.0, 0.2)
		tween.parallel().tween_property(self, "position", default_position, 0.2)
		player_interaction_component.update_crosshair.emit(true)
	else:
		tween.tween_property(camera, "fov", ads_fov, 0.2)
		tween.parallel().tween_property(self, "position", Vector3(0.0, default_position.y, default_position.z), 0.2)
		player_interaction_component.update_crosshair.emit(false)


func reload() -> void:
	if animation_player:
		animation_player.play(anim_reload)


func change_ammo(_index: int) -> void:
	pass
