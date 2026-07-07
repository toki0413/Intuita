$godot = "C:\Users\wanzh\Desktop\Intuita\Godot_v4.6.3-stable_win64_console.exe"
$project = "C:\Users\wanzh\Desktop\Intuita"
$logFile = "C:\Users\wanzh\Desktop\Intuita\godot_test.log"

if (-not (Test-Path $godot)) {
    "Godot not found at: $godot" | Out-File $logFile -Encoding UTF8
    exit 1
}

"=== Godot Test Started ===" | Out-File $logFile -Encoding UTF8
"Godot: $godot" | Out-File $logFile -Append -Encoding UTF8
"Project: $project" | Out-File $logFile -Append -Encoding UTF8
"Time: $(Get-Date)" | Out-File $logFile -Append -Encoding UTF8

# Test 1: --help
"" | Out-File $logFile -Append -Encoding UTF8
"=== Test 1: --help ===" | Out-File $logFile -Append -Encoding UTF8
& $godot --help 2>&1 | Out-File $logFile -Append -Encoding UTF8

# Test 2: --headless --quit (project load check)
"" | Out-File $logFile -Append -Encoding UTF8
"=== Test 2: --headless --quit ===" | Out-File $logFile -Append -Encoding UTF8
& $godot --path $project --headless --quit 2>&1 | Out-File $logFile -Append -Encoding UTF8

"=== Test Complete ===" | Out-File $logFile -Append -Encoding UTF8
