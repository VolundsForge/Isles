extends Node

## Walks the host NPC between Marker3D waypoints. Does not need a navmesh.

@export var waypoint_parent: NodePath
@export var arrive_distance: float = 0.55

var _points: Array[Node3D] = []
var _index: int = 0


func _ready() -> void:
	var npc := get_parent()
	if not npc.is_node_ready():
		await npc.ready
	var sm := npc.get_node_or_null("NPC_State_Machine")
	if sm:
		sm.process_mode = Node.PROCESS_MODE_DISABLED
	var root := get_node_or_null(waypoint_parent)
	if root == null:
		return
	for child in root.get_children():
		if child is Node3D:
			_points.append(child)


func _physics_process(delta: float) -> void:
	if _points.size() < 2:
		return
	var npc := get_parent() as CogitoNPC
	if npc == null or not is_instance_valid(npc):
		return
	var dest: Vector3 = _points[_index].global_position
	var offset: Vector3 = dest - npc.global_position
	offset.y = 0.0
	if offset.length() <= arrive_distance:
		_index = (_index + 1) % _points.size()
		return
	var dir: Vector3 = offset.normalized()
	if not npc.is_on_floor():
		npc.velocity += npc.get_gravity() * delta
	npc.face_direction(npc.global_position + dir)
	npc.velocity.x = dir.x * npc.move_speed
	npc.velocity.z = dir.z * npc.move_speed
	npc.move_and_slide()
	npc.update_animations(delta)
