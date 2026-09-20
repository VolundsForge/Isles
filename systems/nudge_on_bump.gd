extends Node

## Applies a shove when the player walks into the parent RigidBody3D.
@export var push_strength: float = 4.0

@onready var _body: RigidBody3D = get_parent() as RigidBody3D


func _physics_process(_delta: float) -> void:
	if _body == null or not _body.contact_monitor:
		return
	var player := CogitoSceneManager._current_player_node
	if player == null:
		return
	for other in _body.get_colliding_bodies():
		if other != player:
			continue
		var vel: Vector3 = player.velocity
		vel.y = 0.0
		var speed := vel.length()
		if speed < 0.35:
			continue
		var dir: Vector3 = _body.global_position - player.global_position
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			dir = vel
		_body.sleeping = false
		_body.apply_central_force(dir.normalized() * speed * push_strength * _body.mass)
