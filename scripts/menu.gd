extends Control
## 角色选择菜单

var selected: int = 0
var chars := [
	{"name":"突击兵","color":Color(0.23,0.42,0.29),"skill":"狂暴射击 · 4秒射速翻倍","weapons":"冲锋枪 / 手枪 / 霰弹枪"},
	{"name":"猎手","color":Color(0.23,0.29,0.54),"skill":"死神标记 · 5秒伤害250%","weapons":"狙击枪 / 手枪 / 冲锋枪"},
	{"name":"重炮","color":Color(0.54,0.35,0.16),"skill":"震撼弹 · 眩晕周围3秒","weapons":"霰弹枪 / 手枪 / 火焰枪"},
]

func _ready() -> void:
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			selected = (selected - 1 + 3) % 3
			queue_redraw()
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			selected = (selected + 1) % 3
			queue_redraw()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_start_game()
	# 鼠标点击选择
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := get_global_mouse_position()
		for i in range(3):
			var cx := size.x/2 + (i-1)*260.0
			if abs(pos.x - cx) < 110 and abs(pos.y - size.y/2) < 180:
				selected = i
				queue_redraw()
		if pos.y > size.y - 80:
			_start_game()

func _start_game() -> void:
	GameState.player_class = ["assault","hunter","heavy"][selected]
	# 切换到主场景
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _draw() -> void:
	# 背景
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04,0.04,0.05))
	# 标题
	draw_string(ThemeDB.fallback_font, Vector2(size.x/2-200, 120), "死 寂 ：幸 存 者", HORIZONTAL_ALIGNMENT_CENTER, 400, 48, Color(0.91,0.89,0.85))
	draw_string(ThemeDB.fallback_font, Vector2(size.x/2-200, 160), "俯视角丧尸射击 · 选择你的角色", HORIZONTAL_ALIGNMENT_CENTER, 400, 18, Color(0.6,0.57,0.52))
	# 三个角色卡片
	for i in range(3):
		var cx := size.x/2 + (i-1)*260.0
		var cy := size.y/2 + 20
		var is_sel := i == selected
		var rect := Rect2(cx-110, cy-160, 220, 320)
		# 卡片背景
		var bg := Color(0.09,0.08,0.10) if not is_sel else Color(0.15,0.10,0.12)
		draw_rect(rect, bg)
		# 边框
		var border: Color = chars[i].color if is_sel else Color(0.23,0.21,0.19)
		draw_rect(rect, border, false, 2.0)
		# 角色名
		draw_string(ThemeDB.fallback_font, Vector2(cx-90, cy-100), chars[i].name, HORIZONTAL_ALIGNMENT_LEFT, 180, 24, Color(0.91,0.89,0.85))
		# 技能
		draw_string(ThemeDB.fallback_font, Vector2(cx-90, cy-50), chars[i].skill, HORIZONTAL_ALIGNMENT_LEFT, 180, 14, Color(0.42,0.63,0.35))
		# 可用武器
		draw_string(ThemeDB.fallback_font, Vector2(cx-90, cy-10), chars[i].weapons, HORIZONTAL_ALIGNMENT_LEFT, 180, 13, Color(0.6,0.57,0.52))
		# 选中提示
		if is_sel:
			draw_string(ThemeDB.fallback_font, Vector2(cx-90, cy+120), "> 已选中 <", HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Color(0.78,0.27,0.35))
	# 底部按钮提示
	draw_string(ThemeDB.fallback_font, Vector2(size.x/2-200, size.y-50), "点击卡片选择 · 按 Enter 开始游戏", HORIZONTAL_ALIGNMENT_CENTER, 400, 16, Color(0.42,0.39,0.34))
