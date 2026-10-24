extends Node
## 全局游戏状态

var wave: int = 0
var max_waves: int = 10
var kills: int = 0
var combo: int = 0
var combo_timer: float = 0.0
var map_index: int = 0
var player_class: String = "assault"

# 升级面板是否打开：打开时屏蔽玩家输入，由 HUD 独占 1/2/3 与鼠标点击
var upgrade_open: bool = false

# ===== 全局命中顿帧 =====
var _hitstop_busy: bool = false

func hit_stop(duration: float = 0.03, scale: float = 0.05) -> void:
	# 放在 autoload 上执行：丧尸被对象池回收后，本协程不会因此中断
	if _hitstop_busy: return
	_hitstop_busy = true
	Engine.time_scale = scale
	# 第 4 个参数 ignore_time_scale 必须为 true，否则 0.03s 会被自己的慢放拉长 20 倍
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_busy = false

func blast_circle(pos: Vector3, radius: float, dmg: float) -> void:
	# BOSS 红圈引爆。放在 autoload 上：施法者可能先一步死亡，
	# 若把这段写在 zombie.gd 的延迟回调里，会调用到已释放实例。
	var scene := get_tree().current_scene
	if scene == null: return
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.25, 0.1)
	flash.light_energy = 9.0
	flash.omni_range = radius * 2.5
	scene.add_child(flash)
	flash.global_position = pos  # 先入树再设全局坐标
	var tw := flash.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(flash, "light_energy", 0.0, 0.3)
	tw.tween_callback(flash.queue_free)
	# 只打玩家：站圈里就吃满伤害，走出去就安全
	var p := get_tree().get_first_node_in_group("player")
	if p and is_instance_valid(p) and p.has_method("take_damage"):
		if pos.distance_to(p.global_position) <= radius:
			p.take_damage(dmg)

var MAP_NAMES: Array[String] = ["街道","老巷","广场","地铁站","车库","码头","医院","工地"]

# ===== 波间三选一升级 =====
# 用 var 而非 const：HUD / WaveManager 都通过 autoload 实例访问，属性访问最稳妥
var UPGRADE_POOL: Array[String] = [
	"dmg", "rate", "reload", "speed", "hp", "reserve", "grenade",
	"mag", "killboom", "launcher_mag", "overclock", "armor", "vamp", "steady", "greed",
]
var UPGRADES: Dictionary = {
	# --- 基础强化 ---
	"dmg":         {"name": "穿甲弹头", "desc": "全武器伤害 +20%"},
	"rate":        {"name": "快速抽机", "desc": "射速 +15%"},
	"reload":      {"name": "战术换弹", "desc": "换弹速度 +30%"},
	"speed":       {"name": "轻装疾行", "desc": "移动速度 +12%"},
	"hp":          {"name": "强化体质", "desc": "最大生命 +25 并回满"},
	"reserve":     {"name": "弹药背包", "desc": "备弹上限 +40%"},
	"grenade":     {"name": "手雷补给", "desc": "手雷 +2"},
	# --- 扩容与专精 ---
	"mag":         {"name": "弹匣扩容", "desc": "弹匣容量 +50%"},
	"launcher_mag":{"name": "榴弹扩容", "desc": "榴弹枪弹匣 +2"},
	# --- 双刃剑 ---
	"overclock":   {"name": "超频枪机", "desc": "射速 +25%，但伤害 -10%"},
	# --- 生存 ---
	"armor":       {"name": "复合护甲", "desc": "受到伤害 -15%"},
	"vamp":        {"name": "战地急救", "desc": "每次击杀回复 8 生命"},
	# --- 战斗流派 ---
	"killboom":    {"name": "连锁爆裂", "desc": "击杀引发 3 米小爆炸，35 伤害"},
	"steady":      {"name": "稳定枪管", "desc": "散射 -40%（打得更准）"},
	"greed":       {"name": "血晶共鸣", "desc": "血晶掉落率翻倍"},
}

# ===== 局外成长：血晶 =====
const SAVE_PATH: String = "user://zombie_save.json"
const SAVE_BACKUP: String = "user://zombie_save.bak.json"
# 存档结构版本：以后改动字段时靠它做迁移（当前 2 = 加入历史最佳）
const SAVE_VERSION: int = 2
# 用 var 而非 const：menu/hud 通过 autoload 实例访问该值，属性访问最稳妥
var MAX_META_LV: int = 5

var total_crystals: int = 0        # 已入库的血晶（跨局持久）
var run_crystals: int = 0          # 本局捡到、尚未结算的血晶
var run_damage: float = 0.0        # 本局造成总伤害（结算面板展示）
var run_time: float = 0.0          # 本局存活时间（秒）
var run_settled: bool = false      # 本局是否已入账，防止「死亡 + 返回菜单」重复结算

# ===== 历史最佳（持久化，用于「破纪录」反馈）=====
var best_wave: int = 0
var best_kills: int = 0
var best_time: float = 0.0
# 本次结算是否破了对应纪录（仅影响结算面板的高亮，不落盘）
var new_record_wave: bool = false
var new_record_kills: bool = false
var new_record_time: bool = false

var meta_dmg_lv: int = 0           # 永久伤害等级：每级 +10% 基础伤害
var meta_hp_lv: int = 0            # 永久生命等级：每级 +20 初始生命

# ===== 设置项（同样持久化）=====
var master_volume: float = 0.8     # 0..1，作用于 Master 总线
var mouse_sensitivity: float = 0.0025
var crosshair_color_idx: int = 0

var CROSSHAIR_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0, 0.92),
	Color(0.42, 1.0, 0.45, 0.95),
	Color(1.0, 0.32, 0.28, 0.95),
]
var CROSSHAIR_NAMES: Array[String] = ["白色", "绿色", "红色"]

var META_UPGRADES: Dictionary = {
	"dmg": {"name": "穿透弹芯", "desc": "全武器基础伤害 +10%", "base": 8, "step": 6},
	"hp":  {"name": "强健体魄", "desc": "初始最大生命 +20", "base": 10, "step": 8},
}

func _ready() -> void:
	load_game()
	apply_settings()

func _process(delta: float) -> void:
	# 存活计时：第一波开始后累加，死亡结算后停止。
	# autoload 默认 PROCESS_MODE_INHERIT，暂停时这里会自动停表。
	if wave > 0 and not run_settled:
		run_time += delta

func meta_level(id: String) -> int:
	if id == "dmg": return meta_dmg_lv
	if id == "hp": return meta_hp_lv
	return 0

func meta_cost(id: String) -> int:
	var info: Dictionary = META_UPGRADES.get(id, {})
	return int(info.get("base", 10)) + int(info.get("step", 6)) * meta_level(id)

func meta_dmg_mult() -> float:
	return 1.0 + 0.10 * float(meta_dmg_lv)

func meta_hp_bonus() -> float:
	return 20.0 * float(meta_hp_lv)

func buy_meta(id: String) -> bool:
	if not META_UPGRADES.has(id): return false
	if meta_level(id) >= MAX_META_LV: return false
	var cost: int = meta_cost(id)
	if total_crystals < cost: return false
	total_crystals -= cost
	if id == "dmg": meta_dmg_lv += 1
	elif id == "hp": meta_hp_lv += 1
	save_game()
	return true

func add_run_crystal(n: int = 1) -> void:
	run_crystals += n

func crosshair_color() -> Color:
	return CROSSHAIR_COLORS[clampi(crosshair_color_idx, 0, CROSSHAIR_COLORS.size() - 1)]

func apply_settings() -> void:
	# Master 总线索引恒为 0；AudioServer 用分贝，先做线性→分贝换算
	var bus: int = 0
	AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(max(master_volume, 0.0001)))

# 把本局血晶入账。重复调用安全（run_settled 保护）
func settle_run() -> void:
	if run_settled: return
	run_settled = true
	total_crystals += run_crystals
	# 纪录判定：严格大于才算破纪录（首次通关也自然成为纪录）
	new_record_wave = wave > best_wave
	new_record_kills = kills > best_kills
	new_record_time = run_time > best_time
	if new_record_wave: best_wave = wave
	if new_record_kills: best_kills = kills
	if new_record_time: best_time = run_time
	save_game()

func save_game() -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"crystals": total_crystals,
		"meta_dmg_lv": meta_dmg_lv,
		"meta_hp_lv": meta_hp_lv,
		"volume": master_volume,
		"sensitivity": mouse_sensitivity,
		"crosshair": crosshair_color_idx,
		"best_wave": best_wave,
		"best_kills": best_kills,
		"best_time": best_time,
	}
	# 写前备份上一份：写一半断电/崩溃时还有 .bak 可以回退
	if FileAccess.file_exists(SAVE_PATH):
		var old: String = FileAccess.get_file_as_string(SAVE_PATH)
		if old != "":
			var bak: FileAccess = FileAccess.open(SAVE_BACKUP, FileAccess.WRITE)
			if bak:
				bak.store_string(old)
				bak.close()
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		# 写不进去（权限/磁盘）不该影响游戏，静默降级即可
		push_warning("存档写入失败，错误码 %d" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}

func load_game() -> void:
	var d: Dictionary = _read_save(SAVE_PATH)
	if d.is_empty():
		d = _read_save(SAVE_BACKUP)   # 主档损坏时回退到备份
	if d.is_empty():
		return
	# 迁移入口：老存档没有 version 字段时按 1 处理，缺的字段一律走 get 默认值
	var _ver: int = int(d.get("version", 1))
	total_crystals = maxi(0, int(d.get("crystals", 0)))
	meta_dmg_lv = clampi(int(d.get("meta_dmg_lv", 0)), 0, MAX_META_LV)
	meta_hp_lv = clampi(int(d.get("meta_hp_lv", 0)), 0, MAX_META_LV)
	master_volume = clampf(float(d.get("volume", 0.8)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(d.get("sensitivity", 0.0025)), 0.0006, 0.0060)
	crosshair_color_idx = clampi(int(d.get("crosshair", 0)), 0, CROSSHAIR_COLORS.size() - 1)
	best_wave = maxi(0, int(d.get("best_wave", 0)))
	best_kills = maxi(0, int(d.get("best_kills", 0)))
	best_time = maxf(0.0, float(d.get("best_time", 0.0)))

func reset() -> void:
	wave = 0
	kills = 0
	combo = 0
	combo_timer = 0.0
	map_index = 0
	upgrade_open = false
	# 本局统计清零（血晶库与永久升级不重置）
	run_crystals = 0
	run_damage = 0.0
	run_time = 0.0
	run_settled = false
	new_record_wave = false
	new_record_kills = false
	new_record_time = false
	# 防御：万一在顿帧中途重开，别把慢放状态带进新一局
	Engine.time_scale = 1.0
	_hitstop_busy = false
