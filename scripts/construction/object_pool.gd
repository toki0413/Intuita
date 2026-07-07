# object_pool.gd
# 通用对象池 - 减少频繁实例化/释放的开销

class_name ObjectPool

var _scene: PackedScene
var _pool: Array[Node] = []
var _active: Array[Node] = []
var _parent: Node
var _initial_size: int


func _init(scene_path: String, parent: Node, initial_size: int = 10) -> void:
	_scene = load(scene_path)
	if _scene == null:
		push_error("ObjectPool: 无法加载场景 %s" % scene_path)
		return
	_parent = parent
	_initial_size = initial_size
	_warm_up()


func _warm_up() -> void:
	if _scene == null:
		return
	for i in _initial_size:
		var node := _scene.instantiate()
		node.set_process(false)
		node.visible = false
		# Keep nodes free (not in tree); caller manages add_child
		_pool.append(node)


func acquire() -> Node:
	if _scene == null:
		push_error("ObjectPool: 场景未加载，无法 acquire")
		return null
	var node: Node
	if _pool.size() > 0:
		node = _pool.pop_back()
	else:
		node = _scene.instantiate()
	# 确保节点挂到正确的父节点下
	if node.get_parent() != null and node.get_parent() != _parent:
		node.get_parent().remove_child(node)
	if node.get_parent() == null:
		_parent.add_child(node)
	node.set_process(true)
	node.visible = true
	_active.append(node)
	return node


func release(node: Node) -> void:
	var idx := _active.find(node)
	if idx < 0:
		# Node wasn't acquired from this pool — just detach and free silently
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		return
	_active.remove_at(idx)
	node.set_process(false)
	node.visible = false
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	_pool.append(node)


func release_all() -> void:
	for node in _active:
		# 节点可能已被外部 free 掉，跳过空引用避免崩溃
		if node == null or not is_instance_valid(node):
			continue
		node.set_process(false)
		node.visible = false
		_pool.append(node)
	_active.clear()


func get_active_count() -> int:
	return _active.size()


func get_pool_size() -> int:
	return _pool.size()
