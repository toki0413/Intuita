extends SceneTree
func _initialize():
	var s = load("res://scripts/autoload/04_achievement_manager.gd")
	print("load ok: " + str(s))
	var am = s.new()
	print("new ok: " + str(am))
	am._load_definitions()
	print("defs: " + str(am._definitions.size()))
	quit()
