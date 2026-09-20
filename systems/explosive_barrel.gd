extends Node

## Red barrels go up from a shot, a hard slam, or another blast.
@export var impact_explode_speed: float = 5.8

const BLAST: PackedScene = preload("res://systems/isle_blast.tscn")

var _body: RigidBody3D
var _armed: bool = false
var _exploded: bool = false


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		return
	_body.add_to_group("explosive_barrel")
	if "display_name" in _body:
		_body.display_name = "Oil cask"
	call_deferred("_apply_wooden_oil_look")
	var health: Node = _body.get_node_or_null("HealthAttribute")
	if health:
		health.value_max = 1.0
		health.value_start = 1.0
		health.value_current = 1.0
		health.sound_on_death = null
		health.sound_on_hit = null
		health.sound_on_damage_taken = null
		var death_scenes: Array[PackedScene] = []
		death_scenes.append(BLAST)
		health.spawn_on_death = death_scenes
		if health.has_signal("death") and not health.death.is_connected(_on_death):
			health.death.connect(_on_death)
	if not _body.body_entered.is_connected(_on_body_entered):
		_body.body_entered.connect(_on_body_entered)
	await get_tree().create_timer(0.45).timeout
	_armed = true


func _apply_wooden_oil_look() -> void:
	for child in _body.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.48, 0.3, 0.14)
	wood.roughness = 0.92
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.15, 0.13)
	iron.metallic = 0.55
	iron.roughness = 0.5
	var oil := StandardMaterial3D.new()
	oil.albedo_color = Color(0.1, 0.07, 0.03)
	oil.roughness = 0.18
	var stave := CylinderMesh.new()
	stave.top_radius = 0.36
	stave.bottom_radius = 0.4
	stave.height = 0.98
	stave.radial_segments = 18
	stave.material = wood
	var stave_mi := MeshInstance3D.new()
	stave_mi.mesh = stave
	_body.add_child(stave_mi)
	for band_y in [-0.32, 0.0, 0.32]:
		var band := CylinderMesh.new()
		band.top_radius = 0.41
		band.bottom_radius = 0.41
		band.height = 0.055
		band.radial_segments = 16
		band.material = iron
		var band_mi := MeshInstance3D.new()
		band_mi.mesh = band
		band_mi.position.y = band_y
		_body.add_child(band_mi)
	var lid := CylinderMesh.new()
	lid.top_radius = 0.34
	lid.bottom_radius = 0.34
	lid.height = 0.04
	lid.radial_segments = 16
	lid.material = oil
	var lid_mi := MeshInstance3D.new()
	lid_mi.mesh = lid
	lid_mi.position.y = 0.48
	_body.add_child(lid_mi)


func _on_death(_attribute_name: String = "", _value_current: float = 0.0, _value_max: float = 0.0) -> void:
	_exploded = true


func _on_body_entered(other: Node) -> void:
	if _exploded or not _armed:
		return
	if other is CogitoProjectile:
		call_deferred("_kill")
		return
	var rel: Vector3 = _body.linear_velocity
	if other is RigidBody3D:
		rel -= (other as RigidBody3D).linear_velocity
	elif other is CharacterBody3D:
		rel -= (other as CharacterBody3D).velocity
	if rel.length() >= impact_explode_speed:
		call_deferred("_kill")


func _kill() -> void:
	if _exploded or not is_instance_valid(_body):
		return
	_exploded = true
	var health: Node = _body.get_node_or_null("HealthAttribute")
	if health:
		health.subtract(health.value_max + 1.0)
	else:
		var blast: Node3D = BLAST.instantiate() as Node3D
		blast.global_position = _body.global_position
		_body.get_tree().current_scene.add_child(blast)
		_body.queue_free()
