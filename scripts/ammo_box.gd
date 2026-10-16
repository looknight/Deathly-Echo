extends Area3D
## 弹药箱：走过去拾取 +25 发子弹

@export var ammo_amount: int = 25

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var tw: Tween = create_tween().set_loops()
	tw.tween_property($Visual, "rotation:y", TAU, 2.0)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("add_ammo"):
		body.add_ammo(ammo_amount)
		queue_free()
