@echo off
REM Switch to project root so the PowerShell runner resolves paths correctly
cd /d "%~dp0\..\.."
powershell -ExecutionPolicy Bypass -File "scripts\tests\run_tests.ps1" %*
