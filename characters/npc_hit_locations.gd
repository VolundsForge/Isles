extends Node

## Maps arrow hits to head / torso / arms / legs and drives clutching or a limp.

const WoundMod := preload("res://characters/npc_wound_modifier.gd")
const RageRagdoll := preload("res://characters/rage_ragdoll.gd")

var _npc: CogitoNPC
var _mod
var _base_walk: float = 2.0
var _base_move: float = 2.0
var _base_sprint: float = 4.0
var _last_dir: Vector3 = Vector3.FORWARD
var _last_limb: int = 0


func _ready() -> void:
	_npc = get_parent() as CogitoNPC
	if _npc == null:
		return
	if not _npc.is_node_ready():
		await _npc.ready
	var skel: Skeleton3D = _npc.get_node_or_null("Rig/Skeleton3D") as Skeleton3D
	if skel == null:
		return
	_mod = WoundMod.new()
	_mod.name = "WoundModifier"
	skel.add_child(_mod)
	_base_walk = _npc.walk_speed
	_base_move = _npc.move_speed
	_base_sprint = _npc.sprint_speed
	if not _npc.damage_received.is_connected(_on_hit):
		_npc.damage_received.connect(_on_hit)
	var health: Node = _npc.get_node_or_null("CogitoHealthAttribute")
	if health and health.has_signal("death") and not health.death.is_connected(_on_death):
		health.death.connect(_on_death)


func _on_hit(amount: float, dir: Vector3 = Vector3.ZERO, pos: Vector3 = Vector3.ZERO) -> void:
	if _npc == null or _mod == null or not is_instance_valid(_npc):
		return
	var limb: int = _mod.classify_hit(_npc, pos, dir)
	_last_dir = dir
	_last_limb = limb
	_mod.set_wound(limb, pos)
	if _npc.animation_tree:
		_npc.animation_tree.set("parameters/Transition/transition_request", "hit")
	var legs := limb == WoundMod.Limb.LEFT_LEG or limb == WoundMod.Limb.RIGHT_LEG
	if legs:
		_npc.walk_speed = _base_walk * 0.42
		_npc.move_speed = _base_move * 0.42
		_npc.sprint_speed = minf(_base_sprint * 0.5, _npc.walk_speed + 0.4)
	else:
		_npc.walk_speed = _base_walk * 0.85
		_npc.move_speed = _base_move * 0.85
		_npc.sprint_speed = _base_sprint * 0.85


func _on_death(_attribute_name: String = "", _value_current: float = 0.0, _value_max: float = 0.0) -> void:
	var pos: Vector3 = _npc.global_position if is_instance_valid(_npc) else Vector3.ZERO
	var dir: Vector3 = _last_dir
	var limb: int = _last_limb
	var blast_origin: Variant = _npc.get_meta("blast_origin") if _npc.has_meta("blast_origin") else null
	var blast_force: float = float(_npc.get_meta("blast_force")) if _npc.has_meta("blast_force") else 0.0
	await get_tree().process_frame
	await get_tree().physics_frame
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("Persist"):
		if not (node is CogitoRagdoll) or not is_instance_valid(node):
			continue
		if node.global_position.distance_to(pos) > 4.0:
			continue
		var ctrl: Node = RageRagdoll.attach(node)
		if ctrl == null:
			break
		if blast_origin is Vector3 and ctrl.has_method("apply_blast"):
			ctrl.apply_blast(blast_origin, maxf(blast_force, 36.0))
		elif ctrl.has_method("kick_from_hit"):
			ctrl.kick_from_hit(dir, limb)
		break
