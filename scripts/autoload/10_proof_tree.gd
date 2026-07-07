# proof_tree.gd
# 证明树系统 - 跟踪构造操作的证明结构
# 支持分叉、嫁接、回溯等操作
#
# Responsibilities:
#   - 维护证明树数据结构（TreeNode）
#   - 节点增删、分叉、嫁接、回溯
#   - 节点验证标记（含L5黄金标记）
#   - 树深度计算
#
# Signals:
#   node_added(node) - 新节点添加
#   node_verified(node, level) - 节点被验证
#
# Dependencies:
#   - Autoload: 无

extends Node

var _root: TreeNode = null
var _all_nodes: Dictionary = {}  # id -> TreeNode
var _next_id: int = 0

signal node_added(node: TreeNode)
signal node_verified(node: TreeNode, level: int)


class TreeNode:
	var id: int
	var operation: String
	var parent: TreeNode = null
	var children: Array[TreeNode] = []
	var invariants: Dictionary = {}  # invariant_name -> value
	var is_golden: bool = false  # L5 (Formal) verified
	var depth: int = 0
	var verification_layers: Array[int] = []  # G5: 已通过的验证层列表

	func _init(p_id: int, p_operation: String, p_parent: TreeNode = null) -> void:
		id = p_id
		operation = p_operation
		parent = p_parent
		if p_parent != null:
			depth = p_parent.depth + 1

	func add_child(child: TreeNode) -> void:
		children.append(child)
		child.parent = self
		child.depth = depth + 1

	func remove_child(child: TreeNode) -> void:
		children.erase(child)
		child.parent = null

	func get_path_to_root() -> Array[TreeNode]:
		var path: Array[TreeNode] = []
		var current: TreeNode = self
		while current != null:
			path.append(current)
			current = current.parent
		path.reverse()
		return path

	func count_descendants() -> int:
		var count := children.size()
		for child in children:
			count += child.count_descendants()
		return count


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	# 打破 TreeNode 之间的循环引用，确保退出时能正确释放
	for node in _all_nodes.values():
		node.parent = null
		node.children.clear()
	clear()


func get_root() -> TreeNode:
	return _root


func add_node(operation: String, parent: TreeNode = null, invariants: Dictionary = {}) -> TreeNode:
	var node := TreeNode.new(_next_id, operation, parent)
	node.invariants = invariants
	_all_nodes[_next_id] = node
	_next_id += 1

	if parent == null:
		if _root == null:
			_root = node
		else:
			# 未指定父节点时自动挂到根，保持单根证明树结构
			_root.add_child(node)
	else:
		parent.add_child(node)

	node_added.emit(node)
	return node


func fork(source_node: TreeNode, operation: String, invariants: Dictionary = {}) -> TreeNode:
	# 从某个节点分叉 - 创建兄弟节点
	if source_node.parent == null:
		# 从根节点分叉，创建新的根分支
		return add_node(operation, null, invariants)
	else:
		return add_node(operation, source_node.parent, invariants)


func graft(target: TreeNode, source: TreeNode) -> bool:
	# 嫁接 - 将source子树移到target下
	if target == null or source == null:
		return false

	# 检查是否会形成环
	var check: TreeNode = target
	while check != null:
		if check == source:
			push_warning("Graft would create cycle")
			return false
		check = check.parent

	# 从原父节点移除
	if source.parent != null:
		source.parent.remove_child(source)

	# 添加到目标
	target.add_child(source)
	# 递归更新子树深度
	_update_subtree_depth(source, target.depth + 1)
	return true


func backtrack(node: TreeNode) -> void:
	# 回溯 - 移除该节点及其所有后代
	if node == null:
		return

	# 收集所有后代ID
	var to_remove: Array[int] = []
	_collect_ids(node, to_remove)

	# 从父节点移除
	if node.parent != null:
		node.parent.remove_child(node)

	# 如果是根节点
	if node == _root:
		_root = null

	# 从全局字典删除
	for nid in to_remove:
		_all_nodes.erase(nid)


func _collect_ids(node: TreeNode, out: Array[int]) -> void:
	out.append(node.id)
	for child in node.children:
		_collect_ids(child, out)


const LAYER_FORMAL = 4

func verify_node(node: TreeNode, level: int) -> void:
	if node == null:
		return
	if level >= LAYER_FORMAL:  # L5 = Formal constraint verification
		node.is_golden = true
	# G5: 记录验证层
	if level not in node.verification_layers:
		node.verification_layers.append(level)
	node_verified.emit(node, level)


func get_node_by_id(id: int) -> TreeNode:
	if _all_nodes.has(id):
		return _all_nodes[id]
	return null


func get_all_nodes() -> Dictionary:
	return _all_nodes


func get_tree_depth() -> int:
	if _root == null:
		return 0
	return _get_max_depth(_root)


func _get_max_depth(node: TreeNode) -> int:
	var max_d := node.depth
	for child in node.children:
		var child_depth := _get_max_depth(child)
		if child_depth > max_d:
			max_d = child_depth
	return max_d


func clear() -> void:
	_root = null
	_all_nodes.clear()
	_next_id = 0


func _update_subtree_depth(node: TreeNode, new_depth: int) -> void:
	node.depth = new_depth
	for child in node.children:
		_update_subtree_depth(child, new_depth + 1)
