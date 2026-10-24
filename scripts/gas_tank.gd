extends StaticBody3D
## 毒气罐：30 点血量，被打爆后在原地生成持续 5 秒的毒雾

const MAX_HP: float = 30.0
const GAS_CLOUD_SCRIPT: Script = preload("res://scripts/gas_cloud.gd")

var hp: float = MAX_HP
var exploded: bool = false

func _ready() -> void:
	add_to_group("hazard")

	# 罐体
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.34
	cyl.bottom_radius = 0.34
	cyl.height = 1.2
	body.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.52, 0.2)
	mat.roughness = 0.45
	mat.metallic = 0.5
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 0.15)
	mat.emission_energy_multiplier = 0.3
	body.material_override = mat
	add_child(body)

	# 顶部阀门
	var valve := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.12, 0.18, 0.12)
	valve.mesh = vm
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.35, 0.35, 0.38)
	vmat.metallic = 0.8
	valve.material_override = vmat
	valve.position.y = 0.65
	add_child(valve)

	# 两道黄黑警示箍：和油桶区分开，一眼看出是「毒」
	for sy in [0.35, -0.35]:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.355
		rm.bottom_radius = 0.355
		rm.height = 0.12
		ring.mesh = rm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.85, 0.75, 0.15)
		rmat.roughness = 0.5
		rmat.emission_enabled = true
		rmat.emission = Color(0.8, 0.65, 0.1)
		rmat.emission_energy_multiplier = 0.5
		ring.material_override = rmat
		ring.position.y = float(sy)
		add_child(ring)

	# 碰撞
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.34
	shape.height = 1.2
	cs.shape = shape
	add_child(cs)

func take_damage(amount: float, weapon_type: String = "pistol") -> void:
	if exploded:
		return
	hp -= amount
	if hp <= 0.0:
		explode()

func explode() -> void:
	if exploded:
		return
	exploded = true
	remove_from_group("hazard")
	var host: Node = get_parent()
	if host:
		var cloud: Area3D = Area3D.new()
		cloud.set_script(GAS_CLOUD_SCRIPT)
		host.add_child(cloud)
		cloud.global_position = global_position + Vector3.UP * 0.4
	# 一小段绿色闪光作为爆点反馈
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.4, 1.0, 0.35)
	flash.light_energy = 5.0
	flash.omni_range = 8.0
	if host:
		host.add_child(flash)
		flash.global_position = global_position
		var tw := flash.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(flash, "light_energy", 0.0, 0.35)
		tw.tween_callback(flash.queue_free)
	queue_free()
