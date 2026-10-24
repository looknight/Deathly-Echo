extends Node3D
## 波次管理器：8张地图轮换、10波、BOSS战、过关门

@export var zombie_scene: PackedScene
@export var player: CharacterBody3D
@export var hud: CanvasLayer

const BARREL_SCRIPT: Script = preload("res://scripts/barrel.gd")
const SPIKE_SCRIPT: Script = preload("res://scripts/spike_trap.gd")
const GAS_TANK_SCRIPT: Script = preload("res://scripts/gas_tank.gd")
const ELITE_CHANCE: float = 0.20
const ELITE_AFFIXES: Array[String] = ["frenzy", "split", "lifesteal"]

var zombies_alive: int = 0
var between_waves: bool = false
var map_holder: Node3D

# ===== 波次修饰表（全局）：按波次查表，缺省一律中性值 1.0 =====
# count_mult 数量倍率 / hp_mult 血量倍率 / speed_mult 移动倍率 / damage_mult 伤害倍率
const WAVE_MODS: Dictionary = {
	3: {"name": "尸潮", "count_mult": 2.5, "hp_mult": 0.8, "speed_mult": 1.0, "damage_mult": 1.0},
	9: {"name": "狂暴", "count_mult": 1.0, "hp_mult": 1.0, "speed_mult": 1.4, "damage_mult": 1.5},
}
# 当前波的修饰值：每波开头重算，_spawn_zombie 刷怪时套用
var cur_mod_name: String = ""
var cur_count_mult: float = 1.0
var cur_hp_mult: float = 1.0
var cur_speed_mult: float = 1.0
var cur_damage_mult: float = 1.0

# 8张地图配色: [地板色, 墙色, 雾色]
var MAP_STYLES: Array = [
	[Color(0.9,0.9,0.9), Color(0.5,0.5,0.5), Color(0.3,0.3,0.32)], # 街道
	[Color(0.9,0.9,0.9), Color(0.5,0.45,0.4), Color(0.25,0.22,0.2)], # 老巷
	[Color(0.9,0.9,0.9), Color(0.6,0.6,0.58), Color(0.3,0.3,0.32)], # 广场
	[Color(0.9,0.9,0.9), Color(0.45,0.45,0.5), Color(0.2,0.2,0.25)], # 地铁站
	[Color(0.9,0.9,0.9), Color(0.6,0.5,0.4), Color(0.25,0.22,0.2)], # 车库
	[Color(0.9,0.9,0.9), Color(0.5,0.55,0.6), Color(0.25,0.3,0.35)], # 码头
	[Color(0.9,0.9,0.9), Color(0.7,0.7,0.72), Color(0.3,0.3,0.32)], # 医院
	[Color(0.9,0.9,0.9), Color(0.6,0.5,0.3), Color(0.25,0.22,0.15)], # 工地
]

func _ready() -> void:
	map_holder = Node3D.new()
	add_child(map_holder)
	GameState.reset()
	# 直接从父节点找 Player 和 HUD（避免 export 引用丢失）
	if player == null:
		player = get_parent().get_node_or_null("Player") as CharacterBody3D
	if hud == null:
		hud = get_parent().get_node_or_null("HUD") as CanvasLayer
	# 修正玩家位置，确保在地面上
	if player:
		player.global_position = Vector3(0, 1.0, 20)
	if hud:
		var mm := hud.get_node_or_null("UI/Minimap")
		if mm and mm.has_method("set_player"): mm.set_player(player)
		hud.setup(player)
	_build_map(0)
	_start_wave()

# 清理跨图残留：掉落物挂在 WaveManager 下、投掷物挂在 current_scene 下，都不受 map_holder
# 的 queue_free 影响，不主动清就会跟着玩家进入下一张地图（悬在半空、堵路、白占内存）
func _clear_transients() -> void:
	for g in ["drop", "projectile"]:
		for n in get_tree().get_nodes_in_group(g):
			if is_instance_valid(n):
				n.queue_free()

func _build_map(map_idx: int) -> void:
	for c in map_holder.get_children(): c.queue_free()
	# 换图时一并清掉上一张图遗留的掉落物和飞行中的投掷物（它们并不在 map_holder 下）
	_clear_transients()
	var style: Array = MAP_STYLES[map_idx % MAP_STYLES.size()]
	# 地面
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var fm: BoxMesh = BoxMesh.new()
	fm.size = Vector3(80, 0.2, 80)
	floor_mesh.mesh = fm
	floor_mesh.position.y = -0.1
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = Color(0.95,0.95,0.95,1)
	fmat.roughness = 0.8
	fmat.metallic = 0.0
	fmat.emission_enabled = true
	fmat.emission = Color(0.95,0.95,0.95,1)
	fmat.emission_energy_multiplier = 0.5
	floor_mesh.material_override = fmat
	map_holder.add_child(floor_mesh)
	var fcol: StaticBody3D = StaticBody3D.new()
	var fshape: CollisionShape3D = CollisionShape3D.new()
	var fbox: BoxShape3D = BoxShape3D.new()
	fbox.size = fm.size
	fshape.shape = fbox
	fcol.add_child(fshape)
	map_holder.add_child(fcol)
	# 边界
	_add_boundary(-39, 0, 1, 80)
	_add_boundary(39, 0, 1, 80)
	_add_boundary(0, -39, 80, 1)
	_add_boundary(0, 39, 80, 1)
	# 墙布局
	var layouts: Array = [
		[[-15,-10],[15,-15],[0,5],[-20,15],[20,10]],
		[[-10,-5],[-10,10],[10,-10],[10,15],[0,-20]],
		[[-20,0],[20,0],[0,-15],[0,15],[-5,5]],
		[[-12,-12],[12,-12],[-12,12],[12,12],[0,0]],
		[[-18,-8],[18,-8],[0,0],[-8,18],[8,18]],
		[[-15,0],[15,0],[-10,-18],[10,18],[0,-5]],
		[[-8,-15],[8,-15],[-8,15],[8,15],[-18,0],[18,0]],
		[[-10,-10],[10,-10],[-10,10],[10,10],[0,0],[-20,20]],
	]
	for w in layouts[map_idx % layouts.size()]:
		_add_wall(w[0], w[1], style[1])
	# 加装饰：路障/油桶
	for i in range(6):
		_add_decoration(randf_range(-30,30), randf_range(-30,30), style[1])
	# 陷阱：每张图 2 个，地刺 / 毒气罐各 50%
	# 网格与碰撞由脚本自建，这里只负责实例化 + 定位（都挂 map_holder，换图自动清）
	for i in range(2):
		var px: float = randf_range(-28.0, 28.0)
		var pz: float = randf_range(-28.0, 28.0)
		if randf() < 0.5:
			var spike: Area3D = Area3D.new()
			spike.set_script(SPIKE_SCRIPT)
			spike.position = Vector3(px, 0.04, pz)
			map_holder.add_child(spike)
		else:
			var tank: StaticBody3D = StaticBody3D.new()
			tank.set_script(GAS_TANK_SCRIPT)
			tank.position = Vector3(px, 0.6, pz)
			map_holder.add_child(tank)

func _add_boundary(x: float, z: float, sx: float, sz: float) -> void:
	var b: StaticBody3D = StaticBody3D.new()
	b.position = Vector3(x, 2, z)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = Vector3(sx, 4, sz)
	cs.shape = bs
	b.add_child(cs)
	map_holder.add_child(b)

func _add_wall(x: float, z: float, wall_color: Color) -> void:
	var wall: MeshInstance3D = MeshInstance3D.new()
	var m: BoxMesh = BoxMesh.new()
	m.size = Vector3(3, 2.5, 0.5)
	wall.mesh = m
	wall.position = Vector3(x, 1.25, z)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = wall_color
	mat.roughness = 0.9
	wall.material_override = mat
	map_holder.add_child(wall)
	var col: StaticBody3D = StaticBody3D.new()
	col.position = wall.position
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = m.size
	cs.shape = bs
	col.add_child(cs)
	map_holder.add_child(col)

func _add_decoration(x: float, z: float, _base_color: Color) -> void:
	# 油桶：StaticBody3D 挂 barrel.gd（血量/爆炸/连锁），网格与碰撞体作为其子节点
	# 统一危险红，不再随地图墙色变化 —— 「红色桶=可爆炸」是玩家的既有认知，必须一眼可辨
	var barrel: StaticBody3D = StaticBody3D.new()
	barrel.set_script(BARREL_SCRIPT)
	barrel.position = Vector3(x, 0.45, z)

	# --- 桶身 ---
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.4
	cyl.height = 0.9
	mesh.mesh = cyl
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.09, 0.07)
	mat.roughness = 0.55
	mat.metallic = 0.35
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.05, 0.03)
	mat.emission_energy_multiplier = 0.45  # 暗环境里自带一点红光，远处也能看出是爆炸物
	mesh.material_override = mat
	barrel.add_child(mesh)

	# --- 顶盖：让轮廓多一层台阶，避免看起来像一根光秃秃的管子 ---
	var cap: MeshInstance3D = MeshInstance3D.new()
	var cap_cyl: CylinderMesh = CylinderMesh.new()
	cap_cyl.top_radius = 0.42
	cap_cyl.bottom_radius = 0.42
	cap_cyl.height = 0.06
	cap.mesh = cap_cyl
	var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.35, 0.07, 0.05)
	cap_mat.roughness = 0.6
	cap_mat.metallic = 0.45
	cap.material_override = cap_mat
	cap.position = Vector3(0, 0.45, 0)
	barrel.add_child(cap)

	# --- 两道环箍：微凸于桶身，强化「铁桶」的工业感 ---
	for i in range(2):
		var hoop: MeshInstance3D = MeshInstance3D.new()
		var hoop_cyl: CylinderMesh = CylinderMesh.new()
		hoop_cyl.top_radius = 0.42
		hoop_cyl.bottom_radius = 0.42
		hoop_cyl.height = 0.07
		hoop.mesh = hoop_cyl
		var hoop_mat: StandardMaterial3D = StandardMaterial3D.new()
		hoop_mat.albedo_color = Color(0.18, 0.05, 0.04)
		hoop_mat.roughness = 0.7
		hoop_mat.metallic = 0.5
		hoop.material_override = hoop_mat
		hoop.position = Vector3(0, 0.22 if i == 0 else -0.22, 0)
		barrel.add_child(hoop)

	# --- 中部警示带：黄色自发光，最容易在混战中抓住视线 ---
	var band: MeshInstance3D = MeshInstance3D.new()
	var band_cyl: CylinderMesh = CylinderMesh.new()
	band_cyl.top_radius = 0.415
	band_cyl.bottom_radius = 0.415
	band_cyl.height = 0.16
	band.mesh = band_cyl
	var band_mat: StandardMaterial3D = StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.95, 0.72, 0.12)
	band_mat.roughness = 0.5
	band_mat.emission_enabled = true
	band_mat.emission = Color(0.9, 0.6, 0.08)
	band_mat.emission_energy_multiplier = 0.8
	band.material_override = band_mat
	barrel.add_child(band)

	# --- 碰撞：与桶身同尺寸（0.4 / 0.9），子节点件不参与碰撞 ---
	var cs: CollisionShape3D = CollisionShape3D.new()
	var ss: CylinderShape3D = CylinderShape3D.new()
	ss.radius = 0.4
	ss.height = 0.9
	cs.shape = ss
	barrel.add_child(cs)
	map_holder.add_child(barrel)

func _start_wave() -> void:
	GameState.wave += 1
	var w: int = GameState.wave
	# 每波开始先清空 BOSS 血条：否则上一张图的 BOSS 条会跟着进新地图
	if hud and hud.has_method("clear_bosses"):
		hud.clear_bosses()
	# 先查当波修饰（放在 boss 分支之前，保证 boss 波也回填中性值，不残留上一波）
	_apply_wave_mod(w)
	# 第一分钟：开局只提示一次按键，降低新玩家上手门槛
	if w == 1 and hud and hud.has_method("show_hint"):
		hud.show_hint("WASD 移动 · 左键射击 · R 换弹 · F 技能 · 右键开镜 · G 手雷 · Esc 暂停", 8.0)
	if w % 5 == 0:
		between_waves = false  # BOSS 波直接开打，别让清场判定停留在波间等待状态
		# 无尽模式（>10 波）的每个 BOSS 波改成双 BOSS：一只冲锋型 + 一只吐酸型
		var dual: bool = w > GameState.max_waves
		var bosses: Array = []
		var boss: Node3D = _spawn_zombie("boss", Vector3(0, 0, -25))
		bosses.append(boss)
		if dual:
			# 变体必须在 _spawn_zombie 之后套（内部 reset_for_spawn 会清空 boss_variant）
			if boss.has_method("apply_boss_variant"):
				boss.call("apply_boss_variant", "charger")
			var boss2: Node3D = _spawn_zombie("boss", Vector3(0, 0, -14))
			if boss2.has_method("apply_boss_variant"):
				boss2.call("apply_boss_variant", "spitter")
			bosses.append(boss2)
			hud.show_center("WARNING: 双 BOSS · 冲锋 + 吐酸", 3.5)
		else:
			hud.show_center("WARNING: BOSS 出现", 3.0)
		# 传数组而不是单个引用：HUD 会为每个 BOSS 分配一条血条
		if hud:
			if hud.has_method("set_bosses"):
				hud.set_bosses(bosses)
			elif hud.has_method("set_boss"):
				hud.set_boss(boss)
		for i in range(2):
			_spawn_zombie("runner", Vector3(-15+i*30, 0, -25))
		return
	var count: int = int(round((4 + w * 2) * cur_count_mult))
	for i in range(count):
		var r: float = randf()
		var t: String = "normal"
		if w >= 2 and r < 0.3: t = "runner"
		if w >= 3 and r > 0.85: t = "exploder"
		if w >= 3 and r >= 0.35 and r < 0.45: t = "spitter"  # 第3波起10%：占用 0.35~0.45 空档
		if w >= 4 and r > 0.95: t = "tank"
		if w >= 4 and r >= 0.45 and r < 0.55: t = "charger"  # 第4波起10%：原属于normal的段位切给charger
		# 在玩家周围8-15米随机生成
		var angle: float = randf() * TAU
		var dist: float = 8.0 + randf() * 7.0
		var ppos: Vector3 = player.global_position
		var pos: Vector3 = Vector3(ppos.x + cos(angle)*dist, 1.0, ppos.z + sin(angle)*dist)
		_spawn_zombie(t, pos)
	if cur_mod_name == "":
		if w > GameState.max_waves:
			hud.show_center("无尽模式 · 第 %d 波 · %d 只丧尸" % [w, count], 2.5)
		else:
			hud.show_center("第 %d 波 · %d 只丧尸" % [w, count], 2.0)
	else:
		hud.show_center("第 %d 波 · %s · %d 只丧尸" % [w, cur_mod_name, count], 2.0)

func _apply_wave_mod(w: int) -> void:
	# 每波重算，查不到条目就回中性值，避免上一波修饰残留到下一波
	var mod: Dictionary = WAVE_MODS.get(w, {})
	cur_mod_name = str(mod.get("name", ""))
	cur_count_mult = float(mod.get("count_mult", 1.0))
	cur_hp_mult = float(mod.get("hp_mult", 1.0))
	cur_speed_mult = float(mod.get("speed_mult", 1.0))
	cur_damage_mult = float(mod.get("damage_mult", 1.0))
	# 无尽模式：第 11 波起，血量与伤害按 1.10^(w-10) 指数增长
	# （原为 1.15，第 20 波约 ×4 过陡；1.10 下第 20 波约 ×2.6，第 30 波约 ×6.7）
	if w > GameState.max_waves:
		var g: float = pow(1.10, float(w - GameState.max_waves))
		cur_hp_mult *= g
		cur_damage_mult *= g

func _spawn_zombie(t: String, pos: Vector3, allow_elite: bool = true) -> Node3D:
	# 从对象池取（池空时内部自动实例化，并直接挂到本节点下，不搬家）
	var z: Node3D = ObjectPool.spawn(zombie_scene, self) as Node3D
	z.set("zombie_type", t)
	z.position = Vector3(pos.x, 1.0, pos.z)
	# 复用实例必须按新类型重算属性与外观，并复位全部状态
	if z.has_method("reset_for_spawn"):
		z.reset_for_spawn()
	# 精英判定：第 4 波起 20%，BOSS 与分裂出的子代不参与
	if allow_elite and t != "boss" and GameState.wave >= 4 and randf() < ELITE_CHANCE:
		if z.has_method("make_elite"):
			z.make_elite(ELITE_AFFIXES.pick_random())
	# 死亡信号只连一次（池化后同一个实例会被反复使用）
	if not z.is_connected("died", _on_zombie_died):
		z.connect("died", _on_zombie_died)
	# 进树之后套修饰：_configure_type 会重置 max_hp/hp/speed，必须先刷完基线再乘
	if z.has_method("apply_wave_modifier"):
		z.apply_wave_modifier(cur_hp_mult, cur_speed_mult, cur_damage_mult)
	zombies_alive += 1
	return z

func _on_zombie_died() -> void:
	zombies_alive -= 1
	if GameState.combo >= 5:
		hud.show_center("%d 连杀!" % GameState.combo, 1.5)
	if zombies_alive <= 0 and not between_waves:
		between_waves = true
		# 清场即收起 BOSS 血条（此时 BOSS 已死，但引用还留在数组里）
		if hud and hud.has_method("clear_bosses"):
			hud.clear_bosses()
		# 无尽模式：打完第 10 波不再结算通关，直接继续下一波
		if GameState.wave == GameState.max_waves:
			hud.show_center("进入无尽模式！波次与强度将持续攀升", 3.5)
		# 生成传送门，玩家走进去进下一关
		_spawn_portal()
		hud.show_center("清场完成！走进绿色传送门", 3.0)
		_offer_upgrades()

var portal: Area3D = null

# ===== 波间三选一强化 =====
func _offer_upgrades() -> void:
	if hud == null or not hud.has_method("show_upgrades"):
		return
	# 从升级池随机抽 3 个不重复的
	var pool: Array = GameState.UPGRADE_POOL.duplicate()
	pool.shuffle()
	var picks: Array = []
	for i in range(min(3, pool.size())):
		picks.append(pool[i])
	hud.show_upgrades(picks)

# ===== 调试：清场并直接跳到下一个 BOSS 波（5 / 10）=====
func debug_jump_to_boss() -> void:
	for z in get_tree().get_nodes_in_group("zombie"):
		if is_instance_valid(z):
			# 回池而不是销毁：不结算击杀/掉落，也不触发 died 信号
			if z.has_method("force_recycle"):
				z.force_recycle()
			else:
				z.queue_free()
	zombies_alive = 0
	if portal:
		portal.queue_free()
		portal = null
	between_waves = false
	GameState.wave = 4 if GameState.wave < 5 else 9
	_start_wave()

func _spawn_portal() -> void:
	if portal: portal.queue_free()
	portal = Area3D.new()
	portal.position = Vector3(0, 1.0, -20)
	# 视觉：绿色发光圆柱
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.2
	cyl.height = 3.0
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 0.3)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.4
	mesh.material_override = mat
	portal.add_child(mesh)
	# 碰撞形状
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.5
	shape.height = 3.0
	col.shape = shape
	portal.add_child(col)
	# 进入检测
	portal.body_entered.connect(_on_portal_enter)
	add_child.call_deferred(portal)  # 延迟添加，避免 tree_exited 回调期间 add_child 报错

func _on_portal_enter(body: Node3D) -> void:
	if body == player:
		if portal: portal.queue_free()
		portal = null  # 立即置空，避免下一波 _spawn_portal 时持有已释放节点的悬空引用
		GameState.map_index = (GameState.map_index + 1) % 8
		_build_map(GameState.map_index)
		player.global_position = Vector3(0, 1.0, 20)
		between_waves = false
		_start_wave()
