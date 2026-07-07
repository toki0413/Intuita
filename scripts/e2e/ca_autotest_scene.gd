# CA 模式自动化测试入口
# 直接加载 Chapter 4 Level 6 (Bays' 4555)，供 pyautogui 外部操控
extends Node

func _ready() -> void:
	GameState.set_mode(GameState.GameMode.CAMPAIGN)
	LevelManager.load_level(4, 6)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
