extends StaticBody3D
## 油桶：35 点血量，受击爆炸；4 米内造成 120 伤害，并连锁引爆附近油桶（0.2 秒延迟）

const MAX_HP: float = 35.0
const BLAST_RADIUS: float = 4.0
const BLAST_DAMAGE: float = 120.0
const CHAIN_DELAY: float = 0.2

var hp: float = MAX_HP
var exploded: bool = false
var _chain_pending: bool = false

# ===== 可交互提示（3 米内显示「可引爆」）=====
var _hint_area: Area3D
var _hint_label: Label3D

func _ready() -> void:
	add_to_group("barrel")
	_setup_hint()

func _setup_hint() -> void:
	# 独立检测圈：layer=0 不参与碰撞，mask=1 只用来感知玩家
	_hint_area = Area3D.new()
	_hint_area.collision_layer = 0
	_hint_area.collision_mask = 1
	_hint_area.monitorable = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 3.0
	cs.shape = sp
	_hint_area.add_child(cs)
	add_child(_hint_area)

	_hint_label = Label3D.new()
	_hint_label.text = "可引爆"
	_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint_label.no_depth_test = true
	_hint_label.font_size = 48
	_hint_label.pixel_size = 0.006
	_hint_label.outline_size = 10
	_hint_label.modulate = Color(1.0, 0.84, 0.20)
	_hint_label.outline_modulate = Color(0, 0, 0, 0.85)
	_hint_label.position = Vector3(0, 1.35, 0)
	_hint_label.visible = false
	add_child(_hint_label)

	_hint_area.body_entered.connect(_on_hint_enter)
	_hint_area.body_exited.connect(_on_hint_exit)

func _on_hint_enter(body: Node3D) -> void:
	if exploded or _hint_label == null: return
	if body != null and body.is_in_group("player"):
		_hint_label.visible = true

func _on_hint_exit(body: Node3D) -> void:
	if _hint_label == null: return
	if body != null and body.is_in_group("player"):
		_hint_label.visible = false

func take_damage(amount: float, weapon_type: String = "pistol") -> void:
	if exploded: return
	hp -= amount
	if hp <= 0.0:
		explode()

func chain_explode(delay: float = CHAIN_DELAY) -> void:
	# 连锁引爆：延迟后自爆。
	# 用 Tween 而非 await：节点被销毁时补间会自动失效，不会在已释放对象上恢复协程
	if exploded or _chain_pending: return
	_chain_pending = true
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(delay)
	tw.tween_callback(_chain_boom)

func _chain_boom() -> void:
	if exploded: return
	exploded = true
	_boom()

func explode() -> void:
	if exploded: return
	exploded = true
	_boom()

func _boom() -> void:
	remove_from_group("barrel")
	if _hint_label:
		_hint_label.visible = false
	var center: Vector3 = global_position
	AudioManager.play_explosion(center)

	# 视觉：橙色闪光
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.55, 0.15)
	flash.light_energy = 10.0
	flash.omni_range = 8.0
	get_parent().add_child(flash)
	flash.global_position = center  # 先入树再设全局坐标
	# 补间挂在 flash 自己身上：挂在油桶上会随下方 queue_free() 一起被杀，灯就永久留在场上
	var tw := flash.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)

	# 范围伤害
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = BLAST_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = [get_rid()]
	for h in space.intersect_shape(params, 32):
		var body: Object = h.get("collider")
		if body == null:
			continue
		# 其它油桶：只排队连锁，不再直接扣血，避免同帧递归爆栈
		if body.is_in_group("barrel"):
			if body.has_method("chain_explode"):
				body.chain_explode(CHAIN_DELAY)
			continue
		# 玩家与丧尸的 take_damage 签名不同：玩家 1 参，丧尸 2 参
		if body.is_in_group("player"):
			if body.has_method("take_damage"):
				body.take_damage(BLAST_DAMAGE)
		elif body.has_method("take_damage"):
			body.take_damage(BLAST_DAMAGE, "barrel")

	queue_free()
