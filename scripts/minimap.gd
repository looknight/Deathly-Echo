extends Control
## 小地图：在 Minimap Control 上绘制

var player: Node3D

func set_player(p: Node3D) -> void:
	player = p

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if player == null or not is_instance_valid(player): return
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.6), true)
	draw_rect(r, Color(0.8, 0.8, 0.8, 0.5), false, 2.0)
	var center := size / 2.0
	# 玩家
	draw_circle(center, 5, Color(0.3, 0.9, 0.3))
	var ang: float = player.head.rotation.y + player.rotation.y
	draw_line(center, center + Vector2(sin(ang), cos(ang)) * 12, Color(0.3, 0.9, 0.3), 2)
	# 丧尸
	var half := 40.0
	var sc: float = size.x / (half * 2.0)
	for z in get_tree().get_nodes_in_group("zombie"):
		if not is_instance_valid(z): continue
		var rel: Vector3 = z.global_position - player.global_position
		var p := center + Vector2(rel.x, rel.z) * sc
		if r.has_point(p):
			var c := Color(1, 0.2, 0.2)
			if z.zombie_type == "boss": c = Color(1, 0.5, 0)
			draw_circle(p, 4, c)
