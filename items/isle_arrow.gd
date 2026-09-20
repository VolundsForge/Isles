extends CogitoProjectile

## Short grace so the shot clears the bow, then pin into whatever it hits.
## Reparent/freeze is deferred — doing it inside a physics callback freezes the game.

var _stuck: bool = false


func _ready() -> void:
	super._ready()
	stick_on_impact = false
	# Player-shot arrows ignore only the shooter, never the world.
	var player := CogitoSceneManager._current_player_node
	if player:
		call("add_collision_exception_with", player)


func _on_body_entered(collider: Node) -> void:
	if _stuck or collider == null:
		return
	if collider.is_in_group("Player"):
		return
	if collider is CogitoWieldable:
		return
	if collider is CogitoProjectile:
		return
	# Oil casks explode on their own; pinning to a dying body hangs the physics step.
	if collider.is_in_group("explosive_barrel"):
		return
	if collider is PhysicalBone3D:
		call_deferred("_pin_or_embed_ragdoll", collider)
		return
	if _is_solid_world(collider):
		call_deferred("_pin_if_against_surface", collider)
		return
	_hurt(collider)
	call_deferred("_embed_in", collider)


func _is_solid_world(node: Node) -> bool:
	if node is PhysicalBone3D or node is CogitoNPC or node is CogitoPlayer:
		return false
	if node is RigidBody3D and not bool(node.get("freeze")):
		return false
	return node is CollisionObject3D or node is CSGShape3D


func _first_colliding_bone() -> PhysicalBone3D:
	var bodies: Array = call("get_colliding_bodies")
	for body in bodies:
		if body is PhysicalBone3D:
			return body as PhysicalBone3D
	return null


func _pin_if_against_surface(wall: Node) -> void:
	if _stuck or not is_instance_valid(self):
		return
	var bone := _first_colliding_bone()
	if bone == null:
		_embed_in(wall)
		return
	var dir: Vector3 = direction if direction != null else -global_transform.basis.z
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	_lock_arrow_in_world(global_position, dir)
	_joint_bone_to_world(bone, global_position)
	var pull: Vector3 = global_position - bone.global_position
	if pull.length_squared() > 0.0001:
		bone.call("apply_central_impulse", pull.normalized() * 14.0)


func _pin_or_embed_ragdoll(bone: Node) -> void:
	if _stuck or not is_instance_valid(self) or not is_instance_valid(bone):
		return
	if _pin_ragdoll_to_surface(bone as PhysicalBone3D):
		return
	_embed_in(bone)


func _pin_ragdoll_to_surface(bone: PhysicalBone3D) -> bool:
	var dir: Vector3 = direction if direction != null else Vector3.ZERO
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position - dir * 0.08
	var to: Vector3 = global_position + dir * 1.15
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.hit_from_inside = true
	query.exclude = _exclude_rids(bone)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var wall: Object = hit.get("collider")
	if wall == null or wall == bone or wall is PhysicalBone3D:
		return false
	if wall is RigidBody3D and not bool(wall.get("freeze")):
		return false
	var at: Vector3 = hit.get("position", global_position)
	_lock_arrow_in_world(at, dir)
	_joint_bone_to_world(bone, at)
	var pull: Vector3 = at - bone.global_position
	if pull.length_squared() > 0.0001:
		bone.call("apply_central_impulse", pull.normalized() * 14.0)
	return true


func _exclude_rids(bone: PhysicalBone3D) -> Array[RID]:
	var rids: Array[RID] = []
	var self_rid: Variant = call("get_rid")
	if self_rid is RID:
		rids.append(self_rid)
	var player := CogitoSceneManager._current_player_node
	if player is CollisionObject3D:
		rids.append((player as CollisionObject3D).get_rid())
	var sim: Node = bone.get_parent()
	if sim:
		for child in sim.get_children():
			if child is PhysicalBone3D:
				rids.append((child as PhysicalBone3D).get_rid())
	return rids


func _lock_arrow_in_world(at: Vector3, dir: Vector3) -> void:
	_stuck = true
	set("linear_velocity", Vector3.ZERO)
	set("angular_velocity", Vector3.ZERO)
	set("gravity_scale", 0.0)
	set("freeze", true)
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape:
		shape.disabled = true
	var lifespan := get_node_or_null("Lifespan")
	if lifespan is Timer:
		(lifespan as Timer).stop()
	var look: Vector3 = at + dir
	if look.distance_squared_to(global_position) > 0.0001:
		look_at(look, Vector3.UP)
	global_position = at - dir * 0.22


func _joint_bone_to_world(bone: PhysicalBone3D, at: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var anchor := StaticBody3D.new()
	anchor.name = "ArrowPin"
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	scene.add_child(anchor)
	anchor.global_position = at
	var joint := PinJoint3D.new()
	joint.name = "ArrowPinJoint"
	scene.add_child(joint)
	joint.global_position = at
	joint.node_a = bone.get_path()
	joint.node_b = anchor.get_path()


func _hurt(collider: Node) -> void:
	var target := _find_damageable(collider)
	if target == null:
		return
	var dir: Vector3 = direction if direction != null else Vector3.FORWARD
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	var amount: float = float(damage_amount)
	if amount <= 0.0:
		amount = 4.0
	target.damage_received.emit(amount, dir, global_position)


func _find_damageable(node: Node) -> Node:
	var current := node
	while current:
		if current.has_signal("damage_received"):
			return current
		current = current.get_parent()
	return null


func _embed_in(collider: Node) -> void:
	if _stuck or not is_instance_valid(self) or not is_instance_valid(collider):
		return
	if collider.is_in_group("explosive_barrel"):
		return
	_stuck = true
	set("linear_velocity", Vector3.ZERO)
	set("angular_velocity", Vector3.ZERO)
	set("gravity_scale", 0.0)
	set("freeze", true)
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape:
		shape.disabled = true
	var lifespan := get_node_or_null("Lifespan")
	if lifespan is Timer:
		(lifespan as Timer).stop()
	var host: Node = collider
	if host is CollisionShape3D and host.get_parent() != null:
		host = host.get_parent()
	if not is_instance_valid(host) or not (host is Node3D):
		return
	var xf := global_transform
	var dir: Vector3 = direction if direction != null else -xf.basis.z
	if dir.length_squared() > 0.0001:
		xf.origin += dir.normalized() * 0.07
	reparent(host, true)
	global_transform = xf
