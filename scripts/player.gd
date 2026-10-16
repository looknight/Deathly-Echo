extends CharacterBody3D
## FPS 玩家：多武器、手雷、道具、角色系统

const WEAPONS := {
	"pistol":   {"name":"手枪","dmg":60,"mag":12,"res":48,"rate":0.32,"spread":0.02,"pellets":1,"auto":false},
	"smg":      {"name":"冲锋枪","dmg":25,"mag":32,"res":120,"rate":0.10,"spread":0.07,"pellets":1,"auto":true},
	"shotgun":  {"name":"霰弹枪","dmg":15,"mag":6,"res":36,"rate":0.75,"spread":0.18,"pellets":6,"auto":false},
	"sniper":   {"name":"狙击枪","dmg":200,"mag":5,"res":25,"rate":1.2,"spread":0.001,"pellets":1,"auto":false},
	"flame":    {"name":"火焰枪","dmg":8,"mag":40,"res":160,"rate":0.05,"spread":0.25,"pellets":3,"auto":true},
}
# 每个角色可用武器
var CLASS_WEAPONS := {
	"assault": ["pistol","smg","shotgun"],
	"hunter": ["pistol","sniper","smg"],
	"heavy": ["pistol","shotgun","flame"],
}
var weapon_order: Array[String] = ["pistol","smg","shotgun","sniper","flame"]
var weapon_idx: int = 0
var current_weapons = ["pistol"]

@export var speed: float = 6.0
@export var sprint_mult: float = 1.8
@export var jump_force: float = 5.0
@export var mouse_sens: float = 0.0025
var ctrl_released: bool = false
var ctrl_was_pressed: bool = false
var mouse_locked: bool = true  # 鼠标是否锁定

var gravity: float = 18.0
var slow_timer: float = 0.0
var is_shooting: bool = false
var shoot_player: AudioStreamPlayer
var hit_player: AudioStreamPlayer
var hp: float = 100.0
var max_hp: float = 100.0
var current_weapon: String = "pistol"
var mag: int = 12
var reserve: int = 48
var grenades: int = 3
var can_shoot: bool = true
var reloading: bool = false
var game_over: bool = false
var speed_boost: float = 0.0
var invuln: float = 0.0

@onready var head: Node3D = $Head
@onready var cam: Camera3D = $Head/Camera3D
@onready var gun: MeshInstance3D = $Head/Camera3D/Gun
@onready var ray: RayCast3D = $Head/Camera3D/CameraRay
@onready var muzzle: Marker3D = $Head/Camera3D/Gun/Muzzle

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_locked = true
	# 根据角色设置初始武器
	var start_weapon: String = "pistol"
	current_weapons = CLASS_WEAPONS.get(GameState.player_class, ["pistol"])
	match GameState.player_class:
		"assault": start_weapon = "smg"
		"hunter": start_weapon = "sniper"
		"heavy": start_weapon = "shotgun"
	_build_gun()
	EquipWeapon(start_weapon)
	cam.current = true
	# 初始化音效
	shoot_player = AudioStreamPlayer.new()
	shoot_player.volume_db = -8
	add_child(shoot_player)
	hit_player = AudioStreamPlayer.new()
	hit_player.volume_db = -10
	add_child(hit_player)
	shoot_player.stream = _make_gun_sound()
	hit_player.stream = _make_hit_sound()
	print("[音效] 初始化 shoot.stream=%s hit.stream=%s bus=%s" % [shoot_player.stream != null, hit_player.stream != null, shoot_player.bus])

func _make_gun_sound() -> AudioStreamWAV:
	# 程序化枪声：短促噪声
	var rate := 22050
	var frames := rate / 8  # 0.125秒
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / frames
		var noise := (randf() * 2.0 - 1.0) * (1.0 - t)
		var val := int(noise * 12000)
		data[i*2] = val & 0xFF
		data[i*2+1] = (val >> 8) & 0xFF
	wav.data = data
	return wav

func _make_hit_sound() -> AudioStreamWAV:
	# 击中声：低频咚
	var rate := 22050
	var frames := rate / 15
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / frames
		var s := sin(t * 20) * (1.0 - t) * 0.5
		var val := int(s * 10000)
		data[i*2] = val & 0xFF
		data[i*2+1] = (val >> 8) & 0xFF
	wav.data = data
	return wav

func add_slow(t: float) -> void:
	slow_timer = max(slow_timer, t)
	hud_center_msg("被咆哮减速！", 2.0)

func hud_center_msg(text: String, dur: float) -> void:
	var h := get_tree().get_first_node_in_group("hud")
	if h and h.has_method("show_center"):
		h.show_center(text, dur)

func _input(event: InputEvent) -> void:
	if game_over:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			get_tree().reload_current_scene()
		return
	# Esc释放鼠标
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_locked = false
		return
	# 鼠标视角
	if event is InputEventMouseMotion:
		if mouse_locked:
			rotate_y(-event.relative.x * mouse_sens)
			head.rotate_x(-event.relative.y * mouse_sens)
			head.rotation.x = clamp(head.rotation.x, -1.4, 1.4)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not mouse_locked:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				mouse_locked = true
			is_shooting = true
			_try_shoot()
		else:
			is_shooting = false
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R: _reload()
		if event.keycode == KEY_G: _throw_grenade()
		if event.keycode == KEY_F: _use_skill()
		# 1/2/3切换武器
		if event.keycode >= KEY_1 and event.keycode <= KEY_3:
			var idx: int = event.keycode - KEY_1
			if idx < current_weapons.size():
				EquipWeapon(current_weapons[idx])

func _gun_part(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	mat.metallic = 0.6
	m.material_override = mat
	return m

func _build_gun() -> void:
	# 清空旧模型（立即删除）
	for c in gun.get_children():
		gun.remove_child(c)
		c.queue_free()
	var dark := Color(0.08,0.08,0.08)
	var mid := Color(0.15,0.15,0.15)
	var steel := Color(0.3,0.3,0.32)
	var wood := Color(0.25,0.15,0.08)

	match current_weapon:
		"pistol":
			# 手枪：短套筒+握把
			var slide := _gun_part(Vector3(0.045,0.05,0.18), steel)
			slide.position = Vector3(0,0.03,-0.05)
			gun.add_child(slide)
			var frame := _gun_part(Vector3(0.04,0.04,0.12), dark)
			frame.position = Vector3(0,-0.01,-0.02)
			gun.add_child(frame)
			var grip := _gun_part(Vector3(0.04,0.11,0.06), wood)
			grip.position = Vector3(0,-0.08,0.03)
			grip.rotation.x = 0.2
			gun.add_child(grip)
		"smg":
			# 冲锋枪：短紧凑+长弹匣
			var body := _gun_part(Vector3(0.05,0.06,0.28), dark)
			body.position = Vector3(0,0.02,-0.05)
			gun.add_child(body)
			var barrel := _gun_part(Vector3(0.02,0.02,0.12), steel)
			barrel.position = Vector3(0,0.02,-0.28)
			gun.add_child(barrel)
			var magz := _gun_part(Vector3(0.035,0.18,0.05), mid)
			magz.position = Vector3(0,-0.12,-0.05)
			magz.rotation.x = -0.1
			gun.add_child(magz)
			var grip := _gun_part(Vector3(0.04,0.1,0.05), wood)
			grip.position = Vector3(0,-0.09,0.08)
			grip.rotation.x = 0.25
			gun.add_child(grip)
		"shotgun":
			# 霰弹枪：长枪管+木枪托+泵动护木
			var barrel := _gun_part(Vector3(0.03,0.035,0.5), steel)
			barrel.position = Vector3(0,0.03,-0.15)
			gun.add_child(barrel)
			var pump := _gun_part(Vector3(0.035,0.04,0.18), wood)
			pump.position = Vector3(0,-0.01,-0.35)
			gun.add_child(pump)
			var receiver := _gun_part(Vector3(0.04,0.05,0.15), dark)
			receiver.position = Vector3(0,0.01,0.05)
			gun.add_child(receiver)
			var stock := _gun_part(Vector3(0.04,0.09,0.2), wood)
			stock.position = Vector3(0,-0.02,0.22)
			gun.add_child(stock)
		"sniper":
			# 狙击枪：长枪管+瞄准镜+两脚架
			var barrel := _gun_part(Vector3(0.02,0.025,0.6), steel)
			barrel.position = Vector3(0,0.02,-0.2)
			gun.add_child(barrel)
			var scope := _gun_part(Vector3(0.03,0.03,0.16), dark)
			scope.position = Vector3(0,0.08,-0.05)
			gun.add_child(scope)
			var body := _gun_part(Vector3(0.045,0.06,0.2), mid)
			body.position = Vector3(0,0,0.0)
			gun.add_child(body)
			var stock := _gun_part(Vector3(0.04,0.1,0.22), wood)
			stock.position = Vector3(0,-0.02,0.2)
			gun.add_child(stock)
			var bipod := _gun_part(Vector3(0.08,0.02,0.05), dark)
			bipod.position = Vector3(0,-0.05,-0.45)
			gun.add_child(bipod)
		"flame":
			# 火焰枪：气罐+喷口
			var tank := _gun_part(Vector3(0.08,0.12,0.15), Color(0.7,0.3,0.1))
			tank.position = Vector3(0,-0.05,0.05)
			gun.add_child(tank)
			var nozzle := _gun_part(Vector3(0.03,0.03,0.25), steel)
			nozzle.position = Vector3(0,0.03,-0.2)
			gun.add_child(nozzle)
			var pilot := _gun_part(Vector3(0.04,0.04,0.08), dark)
			pilot.position = Vector3(0,0,0.08)
			gun.add_child(pilot)

func _physics_process(delta: float) -> void:
	if game_over: return
	# 点屏幕重新捕获鼠标
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if not is_on_floor(): velocity.y -= gravity * delta

	var input_dir: Vector2 = Input.get_vector("move_left","move_right","move_forward","move_back")
	var dir: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var boost: float = 1.0
	if speed_boost > 0:
		boost = 1.5
	var spd: float = speed * boost * (sprint_mult if Input.is_action_pressed("sprint") else 1.0)
	if slow_timer > 0:
		spd *= 0.4
		slow_timer -= delta

	if dir.length() > 0:
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
	else:
		velocity.x = move_toward(velocity.x, 0, spd)
		velocity.z = move_toward(velocity.z, 0, spd)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force

	move_and_slide()

	# 自动武器按住连发
	if is_shooting and WEAPONS[current_weapon].auto and can_shoot and not reloading:
		_try_shoot()

	if invuln > 0:
		invuln -= delta
	if skill_cd > 0:
		skill_cd -= delta
	if skill_active > 0:
		skill_active -= delta
		if skill_active <= 0:
			skill_active = 0
			marked_zombie = null  # 技能结束清除标记

func EquipWeapon(w: String) -> void:
	current_weapon = w
	weapon_idx = current_weapons.find(w)
	var cfg: Dictionary = WEAPONS[w]
	mag = cfg.mag
	reserve = cfg.res
	reloading = false
	can_shoot = true
	_build_gun()

func _try_shoot() -> void:
	if not can_shoot or reloading: return
	# 兜底：标记对象已失效则清除（防悬空引用）
	if marked_zombie and not is_instance_valid(marked_zombie):
		marked_zombie = null
	var cfg: Dictionary = WEAPONS[current_weapon]
	if mag <= 0:
		_reload()
		return
	mag -= 1
	can_shoot = false
	# 播放枪声
	if shoot_player:
		print("DEBUG: 枪声播放, stream=", shoot_player.stream)
		shoot_player.play()
	var rate: float = cfg.rate
	if GameState.player_class == "assault" and skill_active > 0:
		rate *= 0.5  # 射速翻倍
	$ShootTimer.wait_time = rate
	$ShootTimer.start()
	# 后坐力：枪身后移 + 相机 pitch 上抬 1.5°，0.08s 回落
	gun.position.z = -0.55
	head.rotation.x += deg_to_rad(1.5)
	var tw := create_tween()
	tw.tween_property(gun, "position:z", -0.5, 0.08)
	tw.tween_property(head, "rotation:x", head.rotation.x - deg_to_rad(1.5), 0.08)

	# 火焰枪视觉：枪口喷火
	if current_weapon == "flame":
		_spawn_flame()

	# 多发子弹（霰弹枪）带散射
	var pellets: int = cfg.pellets
	var spread: float = cfg.spread
	var cam_from: Vector3 = cam.global_position
	var cam_dir: Vector3 = -cam.global_transform.basis.z
	for p in range(pellets):
		var spread_offset := Vector3(
			randf_range(-spread, spread),
			randf_range(-spread, spread),
			0)
		var dir: Vector3 = (cam_dir + spread_offset).normalized()
		var to: Vector3 = cam_from + dir * 50.0
		# raycast检测真实命中点
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(cam_from, to)
		query.exclude = [self]
		query.collide_with_areas = false
		var result: Dictionary = space.intersect_ray(query)
		var hit_pos: Vector3 = to
		var hit_z: Node3D = null
		if not result.is_empty():
			hit_pos = result.position
			var col: Object = result.collider
			if col and col.is_in_group("zombie"):
				hit_z = col
		# 对命中的丧尸造成伤害
		if hit_z:
			var dmg: float = cfg.dmg
			if GameState.player_class == "hunter" and marked_zombie == hit_z:
				dmg *= 2.5
			hit_z.take_damage(dmg, current_weapon)
			_spawn_blood(hit_pos)  # 命中血珠爆发
			# 触发命中标记
			var hud := get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("show_hit_marker"):
				hud.show_hit_marker()
		else:
			_spawn_hole(hit_pos, false)
		if hit_player:
			print("DEBUG: 命中音效播放, stream=", hit_player.stream)
			hit_player.play()

func _through_shot(from_pos: Vector3, dir: Vector3, exclude: Object) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var to: Vector3 = from_pos + dir.normalized() * 50
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_pos, to)
	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty() and result.collider != exclude and result.collider.has_method("take_damage"):
		result.collider.take_damage(120, "sniper")

func _muzzle_flash() -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1, 0.8, 0.3)
	flash.light_energy = 5.0
	flash.omni_range = 5.0
	flash.global_position = muzzle.global_position
	get_parent().add_child(flash)
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(flash.queue_free)

func _spawn_hole(pos: Vector3, is_blood: bool) -> void:
	# 弹孔/血花：2秒后消失
	var hole := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	hole.mesh = sphere
	hole.global_position = pos
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if is_blood:
		mat.albedo_color = Color(0.7, 0.05, 0.05)
		mat.emission_enabled = true
		mat.emission = Color(0.7, 0.05, 0.05)
		mat.emission_energy_multiplier = 1.0
	else:
		mat.albedo_color = Color(0.1, 0.1, 0.1)
		mat.emission_enabled = false
	hole.material_override = mat
	get_tree().current_scene.add_child(hole)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(hole.queue_free)

func _reload() -> void:
	if reloading: return
	if mag >= WEAPONS[current_weapon].mag: return
	if reserve <= 0: return
	reloading = true
	$ReloadTimer.wait_time = 0.6
	$ReloadTimer.start()

func _throw_grenade() -> void:
	if grenades <= 0: return
	grenades -= 1
	var grenade: RigidBody3D = preload("res://scenes/grenade.tscn").instantiate()
	grenade.global_position = cam.global_position + cam.global_transform.basis.z * 0.5
	var dir: Vector3 = -cam.global_transform.basis.z
	dir.y += 0.3
	grenade.linear_velocity = dir.normalized() * 12.0
	get_tree().current_scene.add_child(grenade)

func _spawn_blood(pos: Vector3) -> void:
	for i in range(5):
		var p: MeshInstance3D = MeshInstance3D.new()
		var s: SphereMesh = SphereMesh.new()
		s.radius = 0.04
		s.height = 0.08
		p.mesh = s
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.05, 0.05)
		p.material_override = mat
		p.position = pos
		get_tree().current_scene.add_child(p)
		var tw: Tween = create_tween()
		tw.tween_property(p, "scale", Vector3(0.01,0.01,0.01), 0.4)
		tw.tween_callback(p.queue_free)

func _spawn_flame() -> void:
	# 枪口火光：橙色发光球，向前快速飞散后消失
	var origin: Vector3 = muzzle.global_position
	for i in range(3):
		var f: MeshInstance3D = MeshInstance3D.new()
		var s: SphereMesh = SphereMesh.new()
		s.radius = 0.12 + randf()*0.1
		s.height = s.radius * 2.0
		f.mesh = s
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5 + randf()*0.3, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.05)
		mat.emission_energy_multiplier = 2.0
		f.material_override = mat
		f.position = origin
		get_tree().current_scene.add_child(f)
		# 向前飞一点
		var dir: Vector3 = -cam.global_transform.basis.z
		dir += Vector3(randf()-0.5, randf()-0.3, randf()-0.5) * 0.3
		var tw: Tween = create_tween()
		tw.tween_property(f, "position", origin + dir.normalized() * (0.5 + randf()*0.5), 0.15)
		tw.parallel().tween_property(f, "scale", Vector3(0.1,0.1,0.1), 0.15)
		tw.tween_callback(f.queue_free)

func add_ammo(amount: int) -> void:
	reserve += amount

func add_hp(amount: float) -> void:
	hp = min(max_hp, hp + amount)

func add_speed_boost(duration: float) -> void:
	speed_boost = duration

func add_grenade(n: int) -> void:
	grenades += n

func take_damage(amount: float) -> void:
	if invuln > 0: return
	hp -= amount
	invuln = 0.5
	if hp <= 0:
		hp = 0
		game_over = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_shoot_timer_timeout() -> void:
	can_shoot = true

func _on_reload_timer_timeout() -> void:
	var need: int = WEAPONS[current_weapon].mag - mag
	var take: int = min(need, reserve)
	mag += take
	reserve -= take
	reloading = false

func _exit_tree() -> void:
	# 退出时恢复鼠标，避免残留
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ===== 技能系统 =====
var skill_cd: float = 0.0
var skill_active: float = 0.0
var marked_zombie: Node3D = null

func _use_skill() -> void:
	if skill_cd > 0: return
	var cls := GameState.player_class
	if cls == "assault":
		# 狂暴射击：4秒射速翻倍
		skill_active = 4.0
		skill_cd = 18.0
		hud_show("狂暴射击！射速翻倍")
	elif cls == "hunter":
		# 死神标记：标记最近丧尸，5秒伤害250%
		skill_active = 5.0
		skill_cd = 20.0
		marked_zombie = _find_nearest_zombie()
		if marked_zombie:
			hud_show("死神标记！伤害250%")
		else:
			hud_show("死神标记（无目标）")
	elif cls == "heavy":
		# 震撼弹：眩晕周围丧尸3秒
		skill_active = 3.0
		skill_cd = 16.0
		_stun_nearby_zombies(8.0)
		hud_show("震撼弹！")

func _find_nearest_zombie() -> Node3D:
	var best: Node3D = null
	var bd: float = 1e9
	for z in get_tree().get_nodes_in_group("zombie"):
		if not is_instance_valid(z): continue
		var d: float = global_position.distance_to(z.global_position)
		if d < bd:
			bd = d
			best = z
	return best

func _stun_nearby_zombies(radius: float) -> void:
	for z in get_tree().get_nodes_in_group("zombie"):
		if not is_instance_valid(z): continue
		if global_position.distance_to(z.global_position) < radius:
			z.set("stun_timer", 3.0)

func hud_show(text: String) -> void:
	# 通过 HUD 显示提示
	var hud_node := get_tree().current_scene.get_node_or_null("HUD")
	if hud_node and hud_node.has_method("show_center"):
		hud_node.show_center(text, 2.0)
