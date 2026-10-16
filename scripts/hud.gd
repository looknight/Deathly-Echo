extends CanvasLayer
## HUD：血条、弹药、波次、小地图、BOSS血条、连杀

var hp_bar: ProgressBar
var hp_txt: Label
var ammo_cur: Label
var ammo_res: Label
var weapon_name: Label
var grenade_txt: Label
var wave_txt: Label
var map_txt: Label
var kill_txt: Label
var center_msg: Label
var skill_cd_txt: Label
var crosshair: Label
var boss_bar: ProgressBar
var boss_panel: PanelContainer

var hit_marker_timer: float = 0.0

var player: Node3D
var boss_zombie: Node3D

func _ready() -> void:
	add_to_group("hud")
	# 硬编码路径找节点，失败就 null
	hp_bar = get_node_or_null("UI/HPPanel/VB/HPBar") as ProgressBar
	hp_txt = get_node_or_null("UI/HPPanel/VB/HPTxt") as Label
	ammo_cur = get_node_or_null("UI/AmmoPanel/AB/AmmoRow/AmmoCur") as Label
	ammo_res = get_node_or_null("UI/AmmoPanel/AB/AmmoRow/AmmoRes") as Label
	weapon_name = get_node_or_null("UI/AmmoPanel/AB/WeaponName") as Label
	grenade_txt = get_node_or_null("UI/AmmoPanel/AB/GrenadeTxt") as Label
	wave_txt = get_node_or_null("UI/TopBar/HB/WaveTxt") as Label
	map_txt = get_node_or_null("UI/TopBar/HB/MapTxt") as Label
	kill_txt = get_node_or_null("UI/TopBar/HB/KillTxt") as Label
	center_msg = get_node_or_null("UI/CenterMsg") as Label
	skill_cd_txt = get_node_or_null("UI/SkillCd") as Label
	crosshair = get_node_or_null("UI/Crosshair") as Label
	boss_bar = get_node_or_null("UI/BossPanel/BV/BossBar") as ProgressBar
	boss_panel = get_node_or_null("UI/BossPanel") as PanelContainer
	# 自己找玩家
	player = get_tree().get_first_node_in_group("player")

func setup(p: Node3D) -> void:
	player = p

func set_boss(b: Node3D) -> void:
	boss_zombie = b
	if boss_panel: boss_panel.visible = true

func _process(delta: float) -> void:
	# 如果 player 还没连上，再试一次
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null: return
	if hp_bar: hp_bar.value = player.hp
	if hp_txt: hp_txt.text = "%d / %d" % [int(player.hp), int(player.max_hp)]
	if ammo_cur: ammo_cur.text = str(player.mag)
	if ammo_res: ammo_res.text = "/ %d" % player.reserve
	if weapon_name: weapon_name.text = player.WEAPONS[player.current_weapon].name
	if grenade_txt: grenade_txt.text = "手雷: %d" % player.grenades
	if skill_cd_txt:
		if player.skill_cd > 0:
			skill_cd_txt.text = "F 技能: %.1fs" % player.skill_cd
		else:
			skill_cd_txt.text = "F 技能: 就绪"
	if wave_txt: wave_txt.text = "第 %d/%d 波" % [GameState.wave, GameState.max_waves]
	if map_txt: map_txt.text = GameState.MAP_NAMES[GameState.map_index] if GameState.map_index < GameState.MAP_NAMES.size() else ""
	if kill_txt: kill_txt.text = "击杀 %d" % GameState.kills
	# 命中标记闪烁
	if hit_marker_timer > 0:
		hit_marker_timer -= delta
		if crosshair:
			crosshair.text = "X"
			crosshair.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	else:
		if crosshair:
			crosshair.text = "+"
			crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	# 连杀计时清零
	if GameState.combo_timer > 0:
		GameState.combo_timer -= delta
		if GameState.combo_timer <= 0:
			GameState.combo = 0
	if boss_zombie and is_instance_valid(boss_zombie):
		if boss_bar: boss_bar.value = boss_zombie.hp
	elif boss_panel and boss_panel.visible:
		boss_panel.visible = false
	# 死亡提示
	if player.game_over and center_msg:
		center_msg.text = "你死了 · 按 R 重新开始"
		center_msg.modulate.a = 1.0
	# 暂停提示
	if get_tree().paused and center_msg:
		center_msg.text = "已暂停 · 按 Esc 继续"
		center_msg.modulate.a = 1.0

func show_center(text: String, duration: float = 2.0) -> void:
	if not center_msg: return
	center_msg.text = text
	center_msg.modulate.a = 1.0
	var tw: Tween = create_tween()
	tw.tween_interval(duration)
	tw.tween_property(center_msg, "modulate:a", 0.0, 0.5)

func show_hit_marker() -> void:
	hit_marker_timer = 0.15
