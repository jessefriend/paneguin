[CmdletBinding()]
param(
    [string]$InputFile = ".\setup-gui.ps1",
    [string]$OutputFile = ".\dist\Paneguin.exe",
    [string]$ProductVersion = "1.0.0",
    [string]$Title = "Paneguin",
    [string]$Product = "Paneguin",
    [string]$Company = "Paneguin",
    [string]$Description = "Paneguin bootstraps a WSL desktop environment with XRDP and a Windows launcher.",
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
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -Confirm:$false | Out-Null
    if (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue) {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
    Install-Module ps2exe -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -Confirm:$false
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

$resolvedInputFile = Resolve-RepoPath -Path $InputFile
$resolvedOutputFile = Resolve-RepoPath -Path $OutputFile

Ensure-Ps2Exe
Ensure-PathExists -Path $resolvedOutputFile

$resolvedIconFile = $null
if (-not [string]::IsNullOrWhiteSpace($IconFile)) {
    $resolvedIconFile = Resolve-RepoPath -Path $IconFile
}

Write-Section "Building EXE"
$ps2exeParams = @{
    InputFile    = $resolvedInputFile
    OutputFile   = $resolvedOutputFile
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
Write-Host "Built: $resolvedOutputFile" -ForegroundColor Green
Write-Host "Next step: run .\package-release.ps1 to assemble a distributable release folder." -ForegroundColor Green

