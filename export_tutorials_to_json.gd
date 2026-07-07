# export_tutorials_to_json.gd
# 一次性导出脚本：将 TutorialManager 的教程数据导出到 JSON

extends SceneTree

func _initialize():
	var root = Engine.get_main_loop().root
	var tm = root.get_node_or_null("TutorialManager")
	if tm == null:
		# 遍历子节点查找
		for child in root.get_children():
			if child.name == "TutorialManager":
				tm = child
				break
	if tm == null:
		push_error("TutorialManager not found")
		quit()
		return
	var data := {
		"steps": tm.STEPS,
		"domain_tutorials": tm.DOMAIN_TUTORIALS,
	}
	var json_str := JSON.stringify(data, "\t")
	var file := FileAccess.open("res://data/tutorials/tutorial_data.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write tutorial_data.json")
		quit()
		return
	file.store_string(json_str)
	file.close()
	print("Exported tutorial_data.json")
	quit()
