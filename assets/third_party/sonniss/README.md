# Sonniss GDC 2026 Game Audio Bundle - 下载指南

> **容量**: 7.47 GB (347+ WAV 文件) | **许可**: 免版税、商用、无需署名 | **来源**: https://gdc.sonniss.com/

## 手动下载步骤

由于 Sonniss 官网启用了 Cloudflare 安全验证，**自动下载脚本在当前环境下会被拦截**。请按以下步骤手动下载：

1. 在浏览器中打开 **https://gdc.sonniss.com/**
2. 完成 Cloudflare 验证（通常只需点击"I'm not a robot"）
3. 在页面中填写邮箱（可选）或直接点击下载按钮
4. 下载 `Sonniss GDC 2026 Game Audio Bundle.zip`
5. 解压到 `assets/third_party/sonniss/` 目录下，保持文件夹结构：

```
assets/third_party/sonniss/
├── 344 Audio/
├── Alexander Kopeikin/
├── CB Sounddesign/
├── Cinematic Sound Design/
├── David Dumais Audio/
├── Epic Stock Media/
├── Federico Soler/
├── InMotionAudio/
├── Ivo Vicic/
├── Jake Fielding/
├── Just Sound Effects/
├── Sonic Bat/
├── Sonik Sound Library/
├── SoundBits/
├── The Noisery/
├── TheWorkRoom/
└── Victor Ermakov/
```

## 备选镜像（如果官网下载慢）

- 社区镜像: https://gamesounds.xyz/ (历史包，2026 年包可能尚未同步)
- 历史 GDC 包存档: https://sonniss.com/gameaudiogdc/ (200GB+ 免费音效)

## 自动下载脚本（备用）

如果你已经获得了直接下载链接（例如从浏览器 DevTools Network 面板中提取），可以运行：

```powershell
# 在项目根目录执行
.\scripts\download_sonniss.ps1 -Url "YOUR_DIRECT_LINK"
```

该脚本支持：
- 断点续传（`-Resume`）
- 自动解压到正确目录
- 校验文件完整性

## SoundManager 集成说明

解压完成后，SoundManager 会自动扫描 `assets/third_party/sonniss/` 下的 WAV 文件，并注册到对应的游戏音效槽位：

| 游戏音效 | 搜索关键词 | 回退方案 |
|---------|-----------|---------|
| CLICK_LOCK | click, tap, button | 程序化 1200Hz 正弦波 |
| SOFT_MODE_LOCK | soft, gentle, light | 程序化 800Hz 正弦波 |
| FOG_ENTER | fog, mist, ambient | 程序化白噪音 |
| CONSERVATION_WARN | warning, alert, buzz | 程序化方波 |
| SOLUTION_FOUND | success, chime, positive | 程序化和弦 |
| LEVEL_COMPLETE | complete, win, achievement | 程序化扫频 |
| MISTAKE | error, mistake, negative | 程序化噪声 |
| BACKTRACK | undo, back, reverse | 程序化降调 |
| MORPHISM_APPLY | transform, morph, shift | 程序化滑音 |
| QUANTUM_COLLAPSE | quantum, collapse, burst | 程序化爆发音 |
| THEME_INTRO | theme, intro, ambient | 程序化环境音 |

如果找不到匹配的外部文件，SoundManager 会自动使用程序化生成作为回退，确保游戏音效始终可用。

## 许可证

> "Everything is royalty-free and commercially usable. No attribution is required and you can use them on an unlimited number of projects for the rest of your lifetime."
>
> ⚠️ **禁止用于 AI/ML 训练**（明确排除于许可范围之外）

---
*Generated for Intuita project | 2026-06-07*
