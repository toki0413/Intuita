# 安装 git hooks 到 .git/hooks/
# 用法: powershell -ExecutionPolicy Bypass -File scripts/install_hooks.ps1

$hookSource = Join-Path $PSScriptRoot "hooks\pre-commit"
$gitDir = Join-Path $PSScriptRoot "..\.git"
$hookDest = Join-Path $gitDir "hooks\pre-commit"

if (-not (Test-Path $gitDir)) {
    Write-Host "[Hooks] 未找到 .git 目录，请先 git init" -ForegroundColor Red
    exit 1
}

Copy-Item $hookSource $hookDest -Force
Write-Host "[Hooks] pre-commit hook 已安装到 $hookDest" -ForegroundColor Green
