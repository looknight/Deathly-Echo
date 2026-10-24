extends CharacterBody3D
## 人形丧尸：头+躯干+双臂+双腿，走路摆动

@export var zombie_type: String = "normal"
@export var speed: float = 2.0
@export var damage: float = 10.0
@export var max_hp: float = 60.0
@export var attack_range: float = 1.8

# 死亡结算完成信号：对象池复用后不能再用 tree_exited 判断死亡
signal died
var is_dead: bool = false          # 防止同帧多弹丸/爆炸重复结算
var _death_tween: Tween = null      # 倒地动画补间，回收时要杀掉

var gravity: float = 18.0
var hp: float = 60.0
var player: Node3D
var can_attack: bool = true
var walk_time: float = 0.0
var exploded: bool = false
var boss_state: int = 0  # 0=正常 1=冲刺 2=召唤 3=咆哮
var boss_skill_cd: float = 0.0
var stun_timer: float = 0.0  # 眩晕倒计时
# ===== 波次全局修饰（由 wave_manager 刷怪后套用）=====
var wave_speed_mult: float = 1.0   # 冲刺速度也要乘，否则 charger 无视狂暴
var wave_damage_mult: float = 1.0  # 近战与自爆伤害统一乘这个

# ===== charger（冲刺型）参数：写死，不暴露为导出项 =====
const CHARGER_NORMAL_SPEED: float = 2.5    # 常态移动速度
const CHARGER_CHARGE_SPEED: float = 6.5    # 冲刺速度
const CHARGER_TRIGGER_DIST: float = 10.0   # 进入该距离触发冲刺，触发后不再退回
const CHARGER_BLAST_DIST: float = 1.8      # 撞到玩家该距离内自爆
const CHARGER_HARD_RADIUS: float = 4.0     # 硬半径：>4m 完全无伤
const CHARGER_MAX_DMG: float = 80.0        # 中心伤害
const CHARGER_DMG_FALLOFF: float = 15.0    # 每米衰减：80 - d*15 → 4m 处 20
const ACID_SCENE: PackedScene = preload("res://scenes/grenade.tscn")

# ===== 吐酸者：8~15m 停下吐酸 =====
const SPIT_NEAR: float = 8.0        # 近于此距离会后撤
const SPIT_FAR: float = 15.0        # 远于此距离会靠近
const SPIT_WINDUP: float = 1.2      # 吐酸前摇
const SPIT_COOLDOWN: float = 2.6    # 两次吐酸间隔
var charging: bool = false                 # charger 是否已进入冲刺状态
var _spit_cd: float = 0.0
var _spit_windup: float = 0.0
var _growl_cd: float = 0.0          # 下一次低吼倒计时（4~8 秒随机）

var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var torso: MeshInstance3D
var head_node: Node3D
var is_female: bool = false

# ===== 精英词缀 =====
const ELITE_AFFIXES := {"frenzy": "狂暴", "split": "分裂", "lifesteal": "吸血"}
var is_elite: bool = false
var affix: String = ""

# ===== BOSS 三阶段 =====
const BOSS_CIRCLE_RADIUS: float = 2.2
const BOSS_CIRCLE_DELAY: float = 1.0
const BOSS_CIRCLE_DAMAGE: float = 30.0
const BOSS_CIRCLE_INTERVAL: float = 3.0
var boss_phase: int = 1
var _red_circle_cd: float = 0.0
# 无尽双 BOSS 变体："" = 常规（三阶段），"charger" = 冲锋， "spitter" = 吐酸
var boss_variant: String = ""
var _acid_ring_cd: float = 0.0

func _ready() -> void:
	add_to_group("zombie")
	is_female = randf() < 0.4
	player = get_tree().get_first_node_in_group("player")
	_build_body()
	_configure_type()

# 材质缓存：场上丧尸数量多，同色部件共用一份材质，避免每只丧尸都新建 StandardMaterial3D
static var _mat_cache: Dictionary = {}

func _make_mat(color: Color, rough: float, emit: float) -> StandardMaterial3D:
	# 以「颜色 + 粗糙度 + 发光强度」拼 key 复用材质。
	# 重要：缓存材质是共享只读的，任何地方都不能原地改它的属性，只能整体换一份新的。
	var key: String = str(color) + "|" + str(rough) + "|" + str(emit)
	var mat: StandardMaterial3D = _mat_cache.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = rough
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emit
		_mat_cache[key] = mat
	return mat

func _make_box(size: Vector3, color: Color, rough: float = 0.9, emit: float = 0.3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := _make_mat(color, rough, emit)
	m.material_override = mat
	m.set_meta("base_mat", mat)  # 记录初始材质，复用时据此还原（池化后类型会变）
	return m

func _build_body() -> void:
	var skin := Color(0.65, 0.58, 0.48)
	var cloth := Color(0.3, 0.25, 0.22)
	var pants := Color(0.15, 0.14, 0.16)
	# 体型比例：更像人
	var torso_w := 0.42 if is_female else 0.48
	var torso_d := 0.24 if is_female else 0.28
	var shoulder_x := 0.28 if is_female else 0.32

	# 骨盆
	var pelvis := _make_box(Vector3(torso_w * 0.9, 0.22, torso_d * 0.9), pants)
	pelvis.position = Vector3(0, 0.85, 0)
	add_child(pelvis)
	# 躯干（胸腔）
	torso = _make_box(Vector3(torso_w, 0.55, torso_d), cloth)
	torso.position = Vector3(0, 1.25, 0)
	add_child(torso)
	# 肩膀
	var shoulders := _make_box(Vector3(torso_w + 0.12, 0.12, torso_d), cloth.darkened(0.1))
	shoulders.position = Vector3(0, 1.52, 0)
	add_child(shoulders)
	# 头（更小更像人）
	head_node = Node3D.new()
	head_node.position = Vector3(0, 1.75, 0)
	var head_mesh := _make_box(Vector3(0.24, 0.28, 0.24), skin, 0.8, 0.2)
	head_node.add_child(head_mesh)
	# 红色眼睛
	var eye_l := _make_box(Vector3(0.04, 0.04, 0.02), Color(1, 0.1, 0.1), 0.3, 1.5)
	eye_l.position = Vector3(-0.06, 0.02, -0.13)
	head_node.add_child(eye_l)
	var eye_r := _make_box(Vector3(0.04, 0.04, 0.02), Color(1, 0.1, 0.1), 0.3, 1.5)
	eye_r.position = Vector3(0.06, 0.02, -0.13)
	head_node.add_child(eye_r)
	add_child(head_node)
	# 头发
	if is_female:
		var hair := _make_box(Vector3(0.26, 0.3, 0.26), Color(0.06, 0.05, 0.04), 0.9, 0.0)
		hair.position = Vector3(0, 0.05, 0.02)
		head_node.add_child(hair)
	else:
		var hair := _make_box(Vector3(0.25, 0.08, 0.25), Color(0.05, 0.04, 0.03), 0.9, 0.0)
		hair.position = Vector3(0, 0.16, 0)
		head_node.add_child(hair)

	# 左臂（下垂前伸）
	arm_l = Node3D.new()
	arm_l.position = Vector3(-shoulder_x, 1.48, 0)
	var arm_l_mesh := _make_box(Vector3(0.1, 0.55, 0.1), cloth.darkened(0.15))
	arm_l_mesh.position = Vector3(0, -0.28, 0)
	arm_l.add_child(arm_l_mesh)
	add_child(arm_l)
	# 右臂
	arm_r = Node3D.new()
	arm_r.position = Vector3(shoulder_x, 1.48, 0)
	var arm_r_mesh := _make_box(Vector3(0.1, 0.55, 0.1), cloth.darkened(0.15))
	arm_r_mesh.position = Vector3(0, -0.28, 0)
	arm_r.add_child(arm_r_mesh)
	add_child(arm_r)
	# 左腿
	leg_l = Node3D.new()
	leg_l.position = Vector3(-0.11, 0.8, 0)
	var leg_l_mesh := _make_box(Vector3(0.13, 0.75, 0.15), pants)
	leg_l_mesh.position = Vector3(0, -0.38, 0)
	leg_l.add_child(leg_l_mesh)
	add_child(leg_l)
	# 右腿
	leg_r = Node3D.new()
	leg_r.position = Vector3(0.11, 0.8, 0)
	var leg_r_mesh := _make_box(Vector3(0.13, 0.75, 0.15), pants)
	leg_r_mesh.position = Vector3(0, -0.38, 0)
	leg_r.add_child(leg_r_mesh)
	add_child(leg_r)

func _apply_body_visual(body_color: Color, eye_color: Color, body_emit: float, eye_emit: float) -> void:
	# 通用身体配色：亮色身体 + 高自发光，眼睛单列；头发/裤子等无发光部件跳过
	# 注意：材质来自共享缓存，禁止原地改属性，统一从缓存取新的一份换上
	for child in get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = child.material_override
			if not mat.emission_enabled:
				continue  # 头发/裤子等无发光部件不动
			# 眼睛：原发光色为红色，单独换色
			var is_eye: bool = mat.emission.r > 0.8 and mat.emission.g < 0.4
			child.material_override = _make_mat(
				eye_color if is_eye else body_color,
				mat.roughness,
				eye_emit if is_eye else body_emit)

func _apply_charger_visual() -> void:
	# charger：品红/洋红身体（远离 exploder 黄色色相），眼睛白热，高自发光
	# 注意：_apply_body_visual() 会遍历到场景自带的 Body/Head，故传色必须让两者同色，
	# 否则会出现「大盒子白热眼、小头身体色」的错位
	_apply_body_visual(Color(0.95, 0.15, 0.7), Color(0.95, 0.15, 0.7), 2.5, 2.5)

func _configure_type() -> void:
	match zombie_type:
		"runner":
			speed = 4.0; max_hp = 30.0; damage = 8.0
		"tank":
			speed = 1.2; max_hp = 200.0; damage = 25.0
			scale = Vector3(1.3,1.3,1.3)
		"exploder":
			speed = 2.5; max_hp = 40.0; damage = 50.0
			# 黄色身体标记（与 charger 的亮橙区分）
			_apply_body_visual(Color(1.0, 0.85, 0.1), Color(1.0, 0.95, 0.6), 1.4, 3.0)
		"charger":
			# 冲刺型：常态 2.5，冲刺 6.5，血量 55，撞击自爆
			# damage=0 是有意设计：charger 不参与近战抓挠，全部伤害只由 _charger_explode() 的自爆给出，
			# 避免「撞击自爆」与「抓挠」在同一距离内叠加一次额外伤害
			speed = CHARGER_NORMAL_SPEED; max_hp = 55.0; damage = 0.0
			_apply_charger_visual()
		"spitter":
			# 吐酸者：中距离站桩吐酸，近身会后退；damage=0 表示不参与近战
			speed = 2.2; max_hp = 45.0; damage = 0.0
			_apply_body_visual(Color(0.35, 0.85, 0.25), Color(0.6, 1.0, 0.4), 1.6, 2.5)
		"boss":
			speed = 1.8; max_hp = 800.0; damage = 35.0
			scale = Vector3(1.8,1.8,1.8)
			# BOSS红色发光更强
	hp = max_hp

func apply_wave_modifier(hp_mult: float, speed_mult: float, damage_mult: float) -> void:
	# 波次修饰：在 _configure_type 的基线之上再乘，不改 match 里的原始数值
	max_hp *= hp_mult
	hp = max_hp
	speed *= speed_mult
	damage *= damage_mult
	wave_speed_mult = speed_mult
	wave_damage_mult = damage_mult

func _physics_process(delta: float) -> void:
	if is_dead: return  # 死亡后立刻停手，倒地动画期间不再追击/攻击
	if not is_on_floor(): velocity.y -= gravity * delta
	# 眩晕：减速停止
	if stun_timer > 0:
		stun_timer -= delta
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	if player == null or not is_instance_valid(player): return

	# 低吼：4~8 秒随机一次，按距离衰减（AudioManager 内部还有全局限流）
	if _growl_cd > 0.0:
		_growl_cd -= delta
		if _growl_cd <= 0.0:
			_growl_cd = randf_range(4.0, 8.0)
			var gdist: float = global_position.distance_to(player.global_position)
			if gdist < 26.0:
				AudioManager.play_growl(-12.0 - gdist * 0.6, randf_range(0.85, 1.15))

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()

	# 吐酸者：独立行为分支（不参与通用的追击/近战逻辑）
	if zombie_type == "spitter":
		_spitter_think(delta, dist, to_player)
		move_and_slide()
		return

	# 双 BOSS 变体：行为独立于三阶段系统（无尽模式专属）
	if zombie_type == "boss" and boss_variant != "":
		_boss_variant_think(delta, dist, to_player)
		move_and_slide()
		return

	# BOSS技能冷却
	if boss_skill_cd > 0:
		boss_skill_cd -= delta

	# charger：进入10m触发冲刺，触发后不退回（只置位、不重置），持续追踪玩家实时位置
	if zombie_type == "charger":
		if not charging and dist <= CHARGER_TRIGGER_DIST:
			charging = true
			_charger_set_sprint_visual(true)
		# 撞到玩家 1.8m 内自爆（优先于任何近战逻辑）
		if not exploded and dist <= CHARGER_BLAST_DIST:
			# 把判定帧的 dist 传入，保证判定与伤害用同一个距离（move_and_slide 会在同帧稍后推进位置）
			_charger_explode(dist)
			return

	if dist > attack_range:
		var dir := to_player.normalized()
		var move_speed: float = speed
		# BOSS冲刺
		if zombie_type == "boss" and boss_state == 1:
			move_speed = speed * 4.0
			boss_state = 0
		# charger冲刺：每帧用最新玩家位置重算方向，所以是追踪而非直线
		if zombie_type == "charger" and charging:
			move_speed = CHARGER_CHARGE_SPEED * wave_speed_mult
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
		walk_time += delta * (11.0 if zombie_type == "charger" and charging else 7.0)
		# 走路动画：腿大步迈，臂前伸摆动，身体前倾
		var swing := sin(walk_time)
		leg_l.rotation.x = -swing * 0.6
		leg_r.rotation.x = swing * 0.6
		arm_l.rotation.x = 1.2 + swing * 0.2  # 手臂前伸够人
		arm_r.rotation.x = 1.2 - swing * 0.2
		head_node.rotation.x = -0.15  # 头微低
		torso.rotation.x = 0.1 if zombie_type != "charger" or not charging else 0.35  # 冲刺时更前倾
		torso.position.y = 1.25 + abs(sin(walk_time)) * 0.03
	else:
		velocity.x = 0; velocity.z = 0
		# 攻击：双臂前伸抓
		arm_l.rotation.x = 1.5
		arm_r.rotation.x = 1.5
		if zombie_type == "exploder" and not exploded:
			_explode()
		elif can_attack:
			_attack()

	# BOSS：阶段判定 + 分阶段技能
	if zombie_type == "boss":
		_boss_update_phase()
		if boss_phase >= 3:
			# 三阶段：原地狂暴，只靠地面红圈输出
			velocity.x = 0.0
			velocity.z = 0.0
			_red_circle_cd -= delta
			if _red_circle_cd <= 0.0:
				_red_circle_cd = BOSS_CIRCLE_INTERVAL
				_spawn_red_circle()
		elif boss_skill_cd <= 0.0 and dist < 20.0:
			if boss_phase == 2:
				# 二阶段：召唤被替换为八连酸液环
				_boss_acid_ring()
				boss_skill_cd = 6.0
			else:
				var roll: float = randf()
				if roll < 0.3:
					boss_state = 1  # 冲刺
					boss_skill_cd = 5.0
				elif roll < 0.6:
					_boss_summon()
					boss_skill_cd = 8.0
				else:
					_boss_roar()
					boss_skill_cd = 10.0

	move_and_slide()

func _boss_summon() -> void:
	# 召唤2个runner
	var wm := get_parent()
	if wm and wm.has_method("_spawn_zombie"):
		for i in range(2):
			var offset := Vector3(randf_range(-3,3), 1.0, randf_range(-3,3))
			wm._spawn_zombie("runner", global_position + offset)
	# 召唤提示光
	var flash := OmniLight3D.new()
	flash.light_color = Color(1,0.2,0.5)
	flash.light_energy = 3.0
	flash.omni_range = 4.0
	get_parent().add_child(flash)
	flash.global_position = global_position
	# 补间绑定到 flash 自身：丧尸会被对象池回收（process_mode 置 DISABLED），
	# 绑在丧尸上的补间会随之冻结，灯就永久挂在场上了
	var tw := flash.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(flash, "light_energy", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)

func _boss_roar() -> void:
	# 咆哮：减速玩家3秒
	if player and player.has_method("add_slow"):
		player.add_slow(3.0)
	# 咆哮冲击波光
	var flash := OmniLight3D.new()
	flash.light_color = Color(1,0.8,0.2)
	flash.light_energy = 4.0
	flash.omni_range = 8.0
	get_parent().add_child(flash)
	flash.global_position = global_position
	var tw := flash.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(flash, "light_energy", 0.0, 0.6)
	tw.tween_callback(flash.queue_free)

# ===== BOSS 三阶段 =====
func _boss_update_phase() -> void:
	var ratio: float = hp / max(max_hp, 1.0)
	var want: int = 1
	if ratio < 0.25:
		want = 3
	elif ratio < 0.50:
		want = 2
	if want == boss_phase:
		return
	boss_phase = want
	var hud := get_tree().get_first_node_in_group("hud")
	if want == 2:
		speed *= 1.2   # 二阶段：速度 +20%
		boss_skill_cd = 0.0
		if hud and hud.has_method("show_center"):
			hud.show_center("BOSS 二阶段 · 酸液环", 2.5)
	else:
		_red_circle_cd = 1.0
		if hud and hud.has_method("show_center"):
			hud.show_center("BOSS 狂暴 · 地面红圈爆发", 2.5)

func _boss_acid_ring() -> void:
	# 一圈 8 颗酸液球，呈放射状抛出
	for i in range(8):
		var ang: float = TAU * float(i) / 8.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var g: RigidBody3D = ACID_SCENE.instantiate()
		get_tree().current_scene.add_child(g)
		var from: Vector3 = global_position + dir * 1.2 + Vector3.UP * 1.5
		g.global_position = from
		_paint_acid(g)
		g.set("acid", true)
		g.set("timer", 4.0)
		g.linear_velocity = dir * 9.0 + Vector3.UP * 2.0
		g.continuous_cd = true

func _spawn_red_circle() -> void:
	# 在玩家当前位置画红圈，1 秒后引爆（玩家有时间走出去）
	if player == null or not is_instance_valid(player):
		return
	var pos: Vector3 = player.global_position
	pos.y = 0.03
	var mark := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = BOSS_CIRCLE_RADIUS
	cyl.bottom_radius = BOSS_CIRCLE_RADIUS
	cyl.height = 0.04
	mark.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.15, 0.10, 0.38)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.10, 0.05)
	m.emission_energy_multiplier = 1.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark.material_override = m
	get_tree().current_scene.add_child(mark)
	mark.global_position = pos
	# 补间挂在 mark 自己身上；爆破逻辑走 GameState（autoload），
	# 这样即使 BOSS 在 1 秒内先死，回调也不会碰到已释放实例
	var tw := mark.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(mark, "scale", Vector3(1.15, 1.0, 1.15), BOSS_CIRCLE_DELAY)
	tw.tween_callback(func():
		GameState.blast_circle(pos, BOSS_CIRCLE_RADIUS, BOSS_CIRCLE_DAMAGE)
		if is_instance_valid(mark):
			mark.queue_free()
	)

func _paint_acid(g: Node) -> void:
	var mesh := g.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.9, 0.2)
	m.emission_enabled = true
	m.emission = Color(0.3, 0.9, 0.15)
	m.emission_energy_multiplier = 1.5
	mesh.material_override = m

func _attack() -> void:
	can_attack = false
	$AttackTimer.start()
	if player and player.has_method("take_damage"):
		player.take_damage(damage)
		# 吸血词缀：每次抓到玩家回复 20 点
		if is_elite and affix == "lifesteal":
			hp = min(max_hp, hp + 20.0)

# ===== 吐酸者行为 =====
func _spitter_think(delta: float, dist: float, to_player: Vector3) -> void:
	if _spit_cd > 0.0:
		_spit_cd -= delta

	# 始终面向玩家（水平朝向）
	if dist > 0.01:
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
	var dir: Vector3 = to_player.normalized()

	# 前摇中：站定蓄力，结束瞬间发射
	if _spit_windup > 0.0:
		_spit_windup -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		torso.rotation.x = 0.28
		arm_l.rotation.x = 1.8
		arm_r.rotation.x = 1.8
		if _spit_windup <= 0.0:
			_spit_projectile()
		return

	if dist > SPIT_FAR:
		# 太远：靠近
		velocity.x = dir.x * speed * wave_speed_mult
		velocity.z = dir.z * speed * wave_speed_mult
		_spitter_walk(delta)
	elif dist < SPIT_NEAR:
		# 太近：后撤（速度打折，避免看起来像逃跑）
		velocity.x = -dir.x * speed * 0.7 * wave_speed_mult
		velocity.z = -dir.z * speed * 0.7 * wave_speed_mult
		_spitter_walk(delta)
	else:
		# 射程带内：站定，冷却好了就起手
		velocity.x = 0.0
		velocity.z = 0.0
		torso.rotation.x = 0.1
		if _spit_cd <= 0.0:
			_spit_windup = SPIT_WINDUP

func _spitter_walk(delta: float) -> void:
	walk_time += delta * 7.0
	var swing := sin(walk_time)
	leg_l.rotation.x = -swing * 0.6
	leg_r.rotation.x = swing * 0.6
	arm_l.rotation.x = 1.2 + swing * 0.2
	arm_r.rotation.x = 1.2 - swing * 0.2
	torso.rotation.x = 0.1

func _spit_projectile() -> void:
	_spit_cd = SPIT_COOLDOWN
	torso.rotation.x = 0.0
	if player == null or not is_instance_valid(player):
		return
	var g: RigidBody3D = ACID_SCENE.instantiate()
	get_tree().current_scene.add_child(g)  # 先入树，global_position 才生效

	var forward: Vector3 = player.global_position - global_position
	forward.y = 0.0
	forward = forward.normalized()
	# 从身前上方生成，避免与自身胶囊体重叠导致瞬间引爆
	var from: Vector3 = global_position + forward * 1.0 + Vector3.UP * 1.5
	g.global_position = from

	# 绿色酸液外观
	_paint_acid(g)

	# 解抛物线：给定飞行时间 t，反算水平速度与上抛初速，保证落点落在玩家脚下
	var target: Vector3 = player.global_position
	var flat: Vector3 = target - from
	flat.y = 0.0
	var d: float = flat.length()
	var t: float = clamp(d / 14.0, 0.6, 1.4)
	var horiz: Vector3 = flat.normalized() * (d / t)
	var up: float = (target.y - from.y + 0.5 * gravity * t * t) / t

	g.set("acid", true)
	g.set("timer", 3.5)  # 万一没落地，兜底炸掉
	g.linear_velocity = horiz + Vector3.UP * up
	g.continuous_cd = true

# ===== 无尽双 BOSS 变体（奔跑型 / 吐酸型）=====
func apply_boss_variant(v: String) -> void:
	# 必须在 reset_for_spawn() 之后调用：reset 会把 boss_variant 清空
	boss_variant = v
	match v:
		"charger":
			speed *= 1.7
			max_hp *= 0.85
			hp = max_hp
			_apply_body_visual(Color(0.95, 0.22, 0.10), Color(1.0, 0.55, 0.20), 2.6, 3.0)
		"spitter":
			speed *= 0.75
			max_hp *= 0.90
			hp = max_hp
			_apply_body_visual(Color(0.30, 0.75, 0.22), Color(0.55, 1.00, 0.40), 2.4, 3.0)

func _boss_variant_think(delta: float, dist: float, to_player: Vector3) -> void:
	if player == null or not is_instance_valid(player):
		return
	if dist > 0.01:
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
	var dir: Vector3 = to_player.normalized()

	if boss_variant == "charger":
		# 冲锋型：不停歇地撞过来，近身接通用近战（伤害已吃波次修饰）
		velocity.x = dir.x * speed * 2.0 * wave_speed_mult
		velocity.z = dir.z * speed * 2.0 * wave_speed_mult
		_spitter_walk(delta)   # 复用通用迈步动画
		torso.rotation.x = 0.3
		if dist <= attack_range and can_attack:
			_attack()
		return

	# 吐酸型：保持在 9~16 米抛酸，并周期性放酸液环
	if _spit_cd > 0.0:
		_spit_cd -= delta
	if _acid_ring_cd > 0.0:
		_acid_ring_cd -= delta
	if dist > 16.0:
		velocity.x = dir.x * speed * wave_speed_mult
		velocity.z = dir.z * speed * wave_speed_mult
		_spitter_walk(delta)
	elif dist < 9.0:
		velocity.x = -dir.x * speed * 0.8 * wave_speed_mult
		velocity.z = -dir.z * speed * 0.8 * wave_speed_mult
		_spitter_walk(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		torso.rotation.x = 0.12
		if _spit_cd <= 0.0:
			_spit_projectile()   # 内部会把 _spit_cd 置为 SPIT_COOLDOWN
	if _acid_ring_cd <= 0.0:
		_acid_ring_cd = 8.0
		_boss_acid_ring()

func _explode() -> void:
	exploded = true
	# 谁死谁清理：若被猎手标记，自爆时清除
	if player and is_instance_valid(player) and player.get("marked_zombie") == self:
		player.set("marked_zombie", null)
	if player and global_position.distance_to(player.global_position) < 3.5:
		player.take_damage(50.0 * wave_damage_mult)  # 自爆伤害同样吃波次修饰
	var flash := OmniLight3D.new()
	flash.light_color = Color(1,0.5,0.1)
	flash.light_energy = 5.0
	flash.omni_range = 6.0
	get_parent().add_child(flash)
	flash.global_position = global_position
	# 自爆后本体会立刻回池（process_mode = DISABLED），补间必须绑在 flash 上才不会被冻结
	var tw := flash.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(flash, "light_energy", 0.0, 0.3)
	tw.tween_callback(flash.queue_free)
	# 统一死亡结算（计分 / 发 died 信号 / 脱离分组），随后回池
	if _begin_death():
		_death_tween = create_tween()
		_death_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_death_tween.tween_interval(0.05)
		_death_tween.tween_callback(_recycle_self)

func _charger_set_sprint_visual(on: bool) -> void:
	# 冲刺视觉：自发光翻倍（材质为共享缓存，同样只换不改）
	var mul: float = 2.0 if on else 1.0
	for child in get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = child.material_override
			if mat.emission_enabled:
				var base: float = 4.0 if (mat.emission.r > 0.8 and mat.emission.g > 0.5) else 2.0
				child.material_override = _make_mat(mat.albedo_color, mat.roughness, base * mul)

func _charger_explode(trigger_dist: float = -1.0) -> void:
	exploded = true
	# 谁死谁清理：若被猎手标记，自爆时清除
	if player and is_instance_valid(player) and player.get("marked_zombie") == self:
		player.set("marked_zombie", null)
	# 只炸玩家：以自身为球心做 4m 硬半径球体相交检测，>4m 一律无伤
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = CHARGER_HARD_RADIUS
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), global_position)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = [get_rid()]
	var hits: Array[Dictionary] = space.intersect_shape(params, 32)
	var dist_to_player: float = global_position.distance_to(player.global_position) if (player and is_instance_valid(player)) else 999.0
	var in_radius: bool = false
	for h in hits:
		var body: Object = h.get("collider")
		if body and body.is_in_group("player"):
			in_radius = true
			break
	# 伤害距离：撞击路径用触发帧的 dist（与 1.8m 判定同源）；手动调用时退回当前实际距离
	var dmg_dist: float = trigger_dist if trigger_dist >= 0.0 else dist_to_player
	# 伤害 80→20 线性衰减：80 - d*15（d≤4）
	if in_radius and dmg_dist <= CHARGER_HARD_RADIUS and player.has_method("take_damage"):
		var dmg: float = max(CHARGER_MAX_DMG - dmg_dist * CHARGER_DMG_FALLOFF, 20.0)
		player.take_damage(dmg * wave_damage_mult)  # 冲刺自爆同样吃波次修饰
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.5, 0.1)
	flash.light_energy = 8.0
	flash.omni_range = 8.0
	get_parent().add_child(flash)
	flash.global_position = global_position
	# 撞击自爆后立刻回池，补间绑在 flash 上才不会随本体冻结
	var tw := flash.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)
	# 统一死亡结算，随后回池
	if _begin_death():
		_death_tween = create_tween()
		_death_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_death_tween.tween_interval(0.05)
		_death_tween.tween_callback(_recycle_self)

func take_damage(amount: float, weapon_type: String = "pistol") -> void:
	if is_dead: return  # 已死（可能已被回收进池）不再结算，防重复计分与重复掉落
	hp -= amount
	# 顿帧：只在「重击」或「击杀」时触发。
	# 若每次命中都顿帧，冲锋枪 10 发/秒会把画面卡成幻灯片
	if hp <= 0.0 or amount >= 40.0:
		GameState.hit_stop(0.03, 0.05)
	if hp <= 0: die()

func die() -> void:
	# 统一死亡入口；重复调用会被 _begin_death 拦掉
	if not _begin_death():
		return
	GameState.combo += 1
	GameState.combo_timer = 3.0
	if randf() < 0.3:
		var drop: String = ["ammo","medkit","speed","grenade"].pick_random()
		_spawn_drop(drop)
	# 血晶：局外成长货币，掉落率较低，越打越有积累感
	# 「血晶共鸣」卡通过 up_crystal_mult 把基础 12% 翻倍
	var crystal_chance: float = 0.12
	if player and is_instance_valid(player) and player.get("up_crystal_mult") != null:
		crystal_chance *= float(player.get("up_crystal_mult"))
	if randf() < crystal_chance:
		_spawn_drop("crystal")
	# 倒地动画播完再回池（不再 queue_free）
	_death_tween = create_tween()
	# 即使此刻场景被暂停（清场触发升级面板），也要把回收走完，否则会留下站立尸体
	_death_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_death_tween.tween_property(self, "rotation:x", -PI/2, 0.3)
	_death_tween.tween_callback(_recycle_self)

# ===== 池化支持 =====
func _begin_death() -> bool:
	# 返回 false 表示已经死过，调用方应直接返回，避免重复计分 / 重复发信号
	if is_dead:
		return false
	is_dead = true
	# 立刻脱离 zombie 组：AI 选怪、射线命中、手雷范围查询都会马上忽略它
	remove_from_group("zombie")
	# 死亡瞬间关碰撞：尸体不挡子弹，也不会被范围查询二次计入
	collision_layer = 0
	collision_mask = 0
	# 谁死谁清理：若被猎手标记，死亡时清除
	if player and is_instance_valid(player) and player.get("marked_zombie") == self:
		player.set("marked_zombie", null)
	GameState.kills += 1
	# 击杀联动：玩家的「战地急救」「连锁爆裂」卡依赖这个回调
	if player and is_instance_valid(player) and player.has_method("on_zombie_killed"):
		player.on_zombie_killed(global_position)
	# 精英击杀奖励（掉落 + 提示）
	if is_elite:
		_on_elite_killed()
	# 分裂词缀：必须在 died.emit() 之前生成子代，
	# 否则本只死亡会把 zombies_alive 减到 0，误判清场并刷出传送门
	if is_elite and affix == "split":
		_spawn_split_children()
	died.emit()
	return true

func _recycle_self() -> void:
	if is_instance_valid(self):
		ObjectPool.recycle(self)

func on_recycled() -> void:
	# 由 ObjectPool 在回收时调用：把节点收拾成「干净的待用状态」
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	remove_from_group("zombie")

func reset_for_spawn() -> void:
	# 由 WaveManager 在取出后调用（此时 zombie_type 与 position 已设置好）
	is_dead = false
	exploded = false
	charging = false
	stun_timer = 0.0
	walk_time = 0.0
	can_attack = true
	boss_state = 0
	boss_skill_cd = 0.0
	boss_phase = 1
	boss_variant = ""
	_acid_ring_cd = 0.0
	_red_circle_cd = 0.0
	is_elite = false
	affix = ""
	_spit_cd = 0.0
	_spit_windup = 0.0
	_growl_cd = randf_range(2.0, 6.0)  # 首次低吼别紧贴出场，避免一波刷怪同时吼
	wave_speed_mult = 1.0
	wave_damage_mult = 1.0
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	scale = Vector3.ONE  # _configure_type 会给 tank/boss 重新放大
	add_to_group("zombie")
	# 玩家引用可能因重开场景而失效，重新取一次
	player = get_tree().get_first_node_in_group("player")
	# 先还原普通配色，再按新类型上色——否则会残留上一条命的花色
	_reset_body_visual()
	_configure_type()
	hp = max_hp

func force_recycle() -> void:
	# 调试 / 强制清场：不结算掉落与击杀，直接回池
	is_dead = true
	remove_from_group("zombie")
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	ObjectPool.recycle(self)

func _reset_body_visual() -> void:
	# 把直接子节点（骨盆/躯干/双肩）还原成 _build_body 时的初始材质
	for child in get_children():
		var mi := child as MeshInstance3D
		if mi and mi.has_meta("base_mat"):
			mi.material_override = mi.get_meta("base_mat") as Material

# ===== 精英怪 =====
func make_elite(a: String) -> void:
	# 必须在 reset_for_spawn() 之后调用：在基线数值之上叠加精英加成
	is_elite = true
	affix = a
	scale *= 1.2
	max_hp *= 2.0
	hp = max_hp
	match a:
		"frenzy":
			speed *= 1.4
		_:
			pass
	_apply_affix_visual()

func _apply_affix_visual() -> void:
	# 复用统一的换色管线，仅覆盖直接子节点的材质
	match affix:
		"frenzy":
			_apply_body_visual(Color(0.95, 0.10, 0.10), Color(1.0, 0.30, 0.20), 2.6, 3.0)
		"lifesteal":
			_apply_body_visual(Color(0.20, 0.90, 0.35), Color(0.50, 1.00, 0.50), 2.4, 3.0)
		"split":
			_apply_body_visual(Color(0.60, 0.25, 0.90), Color(0.80, 0.50, 1.00), 2.4, 3.0)

func _affix_name() -> String:
	return str(ELITE_AFFIXES.get(affix, "精英"))

func _on_elite_killed() -> void:
	# 必掉一个补给 + 一颗血晶：精英是主要的血晶来源
	_spawn_drop("medkit" if randf() < 0.5 else "ammo")
	_spawn_drop("crystal")
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_center"):
		hud.show_center("击杀【%s】精英丧尸" % _affix_name(), 2.0)

func _spawn_split_children() -> void:
	var wm := get_parent()
	if wm == null or not wm.has_method("_spawn_zombie"):
		return
	for i in range(2):
		var off := Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
		# allow_elite = false：分裂出的子代不再滚精英，否则会无限套娃
		wm._spawn_zombie("normal", global_position + off, false)

func _spawn_drop(type: String) -> void:
	var drop := Area3D.new()
	drop.add_to_group("drop")  # 换图时由 WaveManager 统一清理，不让上一张图的掉落物跟过去
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4,0.3,0.4)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	match type:
		"ammo": mat.albedo_color = Color(0.8,0.65,0.3)
		"medkit": mat.albedo_color = Color(0.9,0.2,0.2)
		"speed": mat.albedo_color = Color(0.2,0.8,0.9)
		"grenade": mat.albedo_color = Color(0.5,0.5,0.2)
		"crystal": mat.albedo_color = Color(0.55, 0.85, 1.0)  # 血晶：冷白蓝，和补给区分开
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.8 if type == "crystal" else 0.5
	mesh.material_override = mat
	drop.add_child(mesh)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(0.6,0.5,0.6)
	col.shape = cs
	drop.add_child(col)
	drop.body_entered.connect(func(body):
		if body.is_in_group("player"):
			match type:
				"ammo": body.add_ammo(30)
				"medkit": body.add_hp(40)
				"speed": body.add_speed_boost(20.0)
				"grenade": body.add_grenade(1)
				"crystal": body.add_crystal(1)
			AudioManager.play_pickup()
			drop.queue_free()
	)
	var host: Node = get_parent()
	if host == null:
		# 极端情况（丧尸已在回收流程中）没有父节点可挂，直接丢弃，避免残留一个游离节点
		drop.queue_free()
		return
	host.add_child(drop)
	drop.global_position = global_position  # 入树后再设全局坐标，父节点带变换时也不会错位

func _on_attack_timer_timeout() -> void:
	can_attack = true
