# morphism_system.gd
# 态射系统 - 跟踪操作类型及其对不变量的影响
# 对应Rust侧的MorphismCategory
#
# Responsibilities:
#   - 定义态射类别枚举（同构/同态/满态射/单态射等）
#   - 态射组合规则
#   - 跟踪操作历史和不变量变化
#
# Signals:
#   operation_applied(operation_type, changes) - 操作被应用
#
# Dependencies:
#   - Autoload: 无

extends Node
enum MorphismCategory {
	ISOMORPHISM,        # 同构 - 完全可逆
	HOMOMORPHISM,       # 同态 - 保持结构
	EPIMORPHISM,        # 满态射 - 满射
	MONOMORPHISM,       # 单态射 - 单射
	ENDOMORPHISM,       # 自同态
	AUTOMORPHISM,       # 自同构
	FUNCTOR,            # 函子
	NATURAL_TRANS,      # 自然变换
}

var invariants_kept: Array[String] = []
var invariants_lost: Array[String] = []
var invariants_introduced: Array[String] = []

var _operation_history: Array[Dictionary] = []

signal operation_applied(operation_type: int, changes: Dictionary)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func compose(cat_a: MorphismCategory, cat_b: MorphismCategory) -> MorphismCategory:
	# 态射组合规则 - 简化但逻辑自洽
	# 同构 x 同构 = 同构
	if cat_a == MorphismCategory.ISOMORPHISM and cat_b == MorphismCategory.ISOMORPHISM:
		return MorphismCategory.ISOMORPHISM

	# 自同构 x 任何 = 任何 (自同构是同构的特例)
	if cat_a == MorphismCategory.AUTOMORPHISM:
		return cat_b
	if cat_b == MorphismCategory.AUTOMORPHISM:
		return cat_a

	# 单态射 x 满态射 = 可能同构，保守返回同态
	if cat_a == MorphismCategory.MONOMORPHISM and cat_b == MorphismCategory.EPIMORPHISM:
		return MorphismCategory.HOMOMORPHISM
	if cat_a == MorphismCategory.EPIMORPHISM and cat_b == MorphismCategory.MONOMORPHISM:
		return MorphismCategory.HOMOMORPHISM

	# 单态射 x 单态射 = 单态射
	if cat_a == MorphismCategory.MONOMORPHISM and cat_b == MorphismCategory.MONOMORPHISM:
		return MorphismCategory.MONOMORPHISM

	# 满态射 x 满态射 = 满态射
	if cat_a == MorphismCategory.EPIMORPHISM and cat_b == MorphismCategory.EPIMORPHISM:
		return MorphismCategory.EPIMORPHISM

	# 函子 x 函子 = 函子
	if cat_a == MorphismCategory.FUNCTOR and cat_b == MorphismCategory.FUNCTOR:
		return MorphismCategory.FUNCTOR

	# 自然变换提升为函子
	if cat_a == MorphismCategory.NATURAL_TRANS or cat_b == MorphismCategory.NATURAL_TRANS:
		return MorphismCategory.FUNCTOR

	# 默认: 同态
	return MorphismCategory.HOMOMORPHISM


func is_invertible(cat: MorphismCategory) -> bool:
	match cat:
		MorphismCategory.ISOMORPHISM, MorphismCategory.AUTOMORPHISM:
			return true
		_:
			return false


func apply_operation(cat: MorphismCategory, kept: Array[String], lost: Array[String], introduced: Array[String]) -> void:
	invariants_kept.append_array(kept)
	invariants_lost.append_array(lost)
	invariants_introduced.append_array(introduced)

	var changes: Dictionary = {
		"category": cat,
		"kept": kept,
		"lost": lost,
		"introduced": introduced,
		"timestamp": Time.get_ticks_msec(),
	}
	_operation_history.append(changes)

	operation_applied.emit(cat, changes)


func get_history() -> Array[Dictionary]:
	return _operation_history


func clear_history() -> void:
	_operation_history.clear()
	invariants_kept.clear()
	invariants_lost.clear()
	invariants_introduced.clear()
