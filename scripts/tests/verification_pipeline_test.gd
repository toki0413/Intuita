# verification_pipeline_test.gd
# gdUnit4 单元测试：验证管线

extends GdUnitTestSuite


const __source = "res://scripts/autoload/12_verification_pipeline.gd"

var _pipeline: Node = null


func before() -> void:
	_pipeline = Engine.get_main_loop().root.get_node_or_null("/root/VerificationPipeline")


func test_pipeline_autoload_exists() -> void:
	assert_object(_pipeline).is_not_null()


func test_verification_layers_enum_correct() -> void:
	if _pipeline == null:
		return

	var costs: Array = _pipeline.CORE_COSTS
	assert_int(costs.size()).is_equal(5)

	var names: Array = _pipeline.LAYER_NAMES
	assert_int(names.size()).is_equal(5)

	assert_str(names[0]).is_equal("Symbolic")
	assert_str(names[1]).is_equal("TypeSystem")
	assert_str(names[2]).is_equal("Logic")
	assert_str(names[3]).is_equal("LLM")
	assert_str(names[4]).is_equal("Formal")


func test_cost_per_layer_defined() -> void:
	if _pipeline == null:
		return

	var costs: Array = _pipeline.CORE_COSTS
	assert_int(costs.size()).is_equal(5)

	assert_int(costs[0]).is_equal(0)
	assert_int(costs[1]).is_equal(0)
	assert_int(costs[2]).is_equal(1)
	assert_int(costs[3]).is_equal(2)
	assert_int(costs[4]).is_equal(5)
