extends RigidBody3D
## 手雷：碰到碰撞体爆炸，范围伤害

var timer: float = 2.5

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_collide)

func _physics_process(delta: float) -> void:
	timer -= delta
	if timer <= 0: explode()

func _on_collide(body: Node3D) -> void:
	# 碰到丧尸才立即爆炸，碰到地面继续等引信
	if body.is_in_group("zombie"):
		explode()

func explode() -> void:
	if not is_instance_valid(self): return
	var center: Vector3 = global_position
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 5.0
	q.shape = sphere
	q.transform = Transform3D(Basis(), center)
	q.collide_with_areas = true
	var results: Array = space.intersect_shape(q)
	for r in results:
		var col: Object = r.collider
		if col == self: continue
		# 排除玩家自己
		if col is CharacterBody3D and col.is_in_group("player"): continue
		if col and col.has_method("take_damage"):
			var d: float = center.distance_to(col.global_position)
			col.take_damage(max(20.0, 100.0 - d * 15.0), "explosion")
	var flash: OmniLight3D = OmniLight3D.new()
	flash.light_color = Color(1, 0.6, 0.2)
	flash.light_energy = 8.0
	flash.omni_range = 10.0
	flash.position = center
	get_parent().add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.4)
	tw.tween_callback(flash.queue_free)
	queue_free()
