extends RigidBody3D
## 手雷：碰到碰撞体爆炸，范围伤害

var timer: float = 2.5
var direct_damage: float = 0.0  # 榴弹枪直击伤害；玩家手雷保持 0（只走范围伤害）
var exploded: bool = false      # 防止同帧「碰撞引爆 + 引信到期」重复结算伤害
var acid: bool = false          # 酸液球（吐酸者）：只在地面/墙体引爆，只伤玩家

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_collide)
	add_to_group("projectile")  # 换图时由 WaveManager 统一清理，避免飞行中的投掷物飞进新地图

func _physics_process(delta: float) -> void:
	timer -= delta
	if timer <= 0: explode()

func _on_collide(body: Node3D) -> void:
	if acid:
		# 酸液球只在地面/墙体上炸，不会被丧尸（包括发射者自己）提前引爆
		if body is StaticBody3D:
			explode()
		return
	# 碰到丧尸：先结算直击伤害，再引爆结算范围伤害（玩家手雷与榴弹枪共用）
	if body.is_in_group("zombie"):
		if direct_damage > 0.0 and body.has_method("take_damage"):
			body.take_damage(direct_damage, "launcher")
			GameState.run_damage += direct_damage  # 结算面板统计
		explode()
	# 碰到墙壁 / 地面等静态碰撞体：立即引爆
	elif body is StaticBody3D:
		explode()

func explode() -> void:
	if exploded: return
	exploded = true
	var center: Vector3 = global_position
	# 爆炸声：按距离衰减；酸液的 8 连发用更低的基准音量，避免刷屏
	AudioManager.play_explosion(center, -14.0 if acid else -4.0)
	# 屏幕震动：按距离衰减，近处最猛（酸液球不震，避免敌人投掷物刷屏抖动）
	if not acid:
		var p := get_tree().get_first_node_in_group("player")
		if p and is_instance_valid(p) and p.has_method("camera_shake"):
			var pd: float = center.distance_to(p.global_position)
			if pd < 16.0:
				p.camera_shake(0.02 + 0.10 * (1.0 - pd / 16.0), 0.3)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0 if acid else 5.0
	q.shape = sphere
	q.transform = Transform3D(Basis(), center)
	q.collide_with_areas = true
	var results: Array = space.intersect_shape(q)
	for r in results:
		var col: Object = r.collider
		if col == self: continue
		var is_player: bool = col is CharacterBody3D and col.is_in_group("player")
		if acid:
			# 酸液：只溅玩家，固定 15 点（玩家 take_damage 只吃 1 个参数）
			if is_player and col.has_method("take_damage"):
				col.take_damage(15.0)
			continue
		# 排除玩家自己
		if is_player: continue
		if col and col.has_method("take_damage"):
			var d: float = center.distance_to(col.global_position)
			var dmg_amt: float = max(20.0, 100.0 - d * 15.0)
			col.take_damage(dmg_amt, "explosion")
			if col.is_in_group("zombie"):
				GameState.run_damage += dmg_amt  # 结算面板统计（只算打丧尸）
	var flash: OmniLight3D = OmniLight3D.new()
	flash.light_color = Color(0.4, 1.0, 0.3) if acid else Color(1, 0.6, 0.2)
	flash.light_energy = 8.0
	flash.omni_range = 10.0
	get_parent().add_child(flash)
	flash.global_position = center  # 必须先入树，否则 global_position 赋值无效
	# 补间必须挂在 flash 自己身上。
	# 若写成 self.create_tween()，下方 queue_free() 会把补间一起杀掉（Tween 绑定在所属节点上），
	# 淡出与回收永远不会执行 —— 每炸一次场上就永久多一盏灯，越打越亮、越卡。
	var tw: Tween = flash.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # 顿帧/暂停时也照常收尾，不留残影
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)
	queue_free()
