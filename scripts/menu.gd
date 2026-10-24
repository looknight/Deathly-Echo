extends Control
## 主菜单：角色选择 + 血晶商店（局外永久成长）

var selected: int = 0
var mode: int = 0  # 0 = 角色选择，1 = 血晶商店
var chars := [
	{"name":"突击兵","color":Color(0.23,0.42,0.29),"skill":"狂暴射击 · 4秒射速翻倍","weapons":"冲锋枪 / 手枪 / 霰弹枪"},
	{"name":"猎手","color":Color(0.23,0.29,0.54),"skill":"死神标记 · 5秒伤害250%","weapons":"狙击枪 / 手枪 / 冲锋枪"},
	{"name":"重炮","color":Color(0.54,0.35,0.16),"skill":"震撼弹 · 眩晕周围3秒","weapons":"霰弹枪 / 手枪 / 榴弹枪"},
]
var shop_ids: Array[String] = ["dmg", "hp"]

func _ready() -> void:
	# 回菜单时清掉可能残留的暂停/慢放状态（从结算面板 Esc 返回时尤其需要）
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()

# ===== 按钮区域（绘制与点击共用同一套坐标，避免错位）=====
func _btn_primary() -> Rect2:
	var w := 200.0
	return Rect2(size.x * 0.5 - w - 24.0, size.y - 84.0, w, 48.0)

func _btn_secondary() -> Rect2:
	var w := 200.0
	return Rect2(size.x * 0.5 + 24.0, size.y - 84.0, w, 48.0)

func _btn_back() -> Rect2:
	var w := 220.0
	return Rect2(size.x * 0.5 - w * 0.5, size.y - 84.0, w, 48.0)

func _shop_row(i: int) -> Rect2:
	return Rect2(size.x * 0.5 - 280.0, size.y * 0.34 + float(i) * 140.0, 560.0, 120.0)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if mode == 0:
			if event.keycode == KEY_LEFT or event.keycode == KEY_A:
				selected = (selected - 1 + 3) % 3
				queue_redraw()
			elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
				selected = (selected + 1) % 3
				queue_redraw()
			elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				_start_game()
			elif event.keycode == KEY_U:
				mode = 1
				queue_redraw()
		else:
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_U:
				mode = 0
				queue_redraw()
			elif event.keycode == KEY_1:
				_buy(0)
			elif event.keycode == KEY_2:
				_buy(1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = get_global_mouse_position()
		if mode == 0:
			for i in range(3):
				var cx: float = size.x * 0.5 + float(i - 1) * 260.0
				if abs(pos.x - cx) < 110 and abs(pos.y - (size.y * 0.5 + 20.0)) < 180:
					selected = i
					queue_redraw()
			if _btn_primary().has_point(pos):
				_start_game()
			elif _btn_secondary().has_point(pos):
				mode = 1
				queue_redraw()
		else:
			for i in range(shop_ids.size()):
				if _shop_row(i).has_point(pos):
					_buy(i)
			if _btn_back().has_point(pos):
				mode = 0
				queue_redraw()

func _buy(i: int) -> void:
	if i < 0 or i >= shop_ids.size(): return
	if GameState.buy_meta(shop_ids[i]):
		queue_redraw()

func _start_game() -> void:
	GameState.player_class = ["assault", "hunter", "heavy"][selected]
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.05))
	var font := ThemeDB.fallback_font
	if mode == 0:
		_draw_select(font)
	else:
		_draw_shop(font)

func _draw_select(font: Font) -> void:
	draw_string(font, Vector2(size.x * 0.5 - 200, 120), "死 寂 ：幸 存 者", HORIZONTAL_ALIGNMENT_CENTER, 400, 48, Color(0.91, 0.89, 0.85))
	draw_string(font, Vector2(size.x * 0.5 - 200, 160), "第一人称丧尸射击 · 选择你的角色", HORIZONTAL_ALIGNMENT_CENTER, 400, 18, Color(0.6, 0.57, 0.52))
	for i in range(3):
		var cx: float = size.x * 0.5 + float(i - 1) * 260.0
		var cy: float = size.y * 0.5 + 20.0
		var is_sel: bool = i == selected
		var rect := Rect2(cx - 110, cy - 160, 220, 320)
		draw_rect(rect, Color(0.09, 0.08, 0.10) if not is_sel else Color(0.15, 0.10, 0.12))
		var border: Color = chars[i].color if is_sel else Color(0.23, 0.21, 0.19)
		draw_rect(rect, border, false, 2.0)
		draw_string(font, Vector2(cx - 90, cy - 100), chars[i].name, HORIZONTAL_ALIGNMENT_LEFT, 180, 24, Color(0.91, 0.89, 0.85))
		draw_string(font, Vector2(cx - 90, cy - 50), chars[i].skill, HORIZONTAL_ALIGNMENT_LEFT, 180, 14, Color(0.42, 0.63, 0.35))
		draw_string(font, Vector2(cx - 90, cy - 10), chars[i].weapons, HORIZONTAL_ALIGNMENT_LEFT, 180, 13, Color(0.6, 0.57, 0.52))
		if is_sel:
			draw_string(font, Vector2(cx - 90, cy + 120), "> 已选中 <", HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Color(0.78, 0.27, 0.35))
	_draw_button(_btn_primary(), "开始游戏", Color(0.30, 0.55, 0.32))
	_draw_button(_btn_secondary(), "血晶升级 (%d)" % GameState.total_crystals, Color(0.55, 0.42, 0.20))
	draw_string(font, Vector2(size.x * 0.5 - 300, size.y - 22), "点击卡片或 A/D 选择 · Enter 开始 · U 打开升级", HORIZONTAL_ALIGNMENT_CENTER, 600, 15, Color(0.42, 0.39, 0.34))

func _draw_shop(font: Font) -> void:
	draw_string(font, Vector2(size.x * 0.5 - 240, 110), "血 晶 强 化", HORIZONTAL_ALIGNMENT_CENTER, 480, 44, Color(0.91, 0.89, 0.85))
	draw_string(font, Vector2(size.x * 0.5 - 300, 150), "永久生效 · 每局开局自动套用", HORIZONTAL_ALIGNMENT_CENTER, 600, 17, Color(0.6, 0.57, 0.52))
	draw_string(font, Vector2(size.x * 0.5 - 300, 196), "持有血晶：%d" % GameState.total_crystals, HORIZONTAL_ALIGNMENT_CENTER, 600, 24, Color(0.55, 0.85, 1.0))
	for i in range(shop_ids.size()):
		var id: String = shop_ids[i]
		var info: Dictionary = GameState.META_UPGRADES[id]
		var rect := _shop_row(i)
		var lv: int = GameState.meta_level(id)
		var maxed: bool = lv >= GameState.MAX_META_LV
		var cost: int = GameState.meta_cost(id)
		var affordable: bool = not maxed and GameState.total_crystals >= cost
		draw_rect(rect, Color(0.08, 0.085, 0.10))
		draw_rect(rect, Color(0.32, 0.45, 0.34) if affordable else Color(0.22, 0.22, 0.24), false, 2.0)
		draw_string(font, Vector2(rect.position.x + 20, rect.position.y + 40), "[%d] %s" % [i + 1, str(info.get("name", id))], HORIZONTAL_ALIGNMENT_LEFT, 320, 24, Color(0.93, 0.9, 0.82))
		draw_string(font, Vector2(rect.position.x + 20, rect.position.y + 72), str(info.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, 320, 16, Color(0.67, 0.65, 0.6))
		# 等级方块
		for k in range(GameState.MAX_META_LV):
			var px: float = rect.position.x + 20 + float(k) * 26.0
			var py: float = rect.position.y + 90
			draw_rect(Rect2(px, py, 20, 10), Color(0.55, 0.85, 1.0) if k < lv else Color(0.2, 0.2, 0.22))
		var price_txt: String = "已满级" if maxed else "%d 血晶" % cost
		var price_col: Color = Color(0.5, 0.5, 0.5) if maxed else (Color(0.55, 0.85, 1.0) if affordable else Color(0.7, 0.35, 0.3))
		draw_string(font, Vector2(rect.position.x + 360, rect.position.y + 62), price_txt, HORIZONTAL_ALIGNMENT_RIGHT, 180, 22, price_col)
		draw_string(font, Vector2(rect.position.x + 360, rect.position.y + 88), "Lv %d/%d" % [lv, GameState.MAX_META_LV], HORIZONTAL_ALIGNMENT_RIGHT, 180, 15, Color(0.55, 0.55, 0.55))
	# 当前永久加成预览
	var bonus: String = "当前加成：伤害 x%.2f   初始生命 %d" % [GameState.meta_dmg_mult(), int(100.0 + GameState.meta_hp_bonus())]
	draw_string(font, Vector2(size.x * 0.5 - 300, size.y - 130), bonus, HORIZONTAL_ALIGNMENT_CENTER, 600, 16, Color(0.55, 0.6, 0.55))
	_draw_button(_btn_back(), "返回", Color(0.35, 0.35, 0.38))
	draw_string(font, Vector2(size.x * 0.5 - 300, size.y - 22), "点击强化项或按 1 / 2 购买 · Esc 返回", HORIZONTAL_ALIGNMENT_CENTER, 600, 15, Color(0.42, 0.39, 0.34))

func _draw_button(rect: Rect2, text: String, accent: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(rect, Color(0.10, 0.10, 0.12))
	draw_rect(rect, accent, false, 2.0)
	draw_string(font, Vector2(rect.position.x, rect.position.y + 32), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 20, Color(0.93, 0.9, 0.84))
