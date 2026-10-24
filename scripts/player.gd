extends CharacterBody3D
## FPS 玩家：多武器、手雷、道具、角色系统

const WEAPONS := {
	"pistol":   {"name":"手枪","dmg":60,"mag":12,"res":48,"rate":0.32,"spread":0.02,"pellets":1,"auto":false},
	"smg":      {"name":"冲锋枪","dmg":25,"mag":32,"res":120,"rate":0.10,"spread":0.07,"pellets":1,"auto":true},
	"shotgun":  {"name":"霰弹枪","dmg":15,"mag":6,"res":36,"rate":0.75,"spread":0.18,"pellets":6,"auto":false},
	"sniper":   {"name":"狙击枪","dmg":200,"mag":5,"res":25,"rate":1.2,"spread":0.001,"pellets":1,"auto":false},
	"launcher": {"name":"榴弹枪","dmg":150,"mag":3,"res":12,"rate":0.8,"spread":0.01,"pellets":1,"auto":false},
}
# 每个角色可用武器
var CLASS_WEAPONS := {
	"assault": ["pistol","smg","shotgun"],
	"hunter": ["pistol","sniper","smg"],
	"heavy": ["pistol","shotgun","launcher"],
}
var weapon_order: Array[String] = ["pistol","smg","shotgun","sniper","launcher"]
var weapon_idx: int = 0
var current_weapons = ["pistol"]

@export var speed: float = 6.0
@export var sprint_mult: float = 1.8
@export var jump_force: float = 5.0
# 鼠标灵敏度已改为可调设置（GameState.mouse_sensitivity，暂停面板内 ←/→ 调整）
var ctrl_released: bool = false
var ctrl_was_pressed: bool = false
var mouse_locked: bool = true  # 鼠标是否锁定

# 后坐力状态：recoil_offset 为枪身后坐量，recoil_target 为瞬时机枪后坐目标
# 注意：recoil_offset 是「相对枪身静止位」的偏移，正值 = 向玩家方向后退
var recoil_offset: float = 0.0
var recoil_target: float = 0.0
var gun_rest_z: float = -0.5  # 枪身静止时的相机局部 Z（_ready 中按场景实际值覆盖）
# 后坐力恢复速度：位移与视角分开标定，让两者回弹时间都在 0.08~0.1s 左右
const RECOIL_GUN_RECOVER: float = 1.5   # 米/秒：0.12m 约 0.08s 回位
const RECOIL_HEAD_RECOVER: float = 0.3  # 弧度/秒：1.5°(0.026rad) 约 0.09s 回位

# ===== 屏幕震动 =====
var _shake_time: float = 0.0
var _shake_dur: float = 0.0
var _shake_amp: float = 0.0
var _cam_rest_pos: Vector3 = Vector3.ZERO
var _cam_rest_rot: Vector3 = Vector3.ZERO

# ===== 枪械动画 =====
var gun_rest_y: float = -0.2
var _reload_tween: Tween = null
var _swap_tween: Tween = null

# ===== 开镜（狙击枪）=====
var scoped: bool = false
var sens_mult: float = 1.0
const HIP_FOV: float = 75.0
const SCOPE_FOV: float = 22.0
const SCOPE_SENS_MULT: float = 0.35

# ===== 局内成长（波间三选一）=====
var up_dmg_mult: float = 1.0      # 伤害倍率
var up_rate_mult: float = 1.0     # 射击间隔倍率（<1 更快）
var up_reload_mult: float = 1.0   # 换弹时间倍率（<1 更快）
var up_speed_mult: float = 1.0    # 移速倍率
var up_reserve_mult: float = 1.0  # 备弹倍率
var up_picked: Array[String] = [] # 已选升级 id（暂停面板展示用）
# ===== 扩充卡池带来的新维度 =====
var up_mag_mult: float = 1.0        # 弹匣容量倍率（弹匣扩容卡）
var up_launcher_bonus: int = 0      # 榴弹枪弹匣额外发数（榴弹扩容卡）
var up_spread_mult: float = 1.0     # 散射倍率（<1 更准，稳定枪管卡）
var up_damage_taken_mult: float = 1.0  # 受到伤害倍率（<1 减伤，复合护甲卡）
var up_vamp: float = 0.0            # 每次击杀回血（战地急救卡）
var up_killboom: float = 0.0        # 击杀爆炸伤害（0 = 未解锁）
var up_crystal_mult: float = 1.0    # 血晶掉落倍率（供 zombie.gd 读取）
const KILL_BOOM_RADIUS: float = 3.0
# 视角（俯仰）拆分：head_base_pitch 为鼠标控制的瞄准角，head_recoil_offset 为瞬时后坐偏移
# 二者分离，避免后坐回落与鼠标输入相互覆盖
var head_base_pitch: float = 0.0
var head_recoil_offset: float = 0.0

var gravity: float = 18.0
var slow_timer: float = 0.0
var _step_timer: float = 0.0   # 脚步声节拍
var is_shooting: bool = false
var gun_sound: AudioStreamWAV   # 程序化合成一次，播放交给 AudioManager 的播放池
var hit_sound: AudioStreamWAV
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

# 缓存的 HUD 节点。用惰性取用而不是只在 _ready 赋一次：
# main.tscn 里 Player 排在 HUD 之前，Player._ready 执行时 HUD 还没进 "hud" 组，
# 一次性缓存会永久拿到 null（命中标记 / 开镜遮罩 / 准星扩散 / 血晶飘字会全部静默失效）。
var hud_node: Node = null

func _hud() -> Node:
	if hud_node == null or not is_instance_valid(hud_node):
		hud_node = get_tree().get_first_node_in_group("hud")
	return hud_node

func _ready() -> void:
	# 暂停时仍需处理 Esc（恢复）与 B（跳 BOSS），因此节点设为 ALWAYS；
	# 玩法逻辑在 _physics_process / _input 里显式拦掉（见下方 paused 判断）
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_locked = true
	# 局外永久强化：初始生命上限（伤害加成在 _try_shoot 里乘）
	max_hp = 100.0 + GameState.meta_hp_bonus()
	hp = max_hp
	# 根据角色设置初始武器
	var start_weapon: String = "pistol"
	current_weapons = CLASS_WEAPONS.get(GameState.player_class, ["pistol"])
	match GameState.player_class:
		"assault": start_weapon = "smg"
		"hunter": start_weapon = "sniper"
		"heavy": start_weapon = "shotgun"
	# 记录枪械静止位与相机基准（后坐力 / 切枪动画 / 屏幕震动都依赖）
	# 必须在 _build_gun / EquipWeapon 之前取，否则会被切枪动画改写
	gun_rest_z = gun.position.z
	gun_rest_y = gun.position.y
	_cam_rest_pos = cam.position
	_cam_rest_rot = cam.rotation
	_build_gun()
	EquipWeapon(start_weapon)
	cam.current = true
	# 用场景初始头部角度初始化瞄准基准，防止与后坐偏移叠加时跳变
	head_base_pitch = head.rotation.x
	# 预热 HUD 引用（此刻 HUD 可能还没进组，_hud() 会在首次使用时自动重试）
	_hud()
	# 初始化音效：只做一次程序化合成，播放统一走 AudioManager 的 10 播放器池
	gun_sound = _make_gun_sound()
	hit_sound = _make_hit_sound()

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
	var h := _hud()
	if h and h.has_method("show_center"):
		h.show_center(text, dur)

func _input(event: InputEvent) -> void:
	if game_over:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_R:
				get_tree().paused = false  # 暂停界面按 R 也要能正常重开
				get_tree().reload_current_scene()
			elif event.keycode == KEY_ESCAPE:
				# 回主菜单：先解除暂停与鼠标锁定，否则菜单里点不动
				get_tree().paused = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				Engine.time_scale = 1.0
				get_tree().change_scene_to_file("res://scenes/menu.tscn")
		return
	# 升级面板打开时屏蔽一切玩家输入（1/2/3 与点击由 HUD 独占）
	if GameState.upgrade_open:
		return
	# Esc：暂停 / 恢复切换（过滤 echo，否则按住 Esc 会来回反复切）
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if get_tree().paused:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			mouse_locked = true
		else:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			mouse_locked = false
			if scoped:
				_set_scope(false)  # 暂停时退出开镜，避免镜片遮罩叠在暂停面板上
		return
	# B：调试用，直接跳到下一个 BOSS 波
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		_debug_jump_boss()
		return
	# 暂停界面按 R 重开本局：面板上写着这条提示，输入就必须放行（否则提示是假的）
	if get_tree().paused:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
			get_tree().paused = false
			get_tree().reload_current_scene()
		return
	# 鼠标视角：开镜时灵敏度衰减；灵敏度来自设置（GameState），不再写死
	if event is InputEventMouseMotion:
		if mouse_locked:
			var sens: float = GameState.mouse_sensitivity * sens_mult
			rotate_y(-event.relative.x * sens)
			head_base_pitch = clamp(head_base_pitch - event.relative.y * sens, -1.4, 1.4)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not mouse_locked:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				mouse_locked = true
			is_shooting = true
			_try_shoot()
		else:
			is_shooting = false
	# 右键开镜：仅狙击枪可用
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if current_weapon == "sniper":
			_set_scope(not scoped)
	if event is InputEventKey and event.pressed:
		if event.echo: return  # 过滤长按重复事件，避免按住 G 键连续扔手雷
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
		if c.name == "Muzzle":
			continue  # 保留枪口标记，别把场景里的 Marker3D 一起删了
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
		"launcher":
			# 榴弹枪：粗短枪管 + 圆形弹鼓 + 机匣 + 握把（深墨绿）
			var lc := Color(0.12, 0.16, 0.11)
			# 粗枪管（朝前 -Z）
			var lbarrel := _gun_part(Vector3(0.1, 0.1, 0.34), lc)
			lbarrel.position = Vector3(0, 0.02, -0.2)
			gun.add_child(lbarrel)
			# 枪口加粗环
			var lring := _gun_part(Vector3(0.13, 0.13, 0.05), dark)
			lring.position = Vector3(0, 0.02, -0.36)
			gun.add_child(lring)
			# 圆形弹鼓：圆柱轴向朝左右（绕 Z 轴 90°）
			var drum := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.1
			cyl.bottom_radius = 0.1
			cyl.height = 0.09
			drum.mesh = cyl
			var dmat := StandardMaterial3D.new()
			dmat.albedo_color = lc
			dmat.roughness = 0.55
			dmat.metallic = 0.5
			drum.material_override = dmat
			drum.rotation_degrees = Vector3(0, 0, 90)
			drum.position = Vector3(0, -0.07, -0.02)
			gun.add_child(drum)
			# 机匣
			var lbody := _gun_part(Vector3(0.1, 0.13, 0.18), lc)
			lbody.position = Vector3(0, 0, 0.08)
			gun.add_child(lbody)
			# 握把
			var lgrip := _gun_part(Vector3(0.05, 0.15, 0.06), dark)
			lgrip.position = Vector3(0, -0.13, 0.13)
			lgrip.rotation.x = 0.3
			gun.add_child(lgrip)

func _physics_process(delta: float) -> void:
	if game_over: return
	if get_tree().paused: return  # 节点为 PROCESS_MODE_ALWAYS，此处显式冻结玩法逻辑
	# 点屏幕重新捕获鼠标
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if not is_on_floor(): velocity.y -= gravity * delta

	var input_dir: Vector2 = Input.get_vector("move_left","move_right","move_forward","move_back")
	var dir: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var boost: float = 1.0
	if speed_boost > 0:
		boost = 1.5
	var spd: float = speed * boost * up_speed_mult * (sprint_mult if Input.is_action_pressed("sprint") else 1.0)
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

	# 脚步声：贴地且有水平速度时按节奏播放，冲刺时步频更快
	var planar_speed: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar_speed > 1.5:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.30 if Input.is_action_pressed("sprint") else 0.42
			AudioManager.play_footstep()
	else:
		_step_timer = 0.0

	# 后坐力恢复：枪身后坐量与视角俯仰偏移都平滑归零
	# 枪身按「静止位 + 偏移」施加；相机局部 +Z 指向玩家，故正值即后退
	recoil_offset = move_toward(recoil_offset, 0.0, delta * RECOIL_GUN_RECOVER)
	gun.position.z = gun_rest_z + recoil_offset
	head_recoil_offset = move_toward(head_recoil_offset, 0.0, delta * RECOIL_HEAD_RECOVER)
	# 合成最终视角：鼠标瞄准角 + 后坐偏移（不覆盖 head_base_pitch，保证鼠标输入不被打断）
	head.rotation.x = clamp(head_base_pitch + head_recoil_offset, -1.4, 1.4)
	_update_camera_shake(delta)

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
	# 切枪时停掉遗留的换弹/射击计时，避免计时回调把新武器状态打乱
	$ReloadTimer.stop()
	$ShootTimer.stop()
	# 切枪必然退出开镜
	if scoped:
		_set_scope(false)
	current_weapon = w
	weapon_idx = current_weapons.find(w)
	var cfg: Dictionary = WEAPONS[w]
	mag = mag_capacity()
	reserve = int(round(cfg.res * up_reserve_mult))
	reloading = false
	can_shoot = true
	_build_gun()
	_play_swap_anim()

# 弹匣容量：受「弹匣扩容」与「榴弹扩容」两张卡影响
# 单一出口，避免换弹/装填/显示三处各写一份 WEAPONS[...].mag 而不一致
func mag_capacity() -> int:
	var base: int = int(WEAPONS[current_weapon].mag)
	var cap: int = int(round(float(base) * up_mag_mult))
	if current_weapon == "launcher":
		cap += up_launcher_bonus
	return maxi(1, cap)

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
	# 播放枪声（走 AudioManager 的播放池）
	if gun_sound:
		AudioManager.play_sfx(gun_sound, -8.0)
	var rate: float = cfg.rate * up_rate_mult
	if GameState.player_class == "assault" and skill_active > 0:
		rate *= 0.5  # 射速翻倍
	$ShootTimer.wait_time = rate
	$ShootTimer.start()
	# 后坐力：枪身向后顿 0.12m + 视角瞬时上抬 1.5°（二者均在 _physics_process 中平滑回落）
	# 相机局部 +Z 指向玩家，所以这里必须用正值才是「后退」
	recoil_target = 0.12
	recoil_offset = recoil_target
	head_recoil_offset += deg_to_rad(1.5)
	# 屏幕震动 + 准星扩散（威力越大越猛）
	camera_shake(clamp(0.010 + cfg.dmg * 0.0003, 0.010, 0.06), 0.06)
	var hud_shoot := _hud()
	if hud_shoot and hud_shoot.has_method("kick_crosshair"):
		hud_shoot.kick_crosshair(clamp(4.0 + cfg.spread * 55.0, 4.0, 14.0))

	# 榴弹枪：不走 Raycast，抛射一枚榴弹后直接结束本次射击
	if current_weapon == "launcher":
		_launch_grenade()
		return

	# 多发子弹（霰弹枪）带散射
	var pellets: int = cfg.pellets
	var spread: float = cfg.spread * up_spread_mult  # 稳定枪管卡直接缩小散射锥
	var cam_from: Vector3 = cam.global_position
	var cam_dir: Vector3 = -cam.global_transform.basis.z
	var hit_any: bool = false
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
		var hit_prop: Object = null
		if not result.is_empty():
			hit_pos = result.position
			var col: Object = result.collider
			if col and col.is_in_group("zombie"):
				hit_z = col
			elif col and (col.is_in_group("barrel") or col.is_in_group("hazard")):
				hit_prop = col
		# 对命中的丧尸造成伤害（局内三选一 × 局外永久强化）
		if hit_z:
			var dmg: float = cfg.dmg * up_dmg_mult * GameState.meta_dmg_mult()
			if GameState.player_class == "hunter" and marked_zombie == hit_z:
				dmg *= 2.5
			hit_z.take_damage(dmg, current_weapon)
			GameState.run_damage += dmg  # 结算面板用
			_spawn_blood(hit_pos)  # 命中血珠爆发
			# 触发命中标记
			var hud := _hud()
			if hud and hud.has_method("show_hit_marker"):
				hud.show_hit_marker()
			hit_any = true
		elif hit_prop != null:
			# 可破坏场景物（油桶 / 毒气罐）：吃与武器相同的伤害，不产生血花/弹孔
			if hit_prop.has_method("take_damage"):
				hit_prop.take_damage(cfg.dmg * up_dmg_mult * GameState.meta_dmg_mult(), current_weapon)
		else:
			_spawn_hole(hit_pos, false)
	# 命中音效每发只响一次（霰弹枪 6 弹丸不再叠 6 层）
	if hit_any and hit_sound:
		AudioManager.play_sfx(hit_sound, -10.0)

func _launch_grenade() -> void:
	# 榴弹枪：抛出一枚榴弹（RigidBody3D），命中丧尸或墙体由 grenade.gd 立即引爆
	var g: RigidBody3D = preload("res://scenes/grenade.tscn").instantiate()
	# 先入树，global_position 才生效（未入树时 global_transform 是单位变换）
	get_tree().current_scene.add_child(g)
	var forward: Vector3 = -cam.global_transform.basis.z
	# 相机位于玩家胶囊体内，向前偏 0.6m 再生成，避免出生即卡在玩家身上
	var spawn_at: Vector3 = cam.global_position + forward * 0.6
	g.global_position = spawn_at
	# 35 m/s 平射：弹道平直、指哪打哪，适合应对冲脸的尸群
	g.linear_velocity = forward * 35.0
	# 高速抛射物开连续碰撞检测，避免一帧跨过薄墙造成穿透
	g.continuous_cd = true
	# 直击伤害：命中丧尸时由 grenade.gd 先结算这一份，再走范围爆炸
	g.set("direct_damage", 150.0)
	# 枪口闪光
	_muzzle_flash(spawn_at)

# ===== 屏幕震动 =====
func camera_shake(intensity: float, duration: float) -> void:
	# 取更强的一次覆盖，避免连续开枪把震动叠成高频噪声
	if intensity < _shake_amp and _shake_time > 0.0:
		return
	_shake_amp = intensity
	_shake_dur = max(duration, 0.01)
	_shake_time = _shake_dur

func _update_camera_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		return
	_shake_time -= delta
	if _shake_time <= 0.0:
		# 结束：精确还原，避免留下偏移
		cam.position = _cam_rest_pos
		cam.rotation = _cam_rest_rot
		_shake_amp = 0.0
		return
	# 线性衰减，越接近结束抖得越轻
	var k: float = clamp(_shake_time / _shake_dur, 0.0, 1.0)
	var a: float = _shake_amp * k
	cam.position = _cam_rest_pos + Vector3(randf_range(-a, a), randf_range(-a, a), 0.0)
	var rd: float = a * 30.0  # 位移量换算成角度（度）
	cam.rotation = _cam_rest_rot + Vector3(
		deg_to_rad(randf_range(-rd, rd)),
		deg_to_rad(randf_range(-rd, rd)),
		deg_to_rad(randf_range(-rd, rd) * 0.5))

# ===== 枪械动画（只动 rotation.x / position.y，不碰后坐力用的 position.z）=====
func _play_reload_anim(dur: float) -> void:
	if _reload_tween and _reload_tween.is_valid():
		_reload_tween.kill()
	# 负角度 = 枪口向下（相机局部 -Z 为前方，绕 X 轴正向会把枪口抬起来）
	_reload_tween = create_tween()
	_reload_tween.tween_property(gun, "rotation:x", -deg_to_rad(30.0), dur * 0.3).set_trans(Tween.TRANS_SINE)
	_reload_tween.tween_interval(dur * 0.4)
	_reload_tween.tween_property(gun, "rotation:x", 0.0, dur * 0.3).set_trans(Tween.TRANS_SINE)

func _play_swap_anim() -> void:
	# 切枪时先清掉可能残留的换弹倾斜
	if _reload_tween and _reload_tween.is_valid():
		_reload_tween.kill()
	gun.rotation.x = 0.0
	if _swap_tween and _swap_tween.is_valid():
		_swap_tween.kill()
	# 从屏幕下方 0.2m 处滑入
	gun.position.y = gun_rest_y - 0.2
	_swap_tween = create_tween()
	_swap_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swap_tween.tween_property(gun, "position:y", gun_rest_y, 0.18)

# ===== 开镜 =====
func weapon_display_name() -> String:
	# 供 HUD 读取当前武器名（避免 HUD 通过实例访问脚本常量）
	return str(WEAPONS[current_weapon]["name"])

func _set_scope(on: bool) -> void:
	if on == scoped:
		return
	scoped = on
	sens_mult = SCOPE_SENS_MULT if on else 1.0
	gun.visible = not on  # 开镜时隐藏枪模，避免遮挡镜片
	var tw := create_tween()
	tw.tween_property(cam, "fov", SCOPE_FOV if on else HIP_FOV, 0.12)
	var hud_scope := _hud()
	if hud_scope and hud_scope.has_method("show_scope"):
		hud_scope.show_scope(on)

# ===== 局内成长 =====
func apply_upgrade(id: String) -> void:
	up_picked.append(id)
	match id:
		"dmg":
			up_dmg_mult += 0.20
		"rate":
			up_rate_mult = max(0.45, up_rate_mult - 0.15)
		"reload":
			up_reload_mult = max(0.35, up_reload_mult - 0.30)
		"speed":
			up_speed_mult += 0.12
		"hp":
			max_hp += 25.0
			hp = max_hp
		"reserve":
			up_reserve_mult += 0.40
			reserve += int(round(WEAPONS[current_weapon].res * 0.4))
		"grenade":
			grenades += 2
		"mag":
			up_mag_mult += 0.50
			mag = mag_capacity()   # 扩容后立即补满新增容量，手感更直接
		"launcher_mag":
			up_launcher_bonus += 2
			if current_weapon == "launcher":
				mag = mag_capacity()
		"overclock":
			# 双刃剑：射速 +25%（间隔 ×0.8），伤害 -10%
			up_rate_mult = max(0.35, up_rate_mult * 0.80)
			up_dmg_mult = max(0.30, up_dmg_mult - 0.10)
		"armor":
			up_damage_taken_mult = max(0.35, up_damage_taken_mult - 0.15)
		"vamp":
			up_vamp += 8.0
		"steady":
			up_spread_mult = max(0.15, up_spread_mult * 0.60)
		"greed":
			up_crystal_mult *= 2.0
		"killboom":
			up_killboom += 35.0

# ===== 调试：跳 BOSS 波 =====
func _debug_jump_boss() -> void:
	var wm := get_parent().get_node_or_null("WaveManager")
	if wm and wm.has_method("debug_jump_to_boss"):
		wm.debug_jump_to_boss()

func _through_shot(from_pos: Vector3, dir: Vector3, exclude: Object) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var to: Vector3 = from_pos + dir.normalized() * 50
	var query := PhysicsRayQueryParameters3D.create(from_pos, to)
	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty() and result.collider != exclude and result.collider.has_method("take_damage"):
		result.collider.take_damage(120, "sniper")

func _muzzle_flash(at: Vector3) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1, 0.8, 0.3)
	flash.light_energy = 5.0
	flash.omni_range = 5.0
	get_parent().add_child(flash)
	flash.global_position = at  # 必须先入树，否则 global_position 无效
	# 补间挂在 flash 自身：枪口闪光每发都新建，绑在 player 上一旦重开场景会留下孤儿灯
	var tw := flash.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.08)
	tw.tween_callback(flash.queue_free)

func _spawn_hole(pos: Vector3, is_blood: bool) -> void:
	# 弹孔/血花：2秒后消失
	var hole := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	hole.mesh = sphere
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
	hole.global_position = pos  # 必须先入树再设 global_position，否则不在树里时全局变换不可用
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(hole.queue_free)

func _reload() -> void:
	if reloading: return
	if mag >= mag_capacity(): return
	if reserve <= 0: return
	reloading = true
	var dur: float = 0.6 * up_reload_mult
	$ReloadTimer.wait_time = dur
	$ReloadTimer.start()
	_play_reload_anim(dur)

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

func add_ammo(amount: int) -> void:
	reserve += amount

func add_hp(amount: float) -> void:
	hp = min(max_hp, hp + amount)

func add_speed_boost(duration: float) -> void:
	speed_boost = duration

func add_grenade(n: int) -> void:
	grenades += n

func add_crystal(n: int = 1) -> void:
	# 血晶只在本局累计，死亡/结算时才入总库
	GameState.add_run_crystal(n)
	var hud := _hud()
	if hud and hud.has_method("show_center"):
		hud.show_center("血晶 +%d（本局 %d）" % [n, GameState.run_crystals], 1.2)

# ===== 击杀联动（战地急救 / 连锁爆裂卡）=====
# 由 zombie.gd 的 _begin_death() 在计分后调用
func on_zombie_killed(pos: Vector3) -> void:
	if up_vamp > 0.0:
		add_hp(up_vamp)
	if up_killboom > 0.0:
		# 必须延迟：否则「A 死 → 炸死 B → B 死 → 再炸」会在同一帧里同步递归
		call_deferred("_kill_explosion", pos)

func _kill_explosion(pos: Vector3) -> void:
	var dmg: float = up_killboom * up_dmg_mult * GameState.meta_dmg_mult()
	for z in get_tree().get_nodes_in_group("zombie"):
		if not is_instance_valid(z):
			continue
		if pos.distance_to(z.global_position) > KILL_BOOM_RADIUS:
			continue
		# 用 call 而不是 z.take_damage()：组的元素静态类型是 Node，直接调用会解析失败
		if z.has_method("take_damage"):
			z.call("take_damage", dmg, "explosion")
	# 视觉：一小团橙色闪光，和油桶/手雷区分开（更短、更小）
	var scene := get_tree().current_scene
	if scene == null:
		return
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.62, 0.2)
	flash.light_energy = 4.0
	flash.omni_range = KILL_BOOM_RADIUS * 2.0
	scene.add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(flash, "light_energy", 0.0, 0.25)
	tw.tween_callback(flash.queue_free)

func take_damage(amount: float) -> void:
	if invuln > 0: return
	hp -= amount * up_damage_taken_mult  # 复合护甲卡减伤
	invuln = 0.5
	# 受击震屏：伤害越高越猛
	camera_shake(0.03 + amount * 0.0015, 0.2)
	if hp <= 0:
		hp = 0
		game_over = true
		is_shooting = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# 死亡即结算：本局血晶入库并落盘（run_settled 保证只入账一次）
		GameState.settle_run()

func _on_shoot_timer_timeout() -> void:
	can_shoot = true

func _on_reload_timer_timeout() -> void:
	var need: int = mag_capacity() - mag
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
	# 与 hud_center_msg 同源（原先这里另走 current_scene.get_node_or_null，属重复实现）
	hud_center_msg(text, 2.0)
