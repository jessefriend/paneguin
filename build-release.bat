@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0build-exe.ps1" -InstallPs2ExeIfMissing -NoConsole -ProductVersion 1.0.0
if errorlevel 1 exit /b %errorlevel%
powershell.exe -ExecutionPolicy Bypass -File "%~dp0package-release.ps1" -ZipRelease
