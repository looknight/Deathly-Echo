extends Node3D
## 波次管理器：8张地图轮换、10波、BOSS战、过关门

@export var zombie_scene: PackedScene
@export var player: CharacterBody3D
@export var hud: CanvasLayer

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

func _build_map(map_idx: int) -> void:
	for c in map_holder.get_children(): c.queue_free()
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

func _add_decoration(x: float, z: float, base_color: Color) -> void:
	# 油桶
	var barrel: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.4
	cyl.height = 0.9
	barrel.mesh = cyl
	barrel.position = Vector3(x, 0.45, z)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = base_color.darkened(0.3)
	mat.roughness = 0.6
	mat.metallic = 0.3
	barrel.material_override = mat
	map_holder.add_child(barrel)
	var col: StaticBody3D = StaticBody3D.new()
	col.position = barrel.position
	var cs: CollisionShape3D = CollisionShape3D.new()
	var ss: CylinderShape3D = CylinderShape3D.new()
	ss.radius = 0.4
	ss.height = 0.9
	cs.shape = ss
	col.add_child(cs)
	map_holder.add_child(col)

func _start_wave() -> void:
	GameState.wave += 1
	var w: int = GameState.wave
	# 先查当波修饰（放在 boss 分支之前，保证 boss 波也回填中性值，不残留上一波）
	_apply_wave_mod(w)
	if w == 5 or w == 10:
		hud.show_center("WARNING: BOSS 出现", 3.0)
		var boss: Node3D = _spawn_zombie("boss", Vector3(0, 0, -25))
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
		if w >= 4 and r > 0.95: t = "tank"
		if w >= 4 and r >= 0.45 and r < 0.55: t = "charger"  # 第4波起10%：原属于normal的段位切给charger
		# 在玩家周围8-15米随机生成
		var angle: float = randf() * TAU
		var dist: float = 8.0 + randf() * 7.0
		var ppos: Vector3 = player.global_position
		var pos: Vector3 = Vector3(ppos.x + cos(angle)*dist, 1.0, ppos.z + sin(angle)*dist)
		_spawn_zombie(t, pos)
	if cur_mod_name == "":
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

func _spawn_zombie(t: String, pos: Vector3) -> Node3D:
	var z: Node3D = zombie_scene.instantiate()
	z.set("zombie_type", t)
	z.position = Vector3(pos.x, 1.0, pos.z)
	z.tree_exited.connect(_on_zombie_died)
	add_child(z)
	# 进树之后套修饰：_ready → _configure_type 会重置 max_hp/hp/speed，必须先刷完基线再乘
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
		if GameState.wave >= GameState.max_waves:
			GameState.game_won = true
			hud.show_center("通关！你活下来了", 5.0)
			return
		# 生成传送门，玩家走进去进下一关
		_spawn_portal()
		hud.show_center("清场完成！走进绿色传送门", 3.0)

var portal: Area3D = null

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
		GameState.map_index = (GameState.map_index + 1) % 8
		_build_map(GameState.map_index)
		player.global_position = Vector3(0, 1.0, 20)
		between_waves = false
		_start_wave()
