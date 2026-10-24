extends Area3D
## 地刺陷阱：玩家踩上扣 15 血，随后进入 3 秒冷却（网格与碰撞体自建，调用方只需给位置）

const DAMAGE: float = 15.0
const COOLDOWN: float = 3.0

var _cd: float = 0.0
var _spike_mat: StandardMaterial3D
var _hint_area: Area3D
var _hint_label: Label3D

func _ready() -> void:
	add_to_group("hazard")
	monitoring = true
	monitorable = false

	# 底座
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.08, 1.8)
	base.mesh = bm
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.11, 0.11, 0.13)
	base_mat.roughness = 0.55
	base_mat.metallic = 0.55
	base.material_override = base_mat
	add_child(base)

	# 3×3 尖刺（圆锥：top_radius = 0）
	_spike_mat = StandardMaterial3D.new()
	_spike_mat.albedo_color = Color(0.42, 0.42, 0.47)
	_spike_mat.roughness = 0.35
	_spike_mat.metallic = 0.75
	for gx in range(3):
		for gz in range(3):
			var s := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.085
			cm.height = 0.3
			s.mesh = cm
			s.material_override = _spike_mat
			s.position = Vector3(-0.55 + float(gx) * 0.55, 0.2, -0.55 + float(gz) * 0.55)
			add_child(s)

	# 碰撞：整块薄板，踩上去就触发，不要求精确踩到某一根刺
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.5, 1.6)
	cs.shape = box
	cs.position.y = 0.25
	add_child(cs)

	body_entered.connect(_on_body_entered)
	_setup_hint()

# 3 米内显示「危险」，让玩家在踩上去之前就能识别
func _setup_hint() -> void:
	_hint_area = Area3D.new()
	_hint_area.collision_layer = 0
	_hint_area.collision_mask = 1
	_hint_area.monitorable = false
	var hs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 3.0
	hs.shape = sp
	_hint_area.add_child(hs)
	add_child(_hint_area)

	_hint_label = Label3D.new()
	_hint_label.text = "危险"
	_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint_label.no_depth_test = true
	_hint_label.font_size = 48
	_hint_label.pixel_size = 0.006
	_hint_label.outline_size = 10
	_hint_label.modulate = Color(1.0, 0.32, 0.26)
	_hint_label.outline_modulate = Color(0, 0, 0, 0.85)
	_hint_label.position = Vector3(0, 1.0, 0)
	_hint_label.visible = false
	add_child(_hint_label)

	_hint_area.body_entered.connect(_on_hint_enter)
	_hint_area.body_exited.connect(_on_hint_exit)

func _on_hint_enter(body: Node3D) -> void:
	if _hint_label == null: return
	if body != null and body.is_in_group("player"):
		_hint_label.visible = true

func _on_hint_exit(body: Node3D) -> void:
	if _hint_label == null: return
	if body != null and body.is_in_group("player"):
		_hint_label.visible = false

func _physics_process(delta: float) -> void:
	if _cd <= 0.0:
		return
	_cd -= delta
	if _cd <= 0.0:
		_set_hot(false)

func _on_body_entered(body: Node3D) -> void:
	if _cd > 0.0:
		return
	if body == null or not body.is_in_group("player"):
		return
	if not body.has_method("take_damage"):
		return
	body.take_damage(DAMAGE)
	_cd = COOLDOWN
	_set_hot(true)

func _set_hot(on: bool) -> void:
	# 冷却中尖刺泛红，给玩家「暂时安全」的视觉反馈
	if _spike_mat == null:
		return
	_spike_mat.emission_enabled = on
	_spike_mat.emission = Color(0.9, 0.15, 0.1)
	_spike_mat.emission_energy_multiplier = 0.9 if on else 0.0
