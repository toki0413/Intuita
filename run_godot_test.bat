@echo off
echo [TEST] Starting Godot test at %date% %time% > C:\Users\wanzh\Desktop\Intuita\godot_test.log 2>&1
echo [TEST] Running Godot headless... >> C:\Users\wanzh\Desktop\Intuita\godot_test.log 2>&1
"C:\Users\wanzh\Desktop\Intuita\Godot_v4.6.3-stable_win64_console.exe" --path "C:\Users\wanzh\Desktop\Intuita" --headless --quit >> C:\Users\wanzh\Desktop\Intuita\godot_test.log 2>&1
echo [TEST] Godot exit code: %ERRORLEVEL% >> C:\Users\wanzh\Desktop\Intuita\godot_test.log 2>&1
echo [TEST] Done at %date% %time% >> C:\Users\wanzh\Desktop\Intuita\godot_test.log 2>&1
