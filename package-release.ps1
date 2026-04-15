[CmdletBinding()]
param(
    [string]$ExePath = ".\dist\Paneguin.exe",
    [string]$ReleaseDir = ".\dist\release",
    [switch]$ZipRelease
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Resolve-RepoPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $repoRoot $Path
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

$resolvedExePath = Resolve-RepoPath -Path $ExePath
$resolvedReleaseDir = Resolve-RepoPath -Path $ReleaseDir

if (-not (Test-Path $resolvedExePath)) {
    throw "EXE not found: $resolvedExePath. Run .\build-exe.ps1 first."
}

if (Test-Path $resolvedReleaseDir) {
    Remove-Item $resolvedReleaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedReleaseDir -Force | Out-Null

Write-Section "Preparing single-folder release"

Copy-Item $resolvedExePath (Join-Path $resolvedReleaseDir (Split-Path $resolvedExePath -Leaf)) -Force
foreach ($file in @("setup.ps1","setup-gui.ps1","README.md")) {
    $path = Join-Path $repoRoot $file
    if (Test-Path $path) {
        Copy-Item $path $resolvedReleaseDir -Force
    }
}

$assetsSource = Join-Path $repoRoot "assets"
if (Test-Path $assetsSource) {
    Copy-Item $assetsSource (Join-Path $resolvedReleaseDir "assets") -Recurse -Force
}

foreach ($dirName in @("wsl","windows")) {
    $source = Join-Path $repoRoot $dirName
    if (Test-Path $source) {
        Copy-Item $source (Join-Path $resolvedReleaseDir $dirName) -Recurse -Force
    }
}

$runBat = @"
@echo off
start "" "%~dp0Paneguin.exe"
"@
Set-Content -Path (Join-Path $resolvedReleaseDir "Run-Paneguin.bat") -Value $runBat -Encoding ASCII

Write-Host "Release folder ready: $resolvedReleaseDir" -ForegroundColor Green

if ($ZipRelease) {
    $zipPath = "$resolvedReleaseDir.zip"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $resolvedReleaseDir '*') -DestinationPath $zipPath
    Write-Host "Release zip ready: $zipPath" -ForegroundColor Green
}

