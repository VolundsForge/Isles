extends SkeletonModifier3D

## After the walk/idle pose, reach a hand to the wound and/or keep a hurt leg bent.

enum Limb { NONE, HEAD, TORSO, GUT, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG }

var wounded: Limb = Limb.NONE
var clutch_weight: float = 0.0
var limp_weight: float = 0.0
var bend_weight: float = 0.0
var wound_local: Vector3 = Vector3.ZERO
var has_wound_point: bool = false

const _BONES := {
	Limb.HEAD: ["DEF-head", "DEF-neck"],
	Limb.TORSO: ["DEF-spine.002", "DEF-spine.003"],
	Limb.GUT: ["DEF-spine.001", "DEF-hips"],
	Limb.LEFT_ARM: ["DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L", "DEF-shoulder.L"],
	Limb.RIGHT_ARM: ["DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R", "DEF-shoulder.R"],
	Limb.LEFT_LEG: ["DEF-thigh.L", "DEF-shin.L", "DEF-foot.L"],
	Limb.RIGHT_LEG: ["DEF-thigh.R", "DEF-shin.R", "DEF-foot.R"],
}


func set_wound(limb: Limb, world_hit: Vector3 = Vector3.ZERO) -> void:
	var npc := _npc_node()
	if npc and world_hit != Vector3.ZERO and world_hit.distance_to(npc.global_position) < 3.5:
		wound_local = npc.to_local(world_hit)
		has_wound_point = true
		if limb == Limb.TORSO and wound_local.y < 0.95:
			limb = Limb.GUT
	else:
		has_wound_point = false
	wounded = limb
	active = limb != Limb.NONE
	influence = 1.0
	var legs := limb == Limb.LEFT_LEG or limb == Limb.RIGHT_LEG
	limp_weight = 1.0 if legs else 0.0
	bend_weight = 1.0 if limb == Limb.GUT else 0.0
	clutch_weight = 1.0 if limb != Limb.NONE else 0.0


func _npc_node() -> Node3D:
	var n: Node = get_skeleton()
	if n == null:
		n = get_parent()
	while n:
		if n is CogitoNPC:
			return n as Node3D
		n = n.get_parent()
	return null


func classify_hit(npc: Node3D, world_hit: Vector3, hit_dir: Vector3) -> Limb:
	var skel := get_skeleton()
	if skel == null:
		skel = get_parent() as Skeleton3D
	if skel == null:
		return Limb.TORSO
	var local_hit := npc.to_local(world_hit)
	if world_hit == Vector3.ZERO or world_hit.distance_to(npc.global_position) > 4.0:
		local_hit = Vector3(hit_dir.x, 0.9, hit_dir.z)
	var best: Limb = Limb.TORSO
	var best_d: float = INF
	for limb in _BONES.keys():
		for bone_name in _BONES[limb]:
			var idx: int = skel.find_bone(bone_name)
			if idx < 0:
				continue
			var bone_pos: Vector3 = skel.to_global(skel.get_bone_global_pose(idx).origin)
			var d: float = bone_pos.distance_squared_to(world_hit if world_hit != Vector3.ZERO else npc.global_position + Vector3(0, 1, 0))
			if d < best_d:
				best_d = d
				best = limb
	# Height fallback if the hit is clearly head or legs.
	if local_hit.y < 0.48:
		best = Limb.LEFT_LEG if local_hit.x > 0.02 else Limb.RIGHT_LEG
	elif local_hit.y > 1.58:
		best = Limb.HEAD
	elif local_hit.y < 0.95 and (best == Limb.TORSO or best == Limb.GUT):
		best = Limb.GUT
	elif local_hit.y >= 0.95 and local_hit.y <= 1.45 and best == Limb.GUT:
		best = Limb.TORSO
	return best


func _process_modification() -> void:
	if wounded == Limb.NONE:
		return
	var skel := get_skeleton()
	if skel == null:
		return
	if clutch_weight > 0.01:
		_apply_clutch(skel)
	if limp_weight > 0.01:
		_apply_limp(skel)
	if bend_weight > 0.01:
		_apply_gut_bend(skel)


func _body_forward(skel: Skeleton3D) -> Vector3:
	var n: Node = skel
	while n:
		if n is CogitoNPC:
			return -(n as Node3D).global_transform.basis.z
		n = n.get_parent()
	return -skel.global_transform.basis.z


func _bone_world(skel: Skeleton3D, bone_name: String) -> Vector3:
	var idx: int = skel.find_bone(bone_name)
	if idx < 0:
		return skel.global_position + Vector3.UP
	return skel.to_global(skel.get_bone_global_pose(idx).origin)


func _apply_clutch(skel: Skeleton3D) -> void:
	# Opposite hand for an arm wound; same-side hand for head / chest / that-side thigh.
	var use_right: bool = _clutch_with_right()
	var fwd: Vector3 = _body_forward(skel)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var char_right: Vector3 = fwd.cross(Vector3.UP)
	if char_right.length_squared() < 0.0001:
		char_right = Vector3.RIGHT
	char_right = char_right.normalized()
	var clutch_out: Vector3 = char_right if use_right else -char_right
	var chest: Vector3 = _bone_world(skel, "DEF-spine.002")
	var target: Vector3
	if has_wound_point:
		var npc := _npc_node()
		if npc:
			target = npc.to_global(wound_local) + fwd * 0.1
			target = _clamp_in_front(target, chest, fwd, char_right, 0.1, 0.28, -0.28, 0.42)
		else:
			target = _front_clutch_target(skel, chest, fwd, char_right, clutch_out)
	else:
		target = _front_clutch_target(skel, chest, fwd, char_right, clutch_out)
	var pole: Vector3 = _clutch_pole(chest, fwd, clutch_out)
	var w: float = clutch_weight * influence
	var upper := "DEF-upper_arm.R" if use_right else "DEF-upper_arm.L"
	var lower := "DEF-forearm.R" if use_right else "DEF-forearm.L"
	var hand := "DEF-hand.R" if use_right else "DEF-hand.L"
	_two_bone_ik_front(skel, upper, lower, hand, target, pole, chest, fwd, w)


func _clutch_with_right() -> bool:
	match wounded:
		Limb.RIGHT_ARM, Limb.RIGHT_LEG:
			return false
		_:
			return true


func _clutch_pole(chest: Vector3, fwd: Vector3, clutch_out: Vector3) -> Vector3:
	match wounded:
		Limb.HEAD:
			return chest + fwd * 0.28 + clutch_out * 0.2 + Vector3.UP * 0.32
		Limb.LEFT_ARM, Limb.RIGHT_ARM:
			return chest + fwd * 0.5 + clutch_out * 0.22 + Vector3.UP * 0.12
		Limb.LEFT_LEG, Limb.RIGHT_LEG:
			return chest + fwd * 0.35 + clutch_out * 0.18 - Vector3.UP * 0.05
		Limb.GUT:
			return chest + fwd * 0.4 + clutch_out * 0.2 - Vector3.UP * 0.08
		_:
			return chest + fwd * 0.38 + clutch_out * 0.26 + Vector3.UP * 0.04


func _front_clutch_target(skel: Skeleton3D, chest: Vector3, fwd: Vector3, char_right: Vector3, clutch_out: Vector3) -> Vector3:
	var raw: Vector3
	var min_front := 0.16
	var max_lat := 0.2
	var min_up := -0.1
	var max_up := 0.22
	match wounded:
		Limb.HEAD:
			raw = _bone_world(skel, "DEF-head") + fwd * 0.14 + clutch_out * 0.09 - Vector3.UP * 0.02
			min_front = 0.12
			max_lat = 0.14
			min_up = 0.22
			max_up = 0.42
		Limb.LEFT_ARM:
			raw = _bone_world(skel, "DEF-upper_arm.L").lerp(chest, 0.4) + fwd * 0.22
			min_front = 0.18
			max_lat = 0.2
			min_up = -0.02
			max_up = 0.16
		Limb.RIGHT_ARM:
			raw = _bone_world(skel, "DEF-upper_arm.R").lerp(chest, 0.4) + fwd * 0.22
			min_front = 0.18
			max_lat = 0.2
			min_up = -0.02
			max_up = 0.16
		Limb.LEFT_LEG:
			raw = _bone_world(skel, "DEF-thigh.L") + fwd * 0.16 + Vector3.UP * 0.08
			min_front = 0.14
			max_lat = 0.16
			min_up = -0.22
			max_up = 0.02
		Limb.RIGHT_LEG:
			raw = _bone_world(skel, "DEF-thigh.R") + fwd * 0.16 + Vector3.UP * 0.08
			min_front = 0.14
			max_lat = 0.16
			min_up = -0.22
			max_up = 0.02
		Limb.GUT:
			raw = _bone_world(skel, "DEF-hips") + fwd * 0.18 + Vector3.UP * 0.12
			min_front = 0.16
			max_lat = 0.12
			min_up = -0.18
			max_up = 0.04
		_:
			raw = chest + fwd * 0.2 + clutch_out * 0.04 - Vector3.UP * 0.02
			min_front = 0.18
			max_lat = 0.1
			min_up = -0.08
			max_up = 0.1
	return _clamp_in_front(raw, chest, fwd, char_right, min_front, max_lat, min_up, max_up)


func _clamp_in_front(
	point: Vector3,
	chest: Vector3,
	fwd: Vector3,
	char_right: Vector3,
	min_front: float,
	max_lat: float,
	min_up: float,
	max_up: float
) -> Vector3:
	var rel: Vector3 = point - chest
	var front: float = maxf(rel.dot(fwd), min_front)
	var lateral: float = clampf(rel.dot(char_right), -max_lat, max_lat)
	var up_off: float = clampf(rel.dot(Vector3.UP), min_up, max_up)
	return chest + fwd * front + char_right * lateral + Vector3.UP * up_off


func _two_bone_ik_front(
	skel: Skeleton3D,
	root_name: String,
	mid_name: String,
	end_name: String,
	target: Vector3,
	pole: Vector3,
	chest: Vector3,
	fwd: Vector3,
	w: float
) -> void:
	var ri: int = skel.find_bone(root_name)
	var mi: int = skel.find_bone(mid_name)
	var ei: int = skel.find_bone(end_name)
	if ri < 0 or mi < 0 or ei < 0:
		return
	var root_pos: Vector3 = _bone_world(skel, root_name)
	var mid_pos: Vector3 = _bone_world(skel, mid_name)
	var end_pos: Vector3 = _bone_world(skel, end_name)
	var l1: float = root_pos.distance_to(mid_pos)
	var l2: float = mid_pos.distance_to(end_pos)
	if l1 < 0.01 or l2 < 0.01:
		return
	var to_target: Vector3 = target - root_pos
	if to_target.length_squared() < 0.0001:
		return
	var dist: float = clampf(to_target.length(), 0.12, l1 + l2 - 0.06)
	var dir: Vector3 = to_target.normalized()
	var pole_dir: Vector3 = pole - root_pos
	var n: Vector3 = dir.cross(pole_dir)
	if n.length_squared() < 0.00001:
		n = fwd.cross(Vector3.UP)
	n = n.normalized()
	var cos_a: float = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var bend: float = acos(cos_a)
	var elbow_a: Vector3 = root_pos + Quaternion(n, -bend) * (dir * l1)
	var elbow_b: Vector3 = root_pos + Quaternion(n, bend) * (dir * l1)
	var elbow: Vector3 = elbow_a
	if (elbow_b - chest).dot(fwd) > (elbow_a - chest).dot(fwd):
		elbow = elbow_b
	# Keep the elbow in front of the ribs.
	var elbow_front: float = (elbow - chest).dot(fwd)
	if elbow_front < 0.16:
		elbow += fwd * (0.16 - elbow_front)
	_aim_limb(skel, root_name, mid_name, elbow, w)
	_aim_limb(skel, mid_name, end_name, target, w)


func _aim_limb(skel: Skeleton3D, bone_name: String, child_name: String, world_target: Vector3, weight: float) -> void:
	var idx: int = skel.find_bone(bone_name)
	var cidx: int = skel.find_bone(child_name)
	if idx < 0 or cidx < 0 or weight <= 0.0:
		return
	var parent_idx: int = skel.get_bone_parent(idx)
	var parent_global: Transform3D = skel.global_transform
	if parent_idx >= 0:
		parent_global = skel.global_transform * skel.get_bone_global_pose(parent_idx)
	var pose: Transform3D = skel.get_bone_pose(idx)
	var bone_global: Transform3D = parent_global * pose
	var child_global: Vector3 = skel.to_global(skel.get_bone_global_pose(cidx).origin)
	var from_dir: Vector3 = child_global - bone_global.origin
	if from_dir.length_squared() < 0.0001:
		return
	from_dir = from_dir.normalized()
	var to_dir: Vector3 = world_target - bone_global.origin
	if to_dir.length_squared() < 0.0001:
		return
	to_dir = to_dir.normalized()
	var rot := Quaternion(from_dir, to_dir)
	var desired := Transform3D(Basis(rot) * bone_global.basis, bone_global.origin)
	var desired_local: Transform3D = parent_global.affine_inverse() * desired
	var blended: Transform3D = pose.interpolate_with(desired_local, clampf(weight, 0.0, 1.0))
	skel.set_bone_pose_rotation(idx, blended.basis.get_rotation_quaternion())


func _apply_gut_bend(skel: Skeleton3D) -> void:
	var w: float = bend_weight * influence
	_add_bone_x_rotation(skel, "DEF-hips", deg_to_rad(18.0) * w)
	_add_bone_x_rotation(skel, "DEF-spine.001", deg_to_rad(22.0) * w)
	_add_bone_x_rotation(skel, "DEF-spine.002", deg_to_rad(16.0) * w)


func _apply_limp(skel: Skeleton3D) -> void:
	var w: float = limp_weight * influence
	var thigh := "DEF-thigh.L" if wounded == Limb.LEFT_LEG else "DEF-thigh.R"
	var shin := "DEF-shin.L" if wounded == Limb.LEFT_LEG else "DEF-shin.R"
	_add_bone_x_rotation(skel, thigh, deg_to_rad(28.0) * w)
	_add_bone_x_rotation(skel, shin, deg_to_rad(-18.0) * w)
	_add_bone_x_rotation(skel, "DEF-hips", deg_to_rad(8.0) * w)
	var side: float = 1.0 if wounded == Limb.LEFT_LEG else -1.0
	_add_bone_z_rotation(skel, "DEF-hips", deg_to_rad(6.0) * w * side)


func _aim_bone(skel: Skeleton3D, bone_name: String, world_target: Vector3, weight: float, max_angle: float = 1.2) -> void:
	var idx: int = skel.find_bone(bone_name)
	if idx < 0 or weight <= 0.0:
		return
	var parent_idx: int = skel.get_bone_parent(idx)
	var parent_global: Transform3D = skel.global_transform
	if parent_idx >= 0:
		parent_global = skel.global_transform * skel.get_bone_global_pose(parent_idx)
	var pose: Transform3D = skel.get_bone_pose(idx)
	var bone_global: Transform3D = parent_global * pose
	var to_target: Vector3 = world_target - bone_global.origin
	if to_target.length_squared() < 0.0002:
		return
	var from_dir: Vector3 = bone_global.basis.y.normalized()
	var to_dir: Vector3 = to_target.normalized()
	var ang: float = from_dir.angle_to(to_dir)
	if ang > max_angle and ang > 0.001:
		to_dir = from_dir.slerp(to_dir, max_angle / ang).normalized()
	var rot := Quaternion(from_dir, to_dir)
	var desired := Transform3D(Basis(rot) * bone_global.basis, bone_global.origin)
	var desired_local: Transform3D = parent_global.affine_inverse() * desired
	var blended: Transform3D = pose.interpolate_with(desired_local, clampf(weight, 0.0, 1.0))
	skel.set_bone_pose_rotation(idx, blended.basis.get_rotation_quaternion())


func _add_bone_x_rotation(skel: Skeleton3D, bone_name: String, radians: float) -> void:
	var idx: int = skel.find_bone(bone_name)
	if idx < 0:
		return
	var q: Quaternion = skel.get_bone_pose_rotation(idx)
	skel.set_bone_pose_rotation(idx, q * Quaternion(Vector3.RIGHT, radians))


func _add_bone_z_rotation(skel: Skeleton3D, bone_name: String, radians: float) -> void:
	var idx: int = skel.find_bone(bone_name)
	if idx < 0:
		return
	var q: Quaternion = skel.get_bone_pose_rotation(idx)
	skel.set_bone_pose_rotation(idx, q * Quaternion(Vector3.FORWARD, radians))
