[CmdletBinding()]
param(
    [string]$InputFile = ".\setup-gui.ps1",
    [string]$OutputFile = ".\dist\WSL-Desktop-Bootstrap.exe",
    [string]$ProductVersion = "1.0.0",
    [string]$Title = "WSL Desktop Bootstrap",
    [string]$Product = "WSL Desktop Bootstrap",
    [string]$Company = "WSL Desktop Bootstrap",
    [string]$Description = "Bootstrap a WSL desktop environment with XRDP and a Windows launcher.",
    [string]$IconFile = ".\assets\paneguin.ico",
    [switch]$InstallPs2ExeIfMissing,
    [switch]$NoConsole
)

$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Ensure-Ps2Exe {
    $cmd = Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue
    if ($cmd) { return }

    if (-not $InstallPs2ExeIfMissing) {
        throw "Invoke-PS2EXE not found. Re-run with -InstallPs2ExeIfMissing, or install it manually with: Install-Module ps2exe -Scope CurrentUser"
    }

    Write-Section "Installing ps2exe"
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
    Import-Module ps2exe -Force

    $cmd = Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "ps2exe installation did not expose Invoke-PS2EXE."
    }
}

function Ensure-PathExists {
    param([string]$Path)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

Ensure-Ps2Exe
Ensure-PathExists -Path $OutputFile

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedIconFile = $null
if (-not [string]::IsNullOrWhiteSpace($IconFile)) {
    if ([System.IO.Path]::IsPathRooted($IconFile)) {
        $resolvedIconFile = $IconFile
    } else {
        $resolvedIconFile = Join-Path $repoRoot $IconFile
    }
}

Write-Section "Building EXE"
$ps2exeParams = @{
    InputFile    = $InputFile
    OutputFile   = $OutputFile
    Title        = $Title
    Product      = $Product
    Company      = $Company
    Copyright    = ""
    Description  = $Description
    Version      = $ProductVersion
    Verbose      = $true
}
if ($NoConsole) {
    $ps2exeParams["NoConsole"] = $true
}
if ($resolvedIconFile -and (Test-Path $resolvedIconFile)) {
    $ps2exeParams["IconFile"] = $resolvedIconFile
} elseif ($resolvedIconFile) {
    Write-Warning "Icon file not found: $resolvedIconFile. Building EXE without a custom icon."
}

Invoke-PS2EXE @ps2exeParams

Write-Host ""
Write-Host "Built: $OutputFile" -ForegroundColor Green
Write-Host "Next step: run .\package-release.ps1 to assemble a distributable release folder." -ForegroundColor Green
