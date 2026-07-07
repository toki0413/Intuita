# run_performance_test.ps1
# Intuita 性能基准测试运行脚本
# 在 Windows PowerShell 中执行，自动运行 Godot 并收集报告
#
# 用法:
#   .\scripts\run_performance_test.ps1                    # 运行完整测试（默认）
#   .\scripts\run_performance_test.ps1 -Quick            # 快速测试（仅 2000 原子）
#   .\scripts\run_performance_test.ps1 -Headless          # 无头模式（不显示窗口）
#   .\scripts\run_performance_test.ps1 -GodotPath "C:\Godot\godot.exe"
#
# 输出:
#   user://performance_report.csv  →  复制到项目根目录
#   控制台打印关键指标摘要

param(
    [switch]$Quick,
    [switch]$Headless,
    [string]$GodotPath = "",
    [string]$OutputName = "performance_report"
)

$ErrorActionPreference = "Stop"

# === 1. 查找 Godot 可执行文件 ===
function Find-Godot {
    if ($GodotPath -and (Test-Path $GodotPath)) {
        return $GodotPath
    }
    
    $candidates = @(
        "C:\Program Files\Godot\Godot_v4.6.3-stable_win64.exe",
        "C:\Program Files\Godot\Godot.exe",
        "C:\Program Files (x86)\Godot\Godot.exe",
        "$env:LOCALAPPDATA\Godot\Godot.exe",
        "$env:USERPROFILE\Downloads\Godot_v4.6.3-stable_win64.exe",
        "$env:USERPROFILE\Desktop\Godot_v4.6.3-stable_win64.exe"
    )
    
    # 搜索 PATH 中是否有 godot
    $godotInPath = Get-Command "godot" -ErrorAction SilentlyContinue
    if ($godotInPath) {
        return $godotInPath.Source
    }
    
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            return $c
        }
    }
    
    # 尝试模糊搜索
    $found = Get-ChildItem -Path "C:\Program Files\Godot" -Filter "Godot*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        return $found.FullName
    }
    
    return $null
}

# === 2. 主流程 ===
Write-Host "=== Intuita 性能基准测试 ===" -ForegroundColor Cyan
Write-Host ""

$godot = Find-Godot
if (-not $godot) {
    Write-Host "错误: 找不到 Godot 可执行文件" -ForegroundColor Red
    Write-Host ""
    Write-Host "请指定路径: .\scripts\run_performance_test.ps1 -GodotPath '<路径>'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "常见安装位置:" -ForegroundColor Gray
    Write-Host "  C:\Program Files\Godot\Godot_v4.6.3-stable_win64.exe" -ForegroundColor Gray
    Write-Host "  C:\Program Files\Godot\Godot.exe" -ForegroundColor Gray
    Write-Host "  %LOCALAPPDATA%\Godot\Godot.exe" -ForegroundColor Gray
    exit 1
}

Write-Host "Godot 路径: $godot" -ForegroundColor Green

$projectRoot = Split-Path $PSScriptRoot -Parent
$projectFile = Join-Path $projectRoot "project.godot"
if (-not (Test-Path $projectFile)) {
    Write-Host "错误: 找不到 project.godot ($projectFile)" -ForegroundColor Red
    exit 1
}

# 构建命令行参数
$argsList = @(
    "--path", $projectRoot
)

if ($Headless) {
    $argsList += "--headless"
}

if ($Quick) {
    # 快速模式：仅测试 2000 原子，短测量
    $argsList += @(
        "--scene", "res://scenes/tests/performance_benchmark.tscn",
        "--atoms", "2000",
        "--stabilize", "30",
        "--measure", "60"
    )
    Write-Host "模式: 快速测试 (2000 原子)" -ForegroundColor Cyan
} else {
    $argsList += @(
        "--scene", "res://scenes/tests/performance_benchmark.tscn",
        "--atoms", "10,50,100,200,500,1000,2000",
        "--stabilize", "60",
        "--measure", "120"
    )
    Write-Host "模式: 完整测试 (10~2000 原子梯度)" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "启动性能测试场景..." -ForegroundColor Cyan
Write-Host "按 Ctrl+C 可随时终止" -ForegroundColor Gray
Write-Host ""

# 运行 Godot
$process = Start-Process -FilePath $godot -ArgumentList $argsList -PassThru -Wait -NoNewWindow

Write-Host ""
if ($process.ExitCode -ne 0) {
    Write-Host "测试进程异常退出 (exit code $($process.ExitCode))" -ForegroundColor Red
} else {
    Write-Host "测试完成" -ForegroundColor Green
}

# === 3. 收集报告 ===
$reportSource = Join-Path $env:APPDATA "Godot\app_userdata\Intuita\performance_report.csv"
$reportDest = Join-Path $projectRoot "${OutputName}.csv"

if (Test-Path $reportSource) {
    Copy-Item $reportSource $reportDest -Force
    Write-Host "报告已复制: $reportDest" -ForegroundColor Green
    
    # 解析并打印摘要
    Write-Host ""
    Write-Host "=== 性能摘要 ===" -ForegroundColor Cyan
    try {
        $csv = Import-Csv $reportDest
        foreach ($row in $csv) {
            $atoms = $row.Atoms
            $fps = $row.AvgFPS
            $minFps = $row.MinFPS
            $drawCalls = $row.DrawCalls
            Write-Host "  原子数: $($atoms.PadLeft(4)) | FPS: $([math]::Round($fps,1)).PadLeft(6) | 最低: $([math]::Round($minFps,1)).PadLeft(6) | DrawCalls: $drawCalls" -ForegroundColor White
        }
        
        # 找出瓶颈点
        $bottleneck = $csv | Where-Object { [float]$_.AvgFPS -lt 30 } | Select-Object -First 1
        if ($bottleneck) {
            Write-Host ""
            Write-Host "⚠️  瓶颈警告: $($bottleneck.Atoms) 原子场景 FPS < 30" -ForegroundColor Yellow
            Write-Host "   建议优化: 降低材质复杂度、减少阴影质量、启用 LOD" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "解析 CSV 失败: $_" -ForegroundColor Red
    }
} else {
    Write-Host "未找到报告文件 ($reportSource)" -ForegroundColor Yellow
    Write-Host "Godot 用户数据路径可能不同，请手动查找" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== 完成 ===" -ForegroundColor Cyan
