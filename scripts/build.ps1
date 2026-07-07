# 自动构建脚本：源码变更后重新导出 .pck，避免运行时脚本不同步
# 用法: powershell -ExecutionPolicy Bypass -File scripts/build.ps1
param(
    [string]$GodotPath = "godot",
    [string]$PresetName = "Windows Desktop"
)

$ErrorActionPreference = "Stop"

Write-Host "[Build] 开始导出 Intuita..." -ForegroundColor Cyan
$startTime = Get-Date

# 先做语法检查，避免导出带错误的脚本
Write-Host "[Build] 检查脚本语法..." -ForegroundColor Yellow
$checkResult = & $GodotPath --headless --check-only --script res://scripts/game.gd 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[Build] 脚本语法检查失败:" -ForegroundColor Red
    Write-Host $checkResult
    exit 1
}

# 导出项目
Write-Host "[Build] 导出 preset: $PresetName..." -ForegroundColor Yellow
& $GodotPath --headless --export-release "$PresetName" 2>&1 | ForEach-Object { Write-Host $_ }

if ($LASTEXITCODE -ne 0) {
    Write-Host "[Build] 导出失败 (exit code: $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

$elapsed = (Get-Date) - $startTime
Write-Host "[Build] 导出完成，用时 $([math]::Round($elapsed.TotalSeconds, 1))s" -ForegroundColor Green
Write-Host "[Build] 输出: build/Intuita.exe + build/Intuita.pck" -ForegroundColor Green
