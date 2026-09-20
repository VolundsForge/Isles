extends Node3D

## Runtime grass tufts on the inland green. Trees are placed in the scene.

@export var grass_count: int = 900
@export var grass_radius: float = 22.0
@export var center: Vector3 = Vector3(0, 0.14, -8)


func _ready() -> void:
	_scatter_grass()


func _scatter_grass() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.5, 0.2)
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blade := PrismMesh.new()
	blade.size = Vector3(0.12, 0.28, 0.04)
	blade.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade
	mm.instance_count = grass_count
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var placed := 0
	var i := 0
	while placed < grass_count and i < grass_count * 4:
		i += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * grass_radius
		var x := center.x + cos(a) * r
		var z := center.z + sin(a) * r
		# Keep a path from the beach spawn to the cottage clear.
		if absf(x) < 3.2 and z > -22.0 and z < 18.0:
			continue
		if Vector2(x + 16.0, z + 10.0).length() < 4.0:
			continue
		if Vector2(x - 14.0, z + 18.0).length() < 4.0:
			continue
		var xf := Transform3D.IDENTITY
		xf = xf.scaled(Vector3(rng.randf_range(0.7, 1.4), rng.randf_range(0.6, 1.6), rng.randf_range(0.7, 1.3)))
		xf = xf.rotated(Vector3.UP, rng.randf() * TAU)
		xf.origin = Vector3(x, center.y, z)
		mm.set_instance_transform(placed, xf)
		placed += 1
	mm.instance_count = placed
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
