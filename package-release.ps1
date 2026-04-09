
[CmdletBinding()]
param(
    [string]$ExePath = ".\dist\WSL-Desktop-Bootstrap.exe",
    [string]$ReleaseDir = ".\dist\release",
    [switch]$ZipRelease
)

$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

if (-not (Test-Path $ExePath)) {
    throw "EXE not found: $ExePath. Run .\build-exe.ps1 first."
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path $ReleaseDir) {
    Remove-Item $ReleaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null

Write-Section "Preparing single-folder release"

Copy-Item $ExePath (Join-Path $ReleaseDir (Split-Path $ExePath -Leaf)) -Force
foreach ($file in @("setup.ps1","setup-gui.ps1","README.md")) {
    $path = Join-Path $repoRoot $file
    if (Test-Path $path) {
        Copy-Item $path $ReleaseDir -Force
    }
}

foreach ($dirName in @("wsl","windows")) {
    $source = Join-Path $repoRoot $dirName
    if (Test-Path $source) {
        Copy-Item $source (Join-Path $ReleaseDir $dirName) -Recurse -Force
    }
}

$runBat = @"
@echo off
start "" "%~dp0WSL-Desktop-Bootstrap.exe"
"@
Set-Content -Path (Join-Path $ReleaseDir "Run-WSL-Desktop-Bootstrap.bat") -Value $runBat -Encoding ASCII

Write-Host "Release folder ready: $ReleaseDir" -ForegroundColor Green

if ($ZipRelease) {
    $zipPath = "$ReleaseDir.zip"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $ReleaseDir '*') -DestinationPath $zipPath
    Write-Host "Release zip ready: $zipPath" -ForegroundColor Green
}
