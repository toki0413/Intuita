# download_sonniss.ps1
# Sonniss GDC 2026 音效包下载脚本
# 支持断点续传、自动解压、完整性校验
#
# 用法:
#   .\scripts\download_sonniss.ps1 -Url "https://..."              # 直接下载
#   .\scripts\download_sonniss.ps1 -Url "..." -Resume              # 断点续传
#   .\scripts\download_sonniss.ps1 -Manual                        # 仅显示手动指南
#   .\scripts\download_sonniss.ps1 -Verify                      # 校验已下载文件
#
# 注意: Sonniss 官网有 Cloudflare 保护，需要浏览器获取下载链接。
#       请在浏览器中打开 https://gdc.sonniss.com/，完成验证后，
#       使用 DevTools (F12) Network 面板获取 zip 的直接下载链接。

param(
    [string]$Url = "",
    [switch]$Resume,
    [switch]$Manual,
    [switch]$Verify,
    [string]$OutputDir = "assets\third_party\sonniss",
    [string]$TempFile = "$env:TEMP\sonniss_gdc_2026.zip"
)

$ErrorActionPreference = "Stop"

function Show-ManualGuide {
    Write-Host "=== Sonniss GDC 2026 手动下载指南 ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. 在浏览器中打开 https://gdc.sonniss.com/" -ForegroundColor Yellow
    Write-Host "2. 完成 Cloudflare 人机验证" -ForegroundColor Yellow
    Write-Host "3. 填写邮箱或直接点击下载按钮" -ForegroundColor Yellow
    Write-Host "4. 按 F12 打开 DevTools → Network 面板" -ForegroundColor Yellow
    Write-Host "5. 点击下载，观察 Network 面板中的 zip 请求" -ForegroundColor Yellow
    Write-Host "6. 右键点击该请求 → Copy → Copy as cURL (bash)" -ForegroundColor Yellow
    Write-Host "7. 提取其中的 URL，运行: .\scripts\download_sonniss.ps1 -Url '<URL>'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "备选镜像:" -ForegroundColor Green
    Write-Host "  - 历史存档: https://sonniss.com/gameaudiogdc/ (200GB+)" -ForegroundColor White
    Write-Host "  - 社区镜像: https://gamesounds.xyz/ (可能有延迟)" -ForegroundColor White
    Write-Host ""
    Write-Host "许可: 免版税、商用、无需署名 | 禁止 AI/ML 训练" -ForegroundColor Magenta
}

function Test-Integrity {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Host "文件不存在: $Path" -ForegroundColor Red
        return $false
    }
    
    $size = (Get-Item $Path).Length
    Write-Host "文件大小: $([math]::Round($size / 1GB, 2)) GB" -ForegroundColor Cyan
    
    # 7.47 GB 的 zip 至少应该 > 7 GB
    if ($size -lt 7GB) {
        Write-Host "警告: 文件大小不足 7 GB，可能不完整" -ForegroundColor Yellow
        return $false
    }
    
    # 尝试读取 zip 结尾的中央目录签名 (0x06054b50)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $fs.Position = [Math]::Max(0, $fs.Length - 65536)
        $buffer = New-Object byte[] 65536
        $read = $fs.Read($buffer, 0, 65536)
        $sig = [BitConverter]::ToUInt32($buffer, $read - 22)
        if ($sig -eq 0x06054b50) {
            Write-Host "ZIP 中央目录签名验证通过" -ForegroundColor Green
            return $true
        } else {
            Write-Host "ZIP 签名不匹配，文件可能损坏" -ForegroundColor Red
            return $false
        }
    } finally {
        $fs.Close()
    }
}

function Invoke-Download {
    param([string]$DownloadUrl)
    
    Write-Host "开始下载 Sonniss GDC 2026 音效包..." -ForegroundColor Cyan
    Write-Host "来源: $DownloadUrl" -ForegroundColor Gray
    Write-Host "目标: $TempFile" -ForegroundColor Gray
    Write-Host ""
    
    $headers = @{
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        "Accept" = "application/zip,application/octet-stream,*/*"
    }
    
    try {
        if ($Resume -and (Test-Path $TempFile)) {
            $existingSize = (Get-Item $TempFile).Length
            Write-Host "断点续传: 已下载 $([math]::Round($existingSize / 1MB, 2)) MB" -ForegroundColor Cyan
            $headers["Range"] = "bytes=$existingSize-"
        }
        
        $response = Invoke-WebRequest -Uri $DownloadUrl -Headers $headers -OutFile $TempFile -PassThru -UseBasicParsing
        Write-Host "下载完成: HTTP $($response.StatusCode)" -ForegroundColor Green
        
        return Test-Integrity -Path $TempFile
    } catch {
        Write-Host "下载失败: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "可能原因:" -ForegroundColor Yellow
        Write-Host "  - Cloudflare 拦截了直接下载" -ForegroundColor White
        Write-Host "  - 链接已过期或需要 cookies" -ForegroundColor White
        Write-Host "  - 网络不稳定" -ForegroundColor White
        Write-Host ""
        Write-Host "建议: 使用 -Manual 查看手动下载指南" -ForegroundColor Cyan
        return $false
    }
}

function Expand-ArchiveSafe {
    param([string]$ZipPath, [string]$DestDir)
    
    Write-Host "解压到: $DestDir" -ForegroundColor Cyan
    
    if (-not (Test-Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }
    
    try {
        # 使用 .NET 解压（避免 Windows 内置解压的 260 字符路径限制）
        Add-Type -Assembly System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestDir)
        Write-Host "解压完成" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "解压失败: $_" -ForegroundColor Red
        Write-Host "尝试使用 Expand-Archive..." -ForegroundColor Yellow
        try {
            Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force
            Write-Host "解压完成" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "解压失败: $_" -ForegroundColor Red
            return $false
        }
    }
}

# === Main ===

if ($Manual) {
    Show-ManualGuide
    exit 0
}

if ($Verify) {
    Test-Integrity -Path $TempFile
    exit 0
}

if (-not $Url) {
    Write-Host "错误: 未提供下载链接" -ForegroundColor Red
    Show-ManualGuide
    exit 1
}

$success = Invoke-Download -DownloadUrl $Url
if ($success) {
    $projectRoot = Split-Path $PSScriptRoot -Parent
    $dest = Join-Path $projectRoot $OutputDir
    Expand-ArchiveSafe -ZipPath $TempFile -DestDir $dest
    
    Write-Host ""
    Write-Host "=== 下载完成 ===" -ForegroundColor Green
    Write-Host "音效文件位于: $dest" -ForegroundColor Cyan
    Write-Host "请在 Godot 中重新导入项目，SoundManager 会自动注册这些音效" -ForegroundColor Yellow
} else {
    exit 1
}
