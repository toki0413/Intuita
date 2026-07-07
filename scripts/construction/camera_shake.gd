# camera_shake.gd
# 相机震动工具 - 挂载到 Camera3D 节点
# 提供轻量屏幕震动反馈，放置原子等操作时使用

extends Camera3D


func shake(amplitude: float = 0.02, duration: float = 0.1) -> void:
	var orig_h := h_offset
	var orig_v := v_offset
	var tween_h := create_tween()
	tween_h.tween_property(self, "h_offset", orig_h + randf_range(-amplitude, amplitude), duration * 0.5)
	tween_h.tween_property(self, "h_offset", orig_h, duration * 0.5)
	var tween_v := create_tween()
	tween_v.tween_property(self, "v_offset", orig_v + randf_range(-amplitude, amplitude), duration * 0.5)
	tween_v.tween_property(self, "v_offset", orig_v, duration * 0.5)
