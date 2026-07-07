# 临时场景加载测试 - 验证修改后的场景能正常实例化
class_name SceneLoadTest
extends GdUnitTestSuite


func test_game_scene_loads() -> void:
	var scene := load("res://scenes/game.tscn") as PackedScene
	assert_that(scene).is_not_null()
	var instance := scene.instantiate()
	assert_that(instance).is_not_null()
	instance.queue_free()


func test_main_menu_scene_loads() -> void:
	var scene := load("res://scenes/main_menu.tscn") as PackedScene
	assert_that(scene).is_not_null()
	var instance := scene.instantiate()
	assert_that(instance).is_not_null()
	instance.queue_free()


func test_tool_panel_scene_loads() -> void:
	var scene := load("res://scenes/hud/tool_panel.tscn") as PackedScene
	assert_that(scene).is_not_null()
	var instance := scene.instantiate()
	assert_that(instance).is_not_null()
	instance.queue_free()


func test_conservation_hud_scene_loads() -> void:
	var scene := load("res://scenes/hud/conservation_hud.tscn") as PackedScene
	assert_that(scene).is_not_null()
	var instance := scene.instantiate()
	assert_that(instance).is_not_null()
	instance.queue_free()
