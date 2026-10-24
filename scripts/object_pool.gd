extends Node
## 通用对象池（Autoload: ObjectPool）
##
## pools 用「预制体资源路径 -> 实例数组」管理所有对象。
## 每个实例用 meta "pool_active" 标记是否被占用，用 meta "pool_key" 记住所属池。
## 重要：回收时只是「停用」，节点始终留在原父节点下，避免 reparent 造成的物理帧风险。

var pools: Dictionary = {}

func spawn(scene: PackedScene, parent: Node = null) -> Node:
	if scene == null:
		return null
	var key: String = scene.resource_path
	if not pools.has(key):
		pools[key] = []

	# 先剔除已失效的引用（切场景/重开后旧实例已被释放）
	var live: Array = []
	for c in pools[key]:
		if is_instance_valid(c):
			live.append(c)
	pools[key] = live

	# 取一个空闲实例
	var node: Node = null
	for c in live:
		if not bool(c.get_meta("pool_active", false)):
			node = c
			break

	# 池里没有空闲的就新建
	if node == null:
		node = scene.instantiate()
		node.set_meta("pool_key", key)
		node.set_meta("pool_active", false)
		# 记录原始碰撞层：回收时清零（防死尸挡枪/挡路），复用时还原
		if node is CollisionObject3D:
			node.set_meta("pool_layer", node.collision_layer)
			node.set_meta("pool_mask", node.collision_mask)
		# 直接挂到目标父节点，后续不再搬家
		if parent != null:
			parent.add_child(node)
		else:
			add_child(node)
		pools[key].append(node)

	node.set_meta("pool_active", true)
	_activate(node)
	return node

func recycle(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.set_meta("pool_active", false)
	_deactivate(node)

func _activate(node: Node) -> void:
	_set_visible(node, true)
	node.process_mode = Node.PROCESS_MODE_INHERIT
	if node is CollisionObject3D:
		node.collision_layer = int(node.get_meta("pool_layer", 1))
		node.collision_mask = int(node.get_meta("pool_mask", 1))

func _deactivate(node: Node) -> void:
	_set_visible(node, false)
	# DISABLED 会同时停掉 _process / _physics_process，并脱离暂停体系
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	# 交给对象自己清理状态（移出分组、杀掉残留补间等）
	if node.has_method("on_recycled"):
		node.on_recycled()

func _set_visible(node: Node, v: bool) -> void:
	if node is Node3D:
		node.visible = v
	elif node is CanvasItem:
		node.visible = v

func active_count(scene: PackedScene) -> int:
	if scene == null:
		return 0
	var key: String = scene.resource_path
	var n: int = 0
	if pools.has(key):
		for c in pools[key]:
			if is_instance_valid(c) and bool(c.get_meta("pool_active", false)):
				n += 1
	return n
