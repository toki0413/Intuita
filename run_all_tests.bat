@echo off
REM Intuita 快速启动测试
REM 在 Windows 桌面双击运行此文件，或在 PowerShell 中执行

cd /d "C:\Users\wanzh\Desktop\Intuita"

REM 检查 Godot 是否存在
if not exist "Godot_v4.6.3-stable_win64_console.exe" (
    echo [错误] 找不到 Godot 可执行文件
    echo 请确认 Godot 位于项目目录下
    pause
    exit /b 1
)

echo ========================================
echo Intuita 运行测试
echo ========================================
echo.

REM 测试 1: 加载项目并立即退出（检查基础配置）
echo [测试 1] 检查项目配置...
"Godot_v4.6.3-stable_win64_console.exe" --path . --headless --quit > test_log.txt 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [通过] 项目配置检查成功
) else (
    echo [警告] 项目配置检查返回非零码: %ERRORLEVEL%
    echo 查看 test_log.txt 获取详情
)
echo.

REM 测试 2: 运行主菜单场景（5秒后自动退出）
echo [测试 2] 运行主菜单场景（5秒）...
echo "func _ready(): await get_tree().create_timer(5).timeout; get_tree().quit()" > _temp_test.gd
"Godot_v4.6.3-stable_win64_console.exe" --path . --headless --script _temp_test.gd res://scenes/main_menu.tscn >> test_log.txt 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [通过] 主菜单场景可运行
) else (
    echo [警告] 主菜单场景运行异常
)
if exist "_temp_test.gd" del "_temp_test.gd"
echo.

REM 测试 3: 运行性能测试（快速模式）
echo [测试 3] 运行性能测试（快速模式，2000原子，约2分钟）...
"Godot_v4.6.3-stable_win64_console.exe" --path . --headless res://scenes/tests/performance_benchmark.tscn --atoms 2000 --stabilize 30 --measure 60 >> test_log.txt 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [通过] 性能测试完成
    echo 报告位置: %APPDATA%\Godot\app_userdata\Intuita\performance_report.csv
) else (
    echo [警告] 性能测试异常
)
echo.

echo ========================================
echo 测试完成
echo 完整日志: C:\Users\wanzh\Desktop\Intuita\test_log.txt
echo ========================================
pause
