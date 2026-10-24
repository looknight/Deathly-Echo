extends Area3D
## 毒气云：由毒气罐爆炸产生，持续 5 秒，范围内丧尸每秒扣 10 血

const RADIUS: float = 3.5
const LIFETIME: float = 5.0
const TICK: float = 1.0
const DPS: float = 10.0

var _life: float = LIFETIME
var _tick: float = 0.0
var _mesh: MeshInstance3D

func _ready() -> void:
	monitoring = true
	monitorable = false

	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	cs.shape = shape
	cs.position.y = 1.0
	add_child(cs)

	_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height = 2.6
	_mesh.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.9, 0.3, 0.22)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.emission_enabled = true
	m.emission = Color(0.3, 0.85, 0.2)
	m.emission_energy_multiplier = 0.5
	_mesh.material_override = m
	_mesh.position.y = 1.0
	add_child(_mesh)

func _physics_process(delta: float) -> void:
	_life -= delta
	_tick += delta
	if _tick >= TICK:
		_tick -= TICK
		_damage_inside()
	if _mesh:
		# 轻微呼吸感，避免一大块死板的绿色圆柱
		_mesh.scale = Vector3.ONE + Vector3.ONE * (0.04 * sin(_life * 4.0))
	if _life <= 0.0:
		queue_free()

func _damage_inside() -> void:
	for body in get_overlapping_bodies():
		if body == null or not is_instance_valid(body):
			continue
		if body.is_in_group("zombie") and body.has_method("take_damage"):
			body.take_damage(DPS, "gas")
