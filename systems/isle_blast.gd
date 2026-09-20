extends Node3D

## Blast centered on this node. Throws physics props, hurts/kills living NPCs by range, flings ragdolls.
@export var radius: float = 7.0
@export var kill_radius: float = 5.0
@export var ragdoll_radius: float = 7.0
@export var force: float = 36.0
@export var damage: float = 12.0

const VFX: PackedScene = preload("res://addons/cogito/Assets/VFX/Explosion_01/Explosion.tscn")


func _ready() -> void:
	var vfx: Node = VFX.instantiate()
	vfx.set("damage_amount", 0.0)
	vfx.set("damage_force", 0.0)
	vfx.set("monitoring", false)
	vfx.set("monitorable", false)
	add_child(vfx)
	call_deferred("_detonate")


func _detonate() -> void:
	var origin: Vector3 = global_position
	_blast_props_and_people(origin)
	await get_tree().physics_frame
	if is_instance_valid(self):
		_throw_ragdolls(origin)
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(self):
		queue_free()


func _blast_props_and_people(origin: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var targets: Array[Node] = []
	_gather(scene, origin, targets)
	var seen: Dictionary = {}
	for node in targets:
		if node == null or seen.has(node) or not is_instance_valid(node):
			continue
		seen[node] = true
		_affect(node, origin)


func _gather(node: Node, origin: Vector3, out: Array[Node]) -> void:
	if node is RigidBody3D or node is CogitoNPC or node is CogitoPlayer:
		if node is Node3D and (node as Node3D).global_position.distance_to(origin) <= radius + 1.5:
			out.append(node)
	for child in node.get_children():
		_gather(child, origin, out)


func _falloff(dist: float) -> float:
	return clampf(1.0 - dist / radius, 0.12, 1.0)


func _affect(collider: Node, origin: Vector3) -> void:
	if collider == null or not is_instance_valid(collider) or collider.is_queued_for_deletion():
		return
	if collider is PhysicalBone3D:
		return
	var pos: Vector3 = (collider as Node3D).global_position if collider is Node3D else origin
	var offset: Vector3 = pos - origin
	var dist: float = offset.length()
	if dist > radius:
		return
	var falloff: float = _falloff(dist)
	var dir: Vector3 = Vector3.UP if offset.length_squared() < 0.0001 else offset.normalized()
	var impulse: Vector3 = dir * force * falloff

	if collider.is_in_group("explosive_barrel") and dist > 0.2:
		var health: Node = collider.get_node_or_null("HealthAttribute")
		var delay: float = maxf(dist * 0.05, 0.05)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(collider) and health:
				health.subtract(99.0)
		)

	if collider is RigidBody3D:
		var body := collider as RigidBody3D
		if "freeze" in body:
			body.freeze = false
		body.sleeping = false
		body.apply_central_impulse(impulse * maxf(body.mass, 0.35) * 0.53)
		body.apply_impulse(impulse * 0.08, Vector3(0, 0.15, 0.08))
		return

	if collider is CogitoNPC:
		_hurt_live_npc(collider as CogitoNPC, dist, falloff, dir, impulse, origin)
		return

	if collider is CogitoPlayer:
		var player := collider as CogitoPlayer
		player.apply_external_force(impulse)
		player.decrease_attribute("health", damage * falloff * 0.35)


func _hurt_live_npc(npc: CogitoNPC, dist: float, falloff: float, dir: Vector3, impulse: Vector3, origin: Vector3) -> void:
	if not is_instance_valid(npc) or npc.is_queued_for_deletion():
		return
	var dmg: float
	if dist <= kill_radius:
		dmg = 999.0
		npc.set_meta("blast_origin", origin)
		npc.set_meta("blast_force", force * maxf(falloff, 0.45))
		# Don't CharacterBody-knockback on a lethal blast — that looks like a slow topple.
	else:
		dmg = maxf(damage * falloff, 2.5)
		npc.apply_knockback(impulse * 1.4)
	npc.damage_received.emit(dmg, dir, origin)


func _throw_ragdolls(origin: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("Persist"):
		if not is_instance_valid(node) or not (node is CogitoRagdoll):
			continue
		var ragdoll := node as CogitoRagdoll
		if ragdoll.global_position.distance_to(origin) > ragdoll_radius + 2.0:
			continue
		_impulse_ragdoll(ragdoll, origin)


func _impulse_ragdoll(ragdoll: CogitoRagdoll, origin: Vector3) -> void:
	var RageRagdoll = load("res://characters/rage_ragdoll.gd")
	var ctrl: Node = RageRagdoll.attach(ragdoll)
	if ctrl and ctrl.has_method("apply_blast"):
		ctrl.apply_blast(origin, force)
