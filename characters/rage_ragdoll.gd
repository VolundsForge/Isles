extends Node

## GTA/RAGE-like corpse: heavy torso, loose limbs, ballistic launch, brief flail, then settle.
## Never freeze the body — it stays kickable.

var _bones: Array[PhysicalBone3D] = []
var _age: float = 0.0
var _muscle: float = 1.0
var _settled: bool = false


static func attach(ragdoll: Node) -> Node:
	if ragdoll == null or not is_instance_valid(ragdoll):
		return null
	var existing: Node = ragdoll.get_node_or_null("RageStyle")
	if existing:
		return existing
	var n := Node.new()
	n.name = "RageStyle"
	n.set_script(load("res://characters/rage_ragdoll.gd"))
	ragdoll.add_child(n)
	return n


func _ready() -> void:
	await get_tree().process_frame
	_ensure_ready()


func _ensure_ready() -> void:
	var ragdoll := get_parent()
	if ragdoll == null or not is_instance_valid(ragdoll):
		return
	var sim := _simulator(ragdoll)
	if sim == null:
		return
	if _bones.is_empty():
		_collect_bones(sim)
		_tune_bones()
	if not sim.active:
		sim.active = true
		sim.physical_bones_start_simulation()


func _simulator(ragdoll: Node) -> PhysicalBoneSimulator3D:
	if ragdoll is CogitoRagdoll and (ragdoll as CogitoRagdoll).physical_bone_simulator_3d:
		return (ragdoll as CogitoRagdoll).physical_bone_simulator_3d
	var found: Array[Node] = ragdoll.find_children("*", "PhysicalBoneSimulator3D", true, false)
	if found.is_empty():
		return null
	return found[0] as PhysicalBoneSimulator3D


func _collect_bones(sim: PhysicalBoneSimulator3D) -> void:
	_bones.clear()
	for child in sim.get_children():
		if child is PhysicalBone3D:
			_bones.append(child as PhysicalBone3D)


func _tune_bones() -> void:
	for bone in _bones:
		if not is_instance_valid(bone):
			continue
		var n: String = str(bone.get("bone_name")).to_lower()
		bone.mass = _mass_for(n)
		bone.friction = 0.35
		bone.bounce = 0.18 if _is_core(n) else 0.08
		bone.linear_damp = 0.04
		bone.angular_damp = 0.12
		if "can_sleep" in bone:
			bone.can_sleep = false
		_loosen_joint(bone, n)


func _mass_for(n: String) -> float:
	if "hip" in n or n == "root":
		return 12.0
	if "spine" in n:
		return 7.0
	if "head" in n or "neck" in n:
		return 3.2
	if "thigh" in n:
		return 4.5
	if "shin" in n or "foot" in n:
		return 2.2
	if "upper_arm" in n or "shoulder" in n:
		return 2.4
	if "forearm" in n:
		return 1.4
	if "hand" in n:
		return 0.6
	if "toe" in n or "thumb" in n or "index" in n or "middle" in n or "ring" in n or "pinky" in n:
		return 0.15
	return 1.0


func _is_core(n: String) -> bool:
	return "hip" in n or "spine" in n or n == "root" or "head" in n


func _is_limb_drive(n: String) -> bool:
	return "upper_arm" in n or "thigh" in n or "forearm" in n


func _loosen_joint(bone: PhysicalBone3D, n: String) -> void:
	var span: float = 0.7
	if "head" in n or "neck" in n:
		span = 0.55
	elif "spine" in n or "hip" in n:
		span = 0.45
	elif "thigh" in n or "shin" in n:
		span = 0.85
	elif "upper_arm" in n or "forearm" in n or "shoulder" in n:
		span = 1.1
	elif "hand" in n or "foot" in n:
		span = 0.7
	elif "thumb" in n or "index" in n or "middle" in n or "ring" in n or "pinky" in n or "toe" in n:
		span = 0.35
	for axis in ["x", "y", "z"]:
		var p := "joint_constraints/%s/" % axis
		bone.set(p + "angular_limit_enabled", true)
		bone.set(p + "angular_limit_upper", span)
		bone.set(p + "angular_limit_lower", -span)
		bone.set(p + "angular_limit_softness", 0.8)
		bone.set(p + "angular_damping", 0.15)
		bone.set(p + "angular_restitution", 0.05)
		bone.set(p + "linear_limit_enabled", true)
		bone.set(p + "linear_damping", 0.4)
		bone.set(p + "erp", 0.4)
		bone.set(p + "angular_spring_enabled", true)
		bone.set(p + "angular_spring_stiffness", 8.0 if _is_core(n) else 3.0)
		bone.set(p + "angular_spring_damping", 0.6)


func kick_from_hit(dir: Vector3, limb: int = 0) -> void:
	if get_parent() and get_parent().has_meta("blasted"):
		return
	_ensure_ready()
	if dir.length_squared() < 0.0001:
		dir = Vector3(0, 0.2, 1)
	dir = (dir.normalized() + Vector3.UP * 0.35).normalized()
	_queue_launch(dir, 14.0, 8.0)


func apply_blast(origin: Vector3, blast_force: float) -> void:
	if get_parent():
		get_parent().set_meta("blasted", true)
	_ensure_ready()
	_muscle = 0.0
	_settled = false
	_age = 0.0
	for bone in _bones:
		if not is_instance_valid(bone):
			continue
		bone.linear_damp = 0.01
		bone.angular_damp = 0.05
		if "can_sleep" in bone:
			bone.can_sleep = false
		_set_spring(bone, 0.0)
	var hips := _bone_named("hip")
	var away: Vector3 = Vector3.UP
	if hips:
		away = hips.global_position - origin
	if away.length_squared() < 0.001:
		away = Vector3.UP
	away = away.normalized()
	var launch: Vector3 = (away * 0.55 + Vector3.UP * 0.84).normalized()
	var speed: float = clampf(maxf(blast_force, 28.0) * 0.55, 16.0, 28.0)
	_queue_launch(launch, speed, speed * 0.7)


var _pending_dir: Vector3 = Vector3.ZERO
var _pending_speed: float = 0.0
var _pending_tumble: float = 0.0
var _pending_frames: int = 0


func _queue_launch(dir: Vector3, speed: float, tumble: float) -> void:
	_pending_dir = dir
	_pending_speed = speed
	_pending_tumble = tumble
	_pending_frames = 2


func _launch(dir: Vector3, speed: float, tumble: float) -> void:
	for bone in _bones:
		if not is_instance_valid(bone):
			continue
		var n: String = str(bone.get("bone_name")).to_lower()
		if "thumb" in n or "index" in n or "middle" in n or "ring" in n or "pinky" in n or "toe" in n:
			continue
		var w: float = 0.2
		if "hip" in n or n == "root":
			w = 1.0
		elif "spine" in n:
			w = 0.85
		elif "thigh" in n:
			w = 0.7
		elif "upper_arm" in n or "shoulder" in n:
			w = 0.55
		elif "head" in n or "neck" in n:
			w = 0.5
		elif "shin" in n or "forearm" in n:
			w = 0.4
		else:
			w = 0.15
		var jitter := Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.15), randf_range(-0.2, 0.2))
		var vel: Vector3 = dir * speed * w + jitter * tumble
		var mass: float = bone.mass if bone.mass > 0.05 else 1.0
		bone.call("apply_central_impulse", vel * mass)
		bone.set("linear_velocity", vel)
		if "hip" in n or "spine" in n:
			var spin: Vector3 = Vector3(-dir.z, 0.5, dir.x) * tumble * 1.8
			bone.set("angular_velocity", spin)


func _set_spring(bone: PhysicalBone3D, stiffness: float) -> void:
	for axis in ["x", "y", "z"]:
		bone.set("joint_constraints/%s/angular_spring_stiffness" % axis, stiffness)
		bone.set("joint_constraints/%s/angular_spring_enabled" % axis, stiffness > 0.05)


func _physics_process(delta: float) -> void:
	if _bones.is_empty():
		_ensure_ready()
		return
	if _pending_frames > 0:
		_pending_frames -= 1
		if _pending_frames == 0 and _pending_speed > 0.0:
			_launch(_pending_dir, _pending_speed, _pending_tumble)
			_pending_speed = 0.0
		return
	_age += delta
	_muscle = maxf(0.0, 1.0 - _age / 0.85)
	if _age < 0.7:
		_flail(delta)
	elif not _settled and _age > 1.8:
		_settle()
		_settled = true


func _flail(_delta: float) -> void:
	## Short Euphoria-like arm throw: reach out as they go down, then give out.
	for bone in _bones:
		if not is_instance_valid(bone):
			continue
		var n: String = str(bone.get("bone_name")).to_lower()
		if "upper_arm" in n:
			var out: Vector3 = bone.global_transform.basis.x
			if ".r" in n or "_r" in n:
				out = -out
			bone.call("apply_central_impulse", (out * 0.9 + Vector3.UP * 0.35) * _muscle * 1.8)
		elif "thigh" in n:
			bone.call("apply_central_impulse", Vector3.DOWN * _muscle * 0.6)


func _settle() -> void:
	for bone in _bones:
		if not is_instance_valid(bone):
			continue
		bone.linear_damp = 0.55
		bone.angular_damp = 1.1
		if "can_sleep" in bone:
			bone.can_sleep = true
		_set_spring(bone, 0.0)


func _bone_named(part: String) -> PhysicalBone3D:
	for bone in _bones:
		if part in str(bone.get("bone_name")).to_lower():
			return bone
	return null
