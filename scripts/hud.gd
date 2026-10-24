extends CanvasLayer
## HUD：血条、弹药、波次、小地图、BOSS血条、连杀
## + 开镜遮罩 / 暂停面板 / 波间三选一升级面板（均为运行时创建，不改场景）

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

# ===== BOSS 血条（支持同时多个：无尽模式的双 BOSS）=====
# boss_zombies 存当前场的 BOSS 引用；面板第 0 个复用场景里的 BossPanel，
# 之后的数量不足时从第 0 个 duplicate() 出来（保留同一套样式与子节点结构）
var boss_zombies: Array = []
var boss_panels: Array = []
var boss_bars: Array = []
var boss_names: Array = []
const BOSS_PANEL_TOP: float = 70.0
const BOSS_PANEL_H: float = 40.0
const BOSS_PANEL_GAP: float = 12.0

# ===== 叠加层 =====
var scope_overlay: Control
var pause_panel: Control
var upgrade_panel: Control
var gameover_panel: Control
var upgrade_open: bool = false
var upgrade_options: Array = []
var _card_rects: Array[Rect2] = []

# ===== 暂停面板设置项 =====
var settings_row: int = 0
const SETTING_COUNT: int = 3

# ===== 自绘准星 =====
var crosshair_node: Control
var crosshair_spread: float = 0.0   # 开火瞬间的额外扩散量（像素）

# ===== 开局提示条 =====
var hint_label: Label
var _hint_tween: Tween

# ===== 调试覆盖层（F3 切换）=====
var debug_label: Label
var _debug_timer: float = 0.0

# ===== 濒死暗角 =====
var vignette_overlay: Control
var vignette_alpha: float = 0.0
var damage_flash: float = 0.0
var _low_hp_time: float = 0.0
var _last_hp: float = -1.0

func _ready() -> void:
	# 暂停时 HUD 仍需刷新与接收输入（否则暂停面板与升级选择不会响应）
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	# 第 0 条血条直接用场景里的模板节点，其余按需 duplicate
	boss_panels.clear()
	boss_bars.clear()
	boss_names.clear()
	if boss_panel:
		boss_panel.visible = false   # 场景里默认可见的话会闪一帧
		boss_panels.append(boss_panel)
		boss_bars.append(boss_bar)
		boss_names.append(boss_panel.get_node_or_null("BV/BossName") as Label)
	# 自己找玩家
	player = get_tree().get_first_node_in_group("player")
	_build_overlays()

func setup(p: Node3D) -> void:
	player = p

# 兼容旧调用：单个 BOSS
func set_boss(b: Node3D) -> void:
	set_bosses([b])

# 主入口：传一个 BOSS 引用数组（普通波 1 个，无尽双 BOSS 2 个）
func set_bosses(list: Array) -> void:
	boss_zombies.clear()
	for b in list:
		if b != null and is_instance_valid(b):
			boss_zombies.append(b)
	_ensure_boss_panels(boss_zombies.size())
	_update_boss_bars()   # 立刻生效，不必等下一帧

# 清场 / 切场景 / 死亡时调用，立即收起所有血条
func clear_bosses() -> void:
	boss_zombies.clear()
	for p in boss_panels:
		if is_instance_valid(p):
			p.visible = false

# 面板数量不足时从模板复制（duplicate 保留 PanelContainer 样式与 BV/BossBar 结构）
func _ensure_boss_panels(n: int) -> void:
	if boss_panel == null:
		return
	var host: Node = boss_panel.get_parent()
	if host == null:
		return
	while boss_panels.size() < n:
		var idx: int = boss_panels.size()
		var p: PanelContainer = boss_panel.duplicate() as PanelContainer
		p.name = "BossPanel_%d" % idx   # 同名会触发 Godot 自动改名，显式命名更可控
		p.visible = false
		host.add_child(p)
		boss_panels.append(p)
		boss_bars.append(p.get_node_or_null("BV/BossBar") as ProgressBar)
		boss_names.append(p.get_node_or_null("BV/BossName") as Label)

# 每帧刷新：池化后的 BOSS 即使「已死」也仍然 is_instance_valid，必须额外判 is_dead
# 同时负责排位：只有可见的血条占位，死掉的那条不会留下空档
func _update_boss_bars() -> void:
	var slot: int = 0
	for i in range(boss_panels.size()):
		var p: Control = boss_panels[i]
		if not is_instance_valid(p):
			continue
		var alive: bool = false
		if i < boss_zombies.size():
			var b = boss_zombies[i]
			# 三个条件缺一不可：
			#   池化后已死的节点仍然 is_instance_valid → 必须看 is_dead
			#   死掉的 BOSS 可能被对象池再派生成普通丧尸 → 必须校验 zombie_type
			alive = (b != null and is_instance_valid(b)
				and not bool(b.get("is_dead"))
				and str(b.get("zombie_type")) == "boss")
		if p.visible != alive:
			p.visible = alive
		if not alive:
			continue
		var boss = boss_zombies[i]
		var bar: ProgressBar = boss_bars[i] if i < boss_bars.size() else null
		if bar:
			# 无尽模式血量远超场景里写死的 800，必须每帧同步上限，否则血条会一直是满的
			var mhp: float = maxf(float(boss.get("max_hp")), 1.0)
			bar.max_value = mhp
			bar.value = clampf(float(boss.get("hp")), 0.0, mhp)
		var nm: Label = boss_names[i] if i < boss_names.size() else null
		if nm:
			nm.text = _boss_title(boss)
		p.offset_top = BOSS_PANEL_TOP + float(slot) * (BOSS_PANEL_H + BOSS_PANEL_GAP)
		p.offset_bottom = p.offset_top + BOSS_PANEL_H
		slot += 1

func _boss_title(boss) -> String:
	var v: String = ""
	if boss != null and is_instance_valid(boss) and boss.get("boss_variant") != null:
		v = str(boss.get("boss_variant"))
	match v:
		"charger": return "BOSS · 冲锋"
		"spitter": return "BOSS · 吐酸"
	return "BOSS"

# ===== 叠加层构建 =====
func _build_overlays() -> void:
	# 濒死暗角放最底层（move_child 到 0），避免把血条等 HUD 一起压暗
	vignette_overlay = _make_overlay(_draw_vignette)
	move_child(vignette_overlay, 0)
	crosshair_node = _make_overlay(_draw_crosshair)
	crosshair_node.visible = true
	scope_overlay = _make_overlay(_draw_scope)
	pause_panel = _make_overlay(_draw_pause)
	upgrade_panel = _make_overlay(_draw_upgrades)
	gameover_panel = _make_overlay(_draw_gameover)  # 最后创建 = 最上层
	_build_hint_label()
	_build_debug_overlay()

# 调试覆盖层：F3 切换。给朋友内测时让他们截图这一行，比"有点卡"有用得多
func _build_debug_overlay() -> void:
	debug_label = Label.new()
	debug_label.position = Vector2(16, 56)
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_label.add_theme_font_size_override("font_size", 14)
	debug_label.add_theme_color_override("font_color", Color(0.82, 1.0, 0.82, 0.92))
	debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	debug_label.add_theme_constant_override("shadow_offset_x", 1)
	debug_label.add_theme_constant_override("shadow_offset_y", 1)
	debug_label.visible = false
	add_child(debug_label)

func _tick_debug(delta: float) -> void:
	if debug_label == null or not debug_label.visible:
		return
	_debug_timer -= delta
	if _debug_timer > 0.0:
		return
	# 0.25 秒刷新一次即可：既不会刷屏，也不会每帧拼字符串
	_debug_timer = 0.25
	var fps: int = int(Engine.get_frames_per_second())
	var zombies: int = get_tree().get_nodes_in_group("zombie").size()
	var calls: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	var vmem: float = float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0
	debug_label.text = "FPS %d  ·  波次 %d  ·  敌人 %d  ·  draw call %d  ·  对象 %d  ·  显存 %.0f MB" % [
		fps, GameState.wave, zombies, calls, objs, vmem]

# 开局按键提示：屏幕中下方的半透明单行文字（不参与鼠标事件）
func _build_hint_label() -> void:
	hint_label = Label.new()
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint_label.offset_bottom = -150.0   # 距屏幕底边 150px，避开弹药/手雷面板
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88, 0.88))
	hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	hint_label.add_theme_constant_override("shadow_offset_x", 2)
	hint_label.add_theme_constant_override("shadow_offset_y", 2)
	hint_label.modulate.a = 0.0
	add_child(hint_label)

func show_hint(text: String, duration: float = 6.0) -> void:
	if hint_label == null:
		return
	hint_label.text = text
	hint_label.modulate.a = 1.0
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(maxf(duration - 1.0, 0.1))
	_hint_tween.tween_property(hint_label, "modulate:a", 0.0, 1.0)
	if crosshair:
		crosshair.visible = false  # 改用自绘准星，隐藏原来的 "+" 标签

func _make_overlay(draw_fn: Callable) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	add_child(c)
	c.draw.connect(draw_fn)
	return c

func _overlay_size(c: Control) -> Vector2:
	var s: Vector2 = c.size
	if s.x <= 1.0 or s.y <= 1.0:
		s = get_viewport().get_visible_rect().size
	return s

# ===== 开镜 =====
func show_scope(on: bool) -> void:
	if scope_overlay:
		scope_overlay.visible = on
		if on:
			scope_overlay.queue_redraw()
	if crosshair_node:
		crosshair_node.visible = not on

func _draw_scope() -> void:
	var s: Vector2 = _overlay_size(scope_overlay)
	var c: Vector2 = s * 0.5
	var r: float = min(s.x, s.y) * 0.34
	var black := Color(0, 0, 0, 1)
	# 四块黑色遮罩，留出中央圆形镜片
	scope_overlay.draw_rect(Rect2(0, 0, s.x, c.y - r), black, true)
	scope_overlay.draw_rect(Rect2(0, c.y + r, s.x, s.y - (c.y + r)), black, true)
	scope_overlay.draw_rect(Rect2(0, c.y - r, c.x - r, 2.0 * r), black, true)
	scope_overlay.draw_rect(Rect2(c.x + r, c.y - r, s.x - (c.x + r), 2.0 * r), black, true)
	# 镜圈
	scope_overlay.draw_arc(c, r, 0.0, TAU, 72, Color(0.02, 0.02, 0.02), 5.0, true)
	scope_overlay.draw_arc(c, r - 3.0, 0.0, TAU, 72, Color(0.28, 0.28, 0.3), 1.0, true)
	# 十字分划
	var lc := Color(0.9, 0.9, 0.9, 0.85)
	scope_overlay.draw_line(Vector2(c.x - r, c.y), Vector2(c.x - 18, c.y), lc, 1.0)
	scope_overlay.draw_line(Vector2(c.x + 18, c.y), Vector2(c.x + r, c.y), lc, 1.0)
	scope_overlay.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y - 18), lc, 1.0)
	scope_overlay.draw_line(Vector2(c.x, c.y + 18), Vector2(c.x, c.y + r), lc, 1.0)
	scope_overlay.draw_circle(c, 2.0, lc)

# ===== 自绘准星：中心圆点 + 四短线，开火弹开 =====
func kick_crosshair(amount: float = 7.0) -> void:
	crosshair_spread = min(crosshair_spread + amount, 20.0)

func _draw_crosshair() -> void:
	if crosshair_node == null:
		return
	var s: Vector2 = _overlay_size(crosshair_node)
	var c: Vector2 = s * 0.5
	var gap: float = 5.0 + crosshair_spread
	var ln: float = 8.0
	var col: Color = GameState.crosshair_color()  # 颜色可在暂停面板切换（白/绿/红）
	# 中心圆点
	crosshair_node.draw_circle(c, 1.5, col)
	# 四条短线
	crosshair_node.draw_line(c + Vector2(gap, 0), c + Vector2(gap + ln, 0), col, 2.0)
	crosshair_node.draw_line(c - Vector2(gap, 0), c - Vector2(gap + ln, 0), col, 2.0)
	crosshair_node.draw_line(c + Vector2(0, gap), c + Vector2(0, gap + ln), col, 2.0)
	crosshair_node.draw_line(c - Vector2(0, gap), c - Vector2(0, gap + ln), col, 2.0)
	# 命中标记：四段斜线拼成的 X
	if hit_marker_timer > 0.0:
		var hc := Color(1.0, 0.25, 0.2)
		var i1: float = 5.0
		var i2: float = 13.0
		crosshair_node.draw_line(c + Vector2(-i2, -i2), c + Vector2(-i1, -i1), hc, 2.5)
		crosshair_node.draw_line(c + Vector2(i1, -i1), c + Vector2(i2, -i2), hc, 2.5)
		crosshair_node.draw_line(c + Vector2(-i2, i2), c + Vector2(-i1, i1), hc, 2.5)
		crosshair_node.draw_line(c + Vector2(i1, i1), c + Vector2(i2, i2), hc, 2.5)

# ===== 濒死暗角：用多层描边模拟径向渐变 =====
func _draw_vignette() -> void:
	if vignette_overlay == null or vignette_alpha <= 0.001:
		return
	var s: Vector2 = _overlay_size(vignette_overlay)
	var layers: int = 26
	var max_thick: float = min(s.x, s.y) * 0.22
	var band: float = max_thick / float(layers)
	for i in range(layers):
		var t: float = float(i) / float(layers - 1)   # 0 = 最外圈
		var a: float = vignette_alpha * pow(1.0 - t, 2.0)
		if a <= 0.002:
			continue
		var inset: float = max_thick * t
		vignette_overlay.draw_rect(
			Rect2(inset, inset, s.x - inset * 2.0, s.y - inset * 2.0),
			Color(0.6, 0.02, 0.02, a), false, band + 1.0)

# ===== 暂停面板 =====
func _draw_pause() -> void:
	var s: Vector2 = _overlay_size(pause_panel)
	pause_panel.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.02, 0.03, 0.72), true)
	var font := ThemeDB.fallback_font
	var cx: float = s.x * 0.5
	# 从 0.18 起画：内容比原来多出设置区，起点太高会在 720p 下溢出屏幕
	var y: float = s.y * 0.18
	pause_panel.draw_string(font, Vector2(cx - 300, y), "已 暂 停", HORIZONTAL_ALIGNMENT_CENTER, 600, 56, Color(0.95, 0.92, 0.85))
	y += 40
	pause_panel.draw_string(font, Vector2(cx - 320, y), "Esc 继续   ·   R 重开本局   ·   B 跳至 BOSS 波", HORIZONTAL_ALIGNMENT_CENTER, 640, 18, Color(0.62, 0.6, 0.55))
	y += 46
	pause_panel.draw_line(Vector2(cx - 260, y), Vector2(cx + 260, y), Color(0.22, 0.22, 0.24), 1.0)
	y += 34
	# 本局成长
	pause_panel.draw_string(font, Vector2(cx - 260, y), "本局成长", HORIZONTAL_ALIGNMENT_LEFT, 520, 16, Color(0.45, 0.72, 0.45))
	y += 28
	var picked: Array = []
	if player and is_instance_valid(player):
		var p = player.get("up_picked")
		if p is Array:
			picked = p
	if picked.is_empty():
		pause_panel.draw_string(font, Vector2(cx - 260, y), "暂无（清场后可选强化）", HORIZONTAL_ALIGNMENT_LEFT, 520, 15, Color(0.5, 0.48, 0.45))
		y += 24
	else:
		var counts := {}
		for id in picked:
			counts[id] = int(counts.get(id, 0)) + 1
		var keys: Array = counts.keys()
		keys.sort()
		# 卡池扩到 15 张后，同一局可能拿到很多种类：改成两列，避免竖向溢出屏幕
		var rows: int = int(ceil(float(keys.size()) / 2.0))
		for i in range(keys.size()):
			var col: int = 0 if i < rows else 1
			var row: int = i if col == 0 else i - rows
			var id: String = keys[i]
			var info: Dictionary = GameState.UPGRADES.get(id, {})
			var line: String = "%s x%d" % [str(info.get("name", id)), counts[id]]
			pause_panel.draw_string(font, Vector2(cx - 260.0 + float(col) * 266.0, y + float(row) * 21.0),
				line, HORIZONTAL_ALIGNMENT_LEFT, 250, 15, Color(0.8, 0.78, 0.7))
		y += float(rows) * 21.0 + 6.0
	# 当前数值
	y += 14
	if player and is_instance_valid(player) and player.get("up_dmg_mult") != null:
		var stat: String = "伤害 x%.2f   射速 x%.2f   换弹 x%.2f   移速 x%.2f   备弹 x%.2f" % [
			float(player.get("up_dmg_mult")),
			1.0 / max(0.01, float(player.get("up_rate_mult"))),
			1.0 / max(0.01, float(player.get("up_reload_mult"))),
			float(player.get("up_speed_mult")),
			float(player.get("up_reserve_mult"))]
		pause_panel.draw_string(font, Vector2(cx - 320, y), stat, HORIZONTAL_ALIGNMENT_CENTER, 640, 15, Color(0.55, 0.6, 0.55))
		# 第二行：本次扩充出的新维度（弹匣 / 减伤 / 散射）
		var stat2: String = "弹匣 x%.2f   减伤 %d%%   散射 x%.2f" % [
			float(player.get("up_mag_mult")),
			int(round((1.0 - float(player.get("up_damage_taken_mult"))) * 100.0)),
			float(player.get("up_spread_mult"))]
		pause_panel.draw_string(font, Vector2(cx - 320, y + 20), stat2, HORIZONTAL_ALIGNMENT_CENTER, 640, 15, Color(0.55, 0.6, 0.55))
		y += 20
	# ===== 设置项：↑/↓ 选择，←/→ 调整 =====
	y += 42
	pause_panel.draw_line(Vector2(cx - 260, y), Vector2(cx + 260, y), Color(0.22, 0.22, 0.24), 1.0)
	y += 30
	pause_panel.draw_string(font, Vector2(cx - 260, y), "设置 · ↑/↓ 选择，←/→ 调整", HORIZONTAL_ALIGNMENT_LEFT, 520, 16, Color(0.45, 0.72, 0.45))
	y += 30
	for i in range(SETTING_COUNT):
		var sel: bool = i == settings_row
		var label: String = ["全局音量", "鼠标灵敏度", "准星颜色"][i]
		if sel:
			pause_panel.draw_rect(Rect2(cx - 268, y - 18, 536, 28), Color(0.16, 0.2, 0.17), true)
			pause_panel.draw_string(font, Vector2(cx - 260, y), ">", HORIZONTAL_ALIGNMENT_LEFT, 20, 16, Color(0.55, 0.85, 0.55))
		pause_panel.draw_string(font, Vector2(cx - 236, y), label, HORIZONTAL_ALIGNMENT_LEFT, 240, 16,
			Color(0.92, 0.9, 0.84) if sel else Color(0.72, 0.7, 0.65))
		# 准星颜色行额外画一个色块，直观看到当前颜色
		if i == 2:
			pause_panel.draw_rect(Rect2(cx + 104, y - 13, 16, 16), GameState.crosshair_color(), true)
		pause_panel.draw_string(font, Vector2(cx + 128, y), _setting_value_text(i), HORIZONTAL_ALIGNMENT_RIGHT, 130, 16,
			Color(0.55, 0.85, 1.0) if sel else Color(0.66, 0.68, 0.72))

func _setting_value_text(i: int) -> String:
	match i:
		0:
			return "%d%%" % int(round(GameState.master_volume * 100.0))
		1:
			# 0.0025 显示成 2.5，比裸小数好读
			return "%.1f" % (GameState.mouse_sensitivity * 1000.0)
		2:
			return str(GameState.CROSSHAIR_NAMES[clampi(GameState.crosshair_color_idx, 0, 2)])
	return ""

func _adjust_setting(i: int, dir: int) -> void:
	match i:
		0:
			GameState.master_volume = clampf(GameState.master_volume + 0.05 * float(dir), 0.0, 1.0)
			GameState.apply_settings()
		1:
			GameState.mouse_sensitivity = clampf(GameState.mouse_sensitivity + 0.0002 * float(dir), 0.0006, 0.0060)
		2:
			var n: int = GameState.CROSSHAIR_COLORS.size()
			GameState.crosshair_color_idx = (GameState.crosshair_color_idx + dir + n) % n
	GameState.save_game()
	if pause_panel:
		pause_panel.queue_redraw()
	if crosshair_node:
		crosshair_node.queue_redraw()

# ===== 死亡结算面板 =====
func _draw_gameover() -> void:
	if gameover_panel == null:
		return
	var s: Vector2 = _overlay_size(gameover_panel)
	gameover_panel.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.02, 0.03, 0.8), true)
	var font := ThemeDB.fallback_font
	var cx: float = s.x * 0.5
	var card_w := 560.0
	var card_h := 560.0
	var rect := Rect2(cx - card_w * 0.5, s.y * 0.5 - card_h * 0.5, card_w, card_h)
	gameover_panel.draw_rect(rect, Color(0.075, 0.07, 0.08), true)
	gameover_panel.draw_rect(rect, Color(0.45, 0.16, 0.16), false, 2.0)
	var top: float = rect.position.y
	gameover_panel.draw_string(font, Vector2(rect.position.x, top + 58), "你 已 死 亡", HORIZONTAL_ALIGNMENT_CENTER, card_w, 42, Color(0.88, 0.32, 0.28))
	gameover_panel.draw_line(Vector2(rect.position.x + 40, top + 78), Vector2(rect.position.x + card_w - 40, top + 78), Color(0.24, 0.2, 0.2), 1.0)
	var rows: Array = [
		["存活波次", "第 %d 波" % maxi(GameState.wave, 1), GameState.new_record_wave],
		["存活时间", _format_time(GameState.run_time), GameState.new_record_time],
		["总击杀数", "%d" % GameState.kills, GameState.new_record_kills],
		["造成总伤害", "%d" % int(round(GameState.run_damage)), false],
		["获得血晶", "+%d  （持有 %d）" % [GameState.run_crystals, GameState.total_crystals], false],
		["最爱强化", _favorite_upgrade(), false],
	]
	var ry: float = top + 120.0
	for r in rows:
		gameover_panel.draw_string(font, Vector2(rect.position.x + 56, ry), str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, 240, 18, Color(0.62, 0.6, 0.55))
		gameover_panel.draw_string(font, Vector2(rect.position.x + 56, ry), str(r[1]), HORIZONTAL_ALIGNMENT_RIGHT, card_w - 112, 20, Color(0.93, 0.9, 0.82))
		if bool(r[2]):
			gameover_panel.draw_string(font, Vector2(rect.position.x + 152, ry), "[NEW RECORD]", HORIZONTAL_ALIGNMENT_LEFT, 180, 14, Color(1.0, 0.83, 0.25))
		ry += 42.0
	# 历史最佳：一行汇总，避免再加三行把卡片撑爆
	gameover_panel.draw_line(Vector2(rect.position.x + 40, ry - 4), Vector2(rect.position.x + card_w - 40, ry - 4), Color(0.2, 0.19, 0.19), 1.0)
	var best_line: String = "历史最佳：第 %d 波 · %d 击杀 · %s" % [GameState.best_wave, GameState.best_kills, _format_time(GameState.best_time)]
	gameover_panel.draw_string(font, Vector2(rect.position.x + 56, ry + 30), best_line, HORIZONTAL_ALIGNMENT_LEFT, card_w - 112, 16, Color(0.72, 0.66, 0.45))
	var by: float = top + card_h - 66.0
	# 两个「按钮」：只做视觉，实际按键由 player._input 处理
	var bw := 220.0
	var b1 := Rect2(rect.position.x + 34, by, bw, 44)
	var b2 := Rect2(rect.position.x + card_w - 34 - bw, by, bw, 44)
	gameover_panel.draw_rect(b1, Color(0.13, 0.18, 0.13), true)
	gameover_panel.draw_rect(b1, Color(0.34, 0.6, 0.36), false, 2.0)
	gameover_panel.draw_string(font, Vector2(b1.position.x, by + 30), "按 R 重新开始", HORIZONTAL_ALIGNMENT_CENTER, bw, 18, Color(0.88, 0.9, 0.84))
	gameover_panel.draw_rect(b2, Color(0.16, 0.14, 0.14), true)
	gameover_panel.draw_rect(b2, Color(0.55, 0.36, 0.34), false, 2.0)
	gameover_panel.draw_string(font, Vector2(b2.position.x, by + 30), "按 Esc 返回主菜单", HORIZONTAL_ALIGNMENT_CENTER, bw, 18, Color(0.88, 0.88, 0.84))

func _format_time(sec: float) -> String:
	var total: int = int(maxf(sec, 0.0))
	return "%02d:%02d" % [int(total / 60.0), total % 60]

# 本局拿得最多的卡（并列时取先达到的），空手时显示破折号
func _favorite_upgrade() -> String:
	if player == null or not is_instance_valid(player):
		return "—"
	var picked = player.get("up_picked")
	if not (picked is Array) or picked.is_empty():
		return "—"
	var counts: Dictionary = {}
	for id in picked:
		counts[id] = int(counts.get(id, 0)) + 1
	var best_id: String = ""
	var best_n: int = 0
	for id in counts.keys():
		if int(counts[id]) > best_n:
			best_n = int(counts[id])
			best_id = str(id)
	if best_id == "":
		return "—"
	var info: Dictionary = GameState.UPGRADES.get(best_id, {})
	return "%s x%d" % [str(info.get("name", best_id)), best_n]

# ===== 升级面板 =====
func show_upgrades(ids: Array) -> void:
	if upgrade_panel == null:
		return
	upgrade_options = ids
	upgrade_open = true
	GameState.upgrade_open = true
	upgrade_panel.visible = true
	upgrade_panel.queue_redraw()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

func _pick_upgrade(idx: int) -> void:
	if not upgrade_open:
		return
	if idx < 0 or idx >= upgrade_options.size():
		return
	var id: String = upgrade_options[idx]
	if player and is_instance_valid(player) and player.has_method("apply_upgrade"):
		player.apply_upgrade(id)
	upgrade_panel.visible = false
	# 延迟一帧再解暂停：否则本次点击会被玩家节点当成射击
	call_deferred("_finish_upgrade")

func _finish_upgrade() -> void:
	upgrade_open = false
	GameState.upgrade_open = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	show_center("强化已生效 · 走进绿色传送门进入下一张地图", 3.0)

func _picked_count(id: String) -> int:
	if player == null or not is_instance_valid(player):
		return 0
	var picked = player.get("up_picked")
	if picked is Array:
		return picked.count(id)
	return 0

func _draw_upgrades() -> void:
	var s: Vector2 = _overlay_size(upgrade_panel)
	upgrade_panel.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.02, 0.03, 0.9), true)
	var font := ThemeDB.fallback_font
	var cx: float = s.x * 0.5
	upgrade_panel.draw_string(font, Vector2(cx - 320, s.y * 0.2), "波 次 奖 励 · 选 择 一 项 强 化", HORIZONTAL_ALIGNMENT_CENTER, 640, 34, Color(0.95, 0.9, 0.78))
	upgrade_panel.draw_string(font, Vector2(cx - 320, s.y * 0.2 + 30), "按 1 / 2 / 3 或直接点击卡片", HORIZONTAL_ALIGNMENT_CENTER, 640, 16, Color(0.55, 0.53, 0.48))
	_card_rects.clear()
	var card_w := 260.0
	var card_h := 190.0
	var gap := 28.0
	var n: int = upgrade_options.size()
	var total: float = card_w * float(n) + gap * float(max(0, n - 1))
	var x0: float = cx - total * 0.5
	var cy: float = s.y * 0.54
	for i in range(n):
		var id: String = upgrade_options[i]
		var info: Dictionary = GameState.UPGRADES.get(id, {})
		var x: float = x0 + float(i) * (card_w + gap)
		var rect := Rect2(x, cy - card_h * 0.5, card_w, card_h)
		_card_rects.append(rect)
		upgrade_panel.draw_rect(rect, Color(0.08, 0.085, 0.1), true)
		upgrade_panel.draw_rect(rect, Color(0.3, 0.45, 0.3), false, 2.0)
		upgrade_panel.draw_string(font, Vector2(x + 18, rect.position.y + 36), "[%d]" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, 80, 18, Color(0.5, 0.78, 0.5))
		upgrade_panel.draw_string(font, Vector2(x + 18, rect.position.y + 76), str(info.get("name", id)), HORIZONTAL_ALIGNMENT_LEFT, card_w - 36, 26, Color(0.95, 0.92, 0.82))
		# 卡池扩到 15 张后描述变长，按卡片宽度自动折行（最多 2 行），避免文字溢出卡片
		var desc_lines: Array = _wrap_text(font, str(info.get("desc", "")), card_w - 40.0, 16)
		for li in range(mini(2, desc_lines.size())):
			upgrade_panel.draw_string(font, Vector2(x + 18, rect.position.y + 110 + li * 21),
				str(desc_lines[li]), HORIZONTAL_ALIGNMENT_LEFT, card_w - 36, 16, Color(0.7, 0.68, 0.62))
		var cnt := _picked_count(id)
		if cnt > 0:
			upgrade_panel.draw_string(font, Vector2(x + 18, rect.position.y + card_h - 18), "已获得 x%d" % cnt, HORIZONTAL_ALIGNMENT_LEFT, card_w - 36, 14, Color(0.45, 0.6, 0.45))

# 按像素宽度逐字折行：中文没有空格，不能靠 split(" ") 处理
func _wrap_text(font: Font, text: String, width: float, fsize: int) -> Array:
	var out: Array = []
	var cur: String = ""
	for ch in text:
		var test: String = cur + ch
		if cur != "" and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width:
			out.append(cur)
			cur = ch
		else:
			cur = test
	if cur != "":
		out.append(cur)
	return out

# ===== 输入：升级面板 / 暂停面板设置项 =====
func _input(event: InputEvent) -> void:
	# F3：调试覆盖层，任何状态下都能切（含暂停 / 升级面板 / 死亡）
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		if debug_label:
			debug_label.visible = not debug_label.visible
			_debug_timer = 0.0
		return
	if upgrade_open:
		if event is InputEventKey and event.pressed and not event.echo:
			var idx: int = -1
			if event.keycode == KEY_1: idx = 0
			elif event.keycode == KEY_2: idx = 1
			elif event.keycode == KEY_3: idx = 2
			if idx >= 0 and idx < upgrade_options.size():
				_pick_upgrade(idx)
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var mpos: Vector2 = get_viewport().get_mouse_position()
			for i in range(_card_rects.size()):
				if _card_rects[i].has_point(mpos):
					_pick_upgrade(i)
					get_viewport().set_input_as_handled()
					break
		return
	# 暂停时接管方向键调设置（玩家节点的玩法输入此时已被拦掉）
	if not get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_UP or event.keycode == KEY_W:
			settings_row = (settings_row - 1 + SETTING_COUNT) % SETTING_COUNT
			if pause_panel: pause_panel.queue_redraw()
		elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
			settings_row = (settings_row + 1) % SETTING_COUNT
			if pause_panel: pause_panel.queue_redraw()
		elif event.keycode == KEY_LEFT or event.keycode == KEY_A:
			_adjust_setting(settings_row, -1)
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			_adjust_setting(settings_row, 1)

# ===== 每帧刷新 =====
func _process(delta: float) -> void:
	_tick_debug(delta)
	# 如果 player 还没连上，再试一次
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null: return

	# 死亡结算面板（比暂停面板优先）
	var dead: bool = bool(player.get("game_over"))
	if gameover_panel and gameover_panel.visible != dead:
		gameover_panel.visible = dead
		if dead:
			gameover_panel.queue_redraw()
	if dead:
		if crosshair_node:
			crosshair_node.visible = false
		if center_msg:
			center_msg.modulate.a = 0.0
		# 玩家死亡后立刻收起 BOSS 血条与开局提示，避免压在结算面板后面
		clear_bosses()
		if hint_label:
			hint_label.modulate.a = 0.0

	# 暂停面板显隐（升级面板优先，二者不同时出现）
	var want_pause: bool = get_tree().paused and not upgrade_open and not dead
	if pause_panel and pause_panel.visible != want_pause:
		pause_panel.visible = want_pause
		if want_pause:
			pause_panel.queue_redraw()
			# 暂停时收起开局提示，避免文字压在暂停面板的成长清单上
			if hint_label:
				hint_label.modulate.a = 0.0

	# 暂停 / 升级选择期间：玩法数值与所有计时一律不走表
	if get_tree().paused:
		return

	if hp_bar: hp_bar.value = player.hp
	if hp_txt: hp_txt.text = "%d / %d" % [int(player.hp), int(player.max_hp)]
	if ammo_cur: ammo_cur.text = str(player.mag)
	if ammo_res: ammo_res.text = "/ %d" % player.reserve
	if weapon_name:
		if player.has_method("weapon_display_name"):
			weapon_name.text = player.weapon_display_name()
		else:
			weapon_name.text = player.current_weapon
	if grenade_txt: grenade_txt.text = "手雷: %d" % player.grenades
	if skill_cd_txt:
		if player.skill_cd > 0:
			skill_cd_txt.text = "F 技能: %.1fs" % player.skill_cd
		else:
			skill_cd_txt.text = "F 技能: 就绪"
	if wave_txt:
		if GameState.wave > GameState.max_waves:
			wave_txt.text = "无尽 · 第 %d 波" % GameState.wave
		else:
			wave_txt.text = "第 %d/%d 波" % [GameState.wave, GameState.max_waves]
	if map_txt: map_txt.text = GameState.MAP_NAMES[GameState.map_index] if GameState.map_index < GameState.MAP_NAMES.size() else ""
	if kill_txt: kill_txt.text = "击杀 %d" % GameState.kills
	# 命中标记计时 + 准星扩散回收（约 0.1s 收回，对应 140 px/s）
	if hit_marker_timer > 0.0:
		hit_marker_timer -= delta
	crosshair_spread = move_toward(crosshair_spread, 0.0, delta * 140.0)
	if crosshair_node:
		crosshair_node.queue_redraw()
	# 连杀计时清零
	if GameState.combo_timer > 0:
		GameState.combo_timer -= delta
		if GameState.combo_timer <= 0:
			GameState.combo = 0
	# 濒死暗角：血量 <30% 呼吸闪烁；单次掉血 >=20 额外闪一下
	var hp_ratio: float = player.hp / max(player.max_hp, 1.0)
	if _last_hp < 0.0:
		_last_hp = player.hp
	if _last_hp - player.hp >= 20.0:
		damage_flash = 0.7
	_last_hp = player.hp
	if damage_flash > 0.0:
		damage_flash = max(damage_flash - delta * 2.5, 0.0)
	var prev_alpha: float = vignette_alpha
	if hp_ratio < 0.30:
		_low_hp_time += delta
		vignette_alpha = 0.55 * (0.6 + 0.4 * sin(_low_hp_time * 5.0))
	else:
		_low_hp_time = 0.0
		vignette_alpha = move_toward(vignette_alpha, 0.0, delta * 2.0)
	vignette_alpha = max(vignette_alpha, damage_flash)
	# 只在数值变化时重绘，避免每帧 26 层描边的开销
	if vignette_overlay and (not is_equal_approx(prev_alpha, vignette_alpha) or vignette_alpha > 0.001):
		vignette_overlay.queue_redraw()
	# 多 BOSS 血条：逐条判活、更新数值、给可见的重新排位
	_update_boss_bars()

func show_center(text: String, duration: float = 2.0) -> void:
	if not center_msg: return
	center_msg.text = text
	center_msg.modulate.a = 1.0
	var tw: Tween = create_tween()
	tw.tween_interval(duration)
	tw.tween_property(center_msg, "modulate:a", 0.0, 0.5)

func show_hit_marker() -> void:
	hit_marker_timer = 0.15
