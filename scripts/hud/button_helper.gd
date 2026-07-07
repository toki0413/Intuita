# button_helper.gd
# 通用按钮反馈工具 - 挂载到任何Button节点即可获得标准反馈
# 提供悬停缩放、点击缩放、音效播放和禁用态灰化
#
# Responsibilities:
#   - 悬停时缩放动画
#   - 点击时缩放+音效
#   - 禁用态自动灰化
#
# Signals:
#   无（使用Button自身信号）
#
# Dependencies:
#   - Autoload: SoundManager

extends Button

@export var click_sound: String = "click"
@export var hover_scale: float = 1.05
@export var press_scale: float = 0.95
@export var animation_duration: float = 0.1

var _original_scale: Vector2
var _original_modulate: Color
var _is_setup: bool = false


func _ready() -> void:
	_original_scale = scale
	_original_modulate = modulate
	_is_setup = true

	mouse_entered.connect(_on_hover_in)
	mouse_exited.connect(_on_hover_out)
	button_down.connect(_on_press)
	button_up.connect(_on_release)

	# 监听禁用状态变化
	# disabled_changed is not available in Godot 4.6, use notification instead
	_update_disabled_visual()


func _notification(what: int) -> void:
	# NOTIFICATION_DISABLED_CHANGED = 44 in Godot 4.x
	if what == 44:
		_update_disabled_visual()


func _on_hover_in() -> void:
	if disabled:
		return
	var tween := create_tween()
	tween.tween_property(self, "scale", _original_scale * hover_scale, animation_duration).set_ease(Tween.EASE_OUT)


func _on_hover_out() -> void:
	if disabled:
		return
	var tween := create_tween()
	tween.tween_property(self, "scale", _original_scale, animation_duration).set_ease(Tween.EASE_OUT)


func _on_press() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", _original_scale * press_scale, 0.05).set_ease(Tween.EASE_IN)
	_play_click_sound()


func _on_release() -> void:
	var target := _original_scale * hover_scale if is_hovered() and not disabled else _original_scale
	var tween := create_tween()
	tween.tween_property(self, "scale", target, animation_duration).set_ease(Tween.EASE_OUT)


func _on_disabled_changed() -> void:
	_update_disabled_visual()


func _update_disabled_visual() -> void:
	if not _is_setup:
		return
	if disabled:
		modulate = Color(0.5, 0.5, 0.5, 0.6)
		mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	else:
		modulate = _original_modulate
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _play_click_sound() -> void:
	if not is_instance_valid(SoundManager):
		return
	# 尝试通过SoundManager播放，回退到静默
	if click_sound == "click":
		SoundManager.play(SoundManager.SoundType.CLICK_LOCK)
	elif click_sound == "verify":
		SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS)
	elif click_sound == "delete":
		SoundManager.play(SoundManager.SoundType.DISINTEGRATE_START)
	elif click_sound == "core_spend":
		SoundManager.play(SoundManager.SoundType.CORE_SPEND)
