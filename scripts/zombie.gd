extends CharacterBody3D
## 人形丧尸：头+躯干+双臂+双腿，走路摆动

@export var zombie_type: String = "normal"
@export var speed: float = 2.0
@export var damage: float = 10.0
@export var max_hp: float = 60.0
@export var attack_range: float = 1.8

var gravity: float = 18.0
var hp: float = 60.0
var player: Node3D
var can_attack: bool = true
var walk_time: float = 0.0
var exploded: bool = false
var boss_state: int = 0  # 0=正常 1=冲刺 2=召唤 3=咆哮
var boss_skill_cd: float = 0.0
var stun_timer: float = 0.0  # 眩晕倒计时

var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var torso: MeshInstance3D
var head_node: Node3D
var is_female: bool = false

func _ready() -> void:
	add_to_group("zombie")
	is_female = randf() < 0.4
	player = get_tree().get_first_node_in_group("player")
	_build_body()
	_configure_type()

func _make_box(size: Vector3, color: Color, rough: float = 0.9, emit: float = 0.3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emit
	m.material_override = mat
	return m

func _build_body() -> void:
	var skin := Color(0.65, 0.58, 0.48)
	var cloth := Color(0.3, 0.25, 0.22)
	var pants := Color(0.15, 0.14, 0.16)
	# 体型比例：更像人
	var torso_w := 0.42 if is_female else 0.48
	var torso_d := 0.24 if is_female else 0.28
	var shoulder_x := 0.28 if is_female else 0.32

	# 骨盆
	var pelvis := _make_box(Vector3(torso_w * 0.9, 0.22, torso_d * 0.9), pants)
	pelvis.position = Vector3(0, 0.85, 0)
	add_child(pelvis)
	# 躯干（胸腔）
	torso = _make_box(Vector3(torso_w, 0.55, torso_d), cloth)
	torso.position = Vector3(0, 1.25, 0)
	add_child(torso)
	# 肩膀
	var shoulders := _make_box(Vector3(torso_w + 0.12, 0.12, torso_d), cloth.darkened(0.1))
	shoulders.position = Vector3(0, 1.52, 0)
	add_child(shoulders)
	# 头（更小更像人）
	head_node = Node3D.new()
	head_node.position = Vector3(0, 1.75, 0)
	var head_mesh := _make_box(Vector3(0.24, 0.28, 0.24), skin, 0.8, 0.2)
	head_node.add_child(head_mesh)
	# 红色眼睛
	var eye_l := _make_box(Vector3(0.04, 0.04, 0.02), Color(1, 0.1, 0.1), 0.3, 1.5)
	eye_l.position = Vector3(-0.06, 0.02, -0.13)
	head_node.add_child(eye_l)
	var eye_r := _make_box(Vector3(0.04, 0.04, 0.02), Color(1, 0.1, 0.1), 0.3, 1.5)
	eye_r.position = Vector3(0.06, 0.02, -0.13)
	head_node.add_child(eye_r)
	add_child(head_node)
	# 头发
	if is_female:
		var hair := _make_box(Vector3(0.26, 0.3, 0.26), Color(0.06, 0.05, 0.04), 0.9, 0.0)
		hair.position = Vector3(0, 0.05, 0.02)
		head_node.add_child(hair)
	else:
		var hair := _make_box(Vector3(0.25, 0.08, 0.25), Color(0.05, 0.04, 0.03), 0.9, 0.0)
		hair.position = Vector3(0, 0.16, 0)
		head_node.add_child(hair)

	# 左臂（下垂前伸）
	arm_l = Node3D.new()
	arm_l.position = Vector3(-shoulder_x, 1.48, 0)
	var arm_l_mesh := _make_box(Vector3(0.1, 0.55, 0.1), cloth.darkened(0.15))
	arm_l_mesh.position = Vector3(0, -0.28, 0)
	arm_l.add_child(arm_l_mesh)
	add_child(arm_l)
	# 右臂
	arm_r = Node3D.new()
	arm_r.position = Vector3(shoulder_x, 1.48, 0)
	var arm_r_mesh := _make_box(Vector3(0.1, 0.55, 0.1), cloth.darkened(0.15))
	arm_r_mesh.position = Vector3(0, -0.28, 0)
	arm_r.add_child(arm_r_mesh)
	add_child(arm_r)
	# 左腿
	leg_l = Node3D.new()
	leg_l.position = Vector3(-0.11, 0.8, 0)
	var leg_l_mesh := _make_box(Vector3(0.13, 0.75, 0.15), pants)
	leg_l_mesh.position = Vector3(0, -0.38, 0)
	leg_l.add_child(leg_l_mesh)
	add_child(leg_l)
	# 右腿
	leg_r = Node3D.new()
	leg_r.position = Vector3(0.11, 0.8, 0)
	var leg_r_mesh := _make_box(Vector3(0.13, 0.75, 0.15), pants)
	leg_r_mesh.position = Vector3(0, -0.38, 0)
	leg_r.add_child(leg_r_mesh)
	add_child(leg_r)
	# 红眼发光
	var glow := OmniLight3D.new()
	glow.light_color = Color(1, 0.1, 0.1)
	glow.light_energy = 0.5
	glow.omni_range = 1.5
	glow.position = Vector3(0, 1.75, 0)
	add_child(glow)

func _configure_type() -> void:
	match zombie_type:
		"runner":
			speed = 4.0; max_hp = 30.0; damage = 8.0
		"tank":
			speed = 1.2; max_hp = 200.0; damage = 25.0
			scale = Vector3(1.3,1.3,1.3)
		"exploder":
			speed = 2.5; max_hp = 40.0; damage = 50.0
			# 黄色身体标记
		"boss":
			speed = 1.8; max_hp = 800.0; damage = 35.0
			scale = Vector3(1.8,1.8,1.8)
			# BOSS红色发光更强
	hp = max_hp

func _physics_process(delta: float) -> void:
	if not is_on_floor(): velocity.y -= gravity * delta
	# 眩晕：减速停止
	if stun_timer > 0:
		stun_timer -= delta
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	if player == null or not is_instance_valid(player): return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()

	# BOSS技能冷却
	if boss_skill_cd > 0:
		boss_skill_cd -= delta

	if dist > attack_range:
		var dir := to_player.normalized()
		var move_speed: float = speed
		# BOSS冲刺
		if zombie_type == "boss" and boss_state == 1:
			move_speed = speed * 4.0
			boss_state = 0
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
		walk_time += delta * 7.0
		# 走路动画：腿大步迈，臂前伸摆动，身体前倾
		var swing := sin(walk_time)
		leg_l.rotation.x = -swing * 0.6
		leg_r.rotation.x = swing * 0.6
		arm_l.rotation.x = 1.2 + swing * 0.2  # 手臂前伸够人
		arm_r.rotation.x = 1.2 - swing * 0.2
		head_node.rotation.x = -0.15  # 头微低
		torso.rotation.x = 0.1  # 身体前倾
		torso.position.y = 1.25 + abs(sin(walk_time)) * 0.03
	else:
		velocity.x = 0; velocity.z = 0
		# 攻击：双臂前伸抓
		arm_l.rotation.x = 1.5
		arm_r.rotation.x = 1.5
		if zombie_type == "exploder" and not exploded:
			_explode()
		elif can_attack:
			_attack()

	# BOSS特殊技能
	if zombie_type == "boss" and boss_skill_cd <= 0 and dist < 20:
		var roll: float = randf()
		if roll < 0.3:
			boss_state = 1  # 冲刺
			boss_skill_cd = 5.0
		elif roll < 0.6:
			_boss_summon()
			boss_skill_cd = 8.0
		else:
			_boss_roar()
			boss_skill_cd = 10.0

	move_and_slide()

func _boss_summon() -> void:
	# 召唤2个runner
	var wm := get_parent()
	if wm and wm.has_method("_spawn_zombie"):
		for i in range(2):
			var offset := Vector3(randf_range(-3,3), 1.0, randf_range(-3,3))
			wm._spawn_zombie("runner", global_position + offset)
	# 召唤提示光
	var flash := OmniLight3D.new()
	flash.light_color = Color(1,0.2,0.5)
	flash.light_energy = 3.0
	flash.omni_range = 4.0
	flash.position = global_position
	get_parent().add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)

func _boss_roar() -> void:
	# 咆哮：减速玩家3秒
	if player and player.has_method("add_slow"):
		player.add_slow(3.0)
	# 咆哮冲击波光
	var flash := OmniLight3D.new()
	flash.light_color = Color(1,0.8,0.2)
	flash.light_energy = 4.0
	flash.omni_range = 8.0
	flash.position = global_position
	get_parent().add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.6)
	tw.tween_callback(flash.queue_free)

func _attack() -> void:
	can_attack = false
	$AttackTimer.start()
	if player and player.has_method("take_damage"):
		player.take_damage(damage)

func _explode() -> void:
	exploded = true
	# 谁死谁清理：若被猎手标记，自爆时清除
	if player and is_instance_valid(player) and player.get("marked_zombie") == self:
		player.set("marked_zombie", null)
	if player and global_position.distance_to(player.global_position) < 3.5:
		player.take_damage(50.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1,0.5,0.1)
	flash.light_energy = 5.0
	flash.omni_range = 6.0
	flash.position = global_position
	get_parent().add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.3)
	tw.tween_callback(flash.queue_free)
	GameState.kills += 1
	queue_free()

func take_damage(amount: float, weapon_type: String = "pistol") -> void:
	hp -= amount
	if hp <= 0: die()

func die() -> void:
	# 谁死谁清理：若被猎手标记，死亡时清除
	if player and is_instance_valid(player) and player.get("marked_zombie") == self:
		player.set("marked_zombie", null)
	GameState.kills += 1
	GameState.combo += 1
	GameState.combo_timer = 3.0
	if randf() < 0.3:
		var drop: String = ["ammo","medkit","speed","grenade"].pick_random()
		_spawn_drop(drop)
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", -PI/2, 0.3)
	tw.tween_callback(queue_free)

func _spawn_drop(type: String) -> void:
	var drop := Area3D.new()
	drop.position = global_position
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4,0.3,0.4)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	match type:
		"ammo": mat.albedo_color = Color(0.8,0.65,0.3)
		"medkit": mat.albedo_color = Color(0.9,0.2,0.2)
		"speed": mat.albedo_color = Color(0.2,0.8,0.9)
		"grenade": mat.albedo_color = Color(0.5,0.5,0.2)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.5
	mesh.material_override = mat
	drop.add_child(mesh)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(0.6,0.5,0.6)
	col.shape = cs
	drop.add_child(col)
	drop.body_entered.connect(func(body):
		if body.is_in_group("player"):
			match type:
				"ammo": body.add_ammo(30)
				"medkit": body.add_hp(40)
				"speed": body.add_speed_boost(20.0)
				"grenade": body.add_grenade(1)
			drop.queue_free()
	)
	get_parent().add_child(drop)

func _on_attack_timer_timeout() -> void:
	can_attack = true
