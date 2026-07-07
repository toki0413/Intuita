# 解析检查测试 - 通过加载完整场景来验证脚本可解析
# 注意：construction_canvas.gd 依赖多个 autoload，不能单独 load()
class_name ParseCheckTest
extends GdUnitTestSuite


func test_construction_canvas_parses_in_scene() -> void:
	var scene := load("res://scenes/game.tscn")
	assert_that(scene).is_not_null()
	var instance: Node = scene.instantiate()
	assert_that(instance).is_not_null()
	instance.queue_free()
