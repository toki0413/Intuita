# Intuita 视觉设计规范

> 对标 Qoder：深色科技感、玻璃拟态、霓虹光效、精致动画

## 1. 设计原则

- **深色优先**：全局深色背景，UI 以半透明暗色面板为主
- **玻璃拟态**：面板使用半透明背景 + 模糊 + 细腻边框
- **霓虹强调**：关键信息用荧光青/橙高亮，带轻微发光
- **精致动画**：每个交互都有 0.2-0.4s 的过渡动画
- **科学档案感**：像操作一台未来实验室终端

## 2. 色彩系统

| Token | Hex | 用途 |
|-------|-----|------|
| `--bg-deep` | `#030406` | 最深背景 |
| `--bg-panel` | `rgba(10, 13, 18, 0.72)` | 面板背景 |
| `--paper` | `#e8e6e3` | 主文字 |
| `--muted` | `#8b919c` | 次要文字 |
| `--cyan` | `#00f0ff` | 主强调色、成功、交互 |
| `--cyan-dim` | `rgba(0, 240, 255, 0.12)` | 青色背景光 |
| `--amber` | `#ff9f43` | 次强调、警告、标题 |
| `--green` | `#39ff14` | 完成、积极状态 |
| `--red` | `#ff4d4d` | 错误、失败 |
| `--border` | `rgba(0, 240, 255, 0.16)` | 面板边框 |
| `--border-hover` | `rgba(0, 240, 255, 0.5)` | 悬停边框 |

## 3. 字体系统

| 用途 | 字体 | 备选 |
|------|------|------|
| 大标题 | Bodoni Moda | 思源宋体 |
| 正文 | Lora | 宋体 |
| 标签/代码 | JetBrains Mono | 等宽 |

Godot 中由于字体资源限制，统一使用系统字体：
- 标题：`Microsoft YaHei` 加粗，或加载自定义 `.ttf`
- 正文：`Microsoft YaHei`
- 代码：`Consolas`

## 4. 间距与圆角

- 卡片圆角：`12px`（Godot 中 `corner_radius = 12`）
- 按钮圆角：`8px`
- 小标签圆角：`999px`
- 卡片内边距：`24px`
- 元素间距：`16px`
- 面板阴影：`0 20px 60px rgba(0,0,0,0.5)`

## 5. 动画曲线

```gdscript
const EASE_OUT_QUART = Tween.TRANS_QUART
const EASE_OUT_EXPO = Tween.TRANS_EXPO
const EASE_IN_OUT_CUBIC = Tween.TRANS_CUBIC

const DURATION_FAST = 0.2
const DURATION_NORMAL = 0.35
const DURATION_SLOW = 0.6
```

## 6. UI 组件规范

### 6.1 面板 Panel
- 背景：`bg-panel` 色
- 边框：`1px border`
- 可选：顶部 1px 发光条
- 模糊：`backdrop blur 12px`

### 6.2 按钮 Button
- 默认：透明背景 + border
- Hover：背景变 `cyan-dim`，边框变亮
- Press：轻微缩放 `scale = 0.97`
- 主要按钮：青色实心背景 + 黑色文字

### 6.3 标签 Label
- 标题：`paper` 色，字号 18-24px
- 正文：`paper` 色，字号 14-16px
- 次要：`muted` 色，字号 12-13px
- 标签/代码：`cyan` 色，等宽，11-12px

### 6.4 卡片 Card
- 同面板规范
- Hover：上浮 4px + 边框发光

## 7. 动效规范

### 7.1 入场动画
- 面板从下方 `translate_y = 30` 淡入
- 持续时间：`0.6s`
- 缓动：`ease-out-quart`

### 7.2 Hover 反馈
- 边框颜色过渡到 `border-hover`
- 背景轻微变亮
- 按钮上浮 2px

### 7.3 状态切换
- 工具切换：旧图标淡出 + 新图标淡入，`0.2s`
- 面板展开：高度从 0 到目标，`0.35s`

### 7.4 成功/失败反馈
- 成功：绿色闪光 + 轻微缩放脉冲
- 失败：红色抖动 + 面板边缘红闪

## 8. 实现方式

1. 创建 `res://resources/ui_theme.tres` 主题资源
2. 创建 `res://scripts/autoload/ui_animator.gd` 动画工具 autoload
3. 所有 UI 场景应用 `ui_theme.tres`
4. 各 UI 脚本调用 `UiAnimator` 的方法播放入场/出场动画
