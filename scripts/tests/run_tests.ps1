# run_tests.ps1
# One-click runner for Intuita's gdUnit4 test suite

param(
    [string]$GodotPath = "",
    [string]$TestPath = "res://scripts/tests/",
    [switch]$InstallGdUnit
)

$ErrorActionPreference = "Stop"

# Locate project root from the script's own path so this works from any working directory.
$scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$scriptDir = Split-Path -Parent $scriptPath
$baseDir = Split-Path -Parent (Split-Path -Parent $scriptDir)

# 1. Locate Godot executable
if ($GodotPath -eq "") {
    $candidates = @(
        "$baseDir\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe",
        "$baseDir\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe",
        (Get-Command "godot" -ErrorAction SilentlyContinue).Source
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            $GodotPath = $c
            break
        }
    }
}

if (-not (Test-Path $GodotPath)) {
    Write-Host "ERROR: Godot executable not found" -ForegroundColor Red
    Write-Host "Specify -GodotPath or place Godot in the project root"
    exit 1
}

Write-Host "Using Godot: $GodotPath" -ForegroundColor Cyan

# 2. Verify gdUnit4 is installed
$gdUnitPath = "$baseDir\addons\gdUnit4"
if (-not (Test-Path $gdUnitPath)) {
    Write-Host ""
    Write-Host "gdUnit4 is not installed. Install manually:" -ForegroundColor Yellow
    Write-Host "  1. Download v6.1.3: https://github.com/godot-gdunit-labs/gdUnit4/archive/refs/tags/v6.1.3.zip"
    Write-Host "  2. Extract to a temporary folder"
    Write-Host "  3. Copy gdUnit4-6.1.3/addons/gdUnit4 to $baseDir\addons\gdUnit4"
    Write-Host "  4. Enable the GdUnit4 plugin in Godot (Project -> Project Settings -> Plugins)"
    Write-Host ""
    Write-Host "Or run this script with -InstallGdUnit to attempt automatic download (requires network)"
    exit 1
}

# 3. (Optional) Try to auto-install gdUnit4
if ($InstallGdUnit -and -not (Test-Path $gdUnitPath)) {
    Write-Host "Attempting to download gdUnit4 v6.1.3..." -ForegroundColor Cyan
    $zip = "$env:TEMP\gdUnit4-v6.1.3.zip"
    try {
        Invoke-WebRequest -Uri "https://github.com/godot-gdunit-labs/gdUnit4/archive/refs/tags/v6.1.3.zip" -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath "$env:TEMP\gdUnit4_extract" -Force
        New-Item -ItemType Directory -Path $gdUnitPath -Force | Out-Null
        Copy-Item -Path "$env:TEMP\gdUnit4_extract\gdUnit4-6.1.3\addons\gdUnit4\*" -Destination $gdUnitPath -Recurse -Force
        Remove-Item $zip -Force
        Remove-Item "$env:TEMP\gdUnit4_extract" -Recurse -Force
        Write-Host "gdUnit4 installed to $gdUnitPath" -ForegroundColor Green
    } catch {
        Write-Host "Automatic download failed: $_" -ForegroundColor Red
        exit 1
    }
}

# 4. Run tests
Write-Host ""
Write-Host "Running tests: $TestPath" -ForegroundColor Cyan
$godotArgs = @(
    "--headless",
    "--path", $baseDir,
    "-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd",
    "--add", $TestPath,
    "--ignoreHeadlessMode"
)

& $GodotPath @godotArgs
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "TESTS FAILED (exit code $exitCode)" -ForegroundColor Red
}

exit $exitCode
