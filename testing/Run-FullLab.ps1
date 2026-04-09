[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [string]$CheckpointName = "clean-wsl-base",

    [pscredential]$GuestCredential,

    [ValidateSet("quick", "full", "cartesian")]
    [string]$MatrixProfile = "full",

    [string]$MatrixFile = "",

    [string]$ResultsRoot = "",

    [int]$SessionTimeoutSeconds = 300,

    [string[]]$CartesianDistros = @("Ubuntu", "FedoraLinux-42", "openSUSE-Tumbleweed"),

    [ValidateSet("kde", "xfce", "mate", "lxqt")]
    [string[]]$CartesianDesktopEnvironments = @("xfce", "mate", "lxqt", "kde"),

    [ValidateSet("basic", "chrome", "xrdp-guard", "kde-fallback")]
    [string[]]$CartesianVariants = @("basic", "chrome", "xrdp-guard", "kde-fallback"),

    [ValidateSet("Production", "ProductionOnly", "Standard")]
    [string]$CheckpointType = "Production",

    [switch]$RefreshCheckpoint,

    [switch]$EnableNestedVirtualization,

    [switch]$StartVmAfterCheckpoint,

    [switch]$CheckpointOnly,

    [switch]$StopOnFailure,

    [switch]$SkipPackaging
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -ge 6) {
    Write-Host "PowerShell Direct requires Windows PowerShell 5.1. Re-launching under powershell.exe..." -ForegroundColor Yellow
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $MyInvocation.MyCommand.Path)
    $argList += "-VMName", $VMName
    $argList += "-CheckpointName", $CheckpointName
    $argList += "-MatrixProfile", $MatrixProfile
    $argList += "-SessionTimeoutSeconds", $SessionTimeoutSeconds
    $argList += "-CheckpointType", $CheckpointType
    if ($MatrixFile)       { $argList += "-MatrixFile", $MatrixFile }
    if ($ResultsRoot)      { $argList += "-ResultsRoot", $ResultsRoot }
    if ($MatrixProfile -eq "cartesian") {
        $argList += "-CartesianDistros", ($CartesianDistros -join ",")
        $argList += "-CartesianDesktopEnvironments", ($CartesianDesktopEnvironments -join ",")
        $argList += "-CartesianVariants", ($CartesianVariants -join ",")
    }
    if ($RefreshCheckpoint)          { $argList += "-RefreshCheckpoint" }
    if ($EnableNestedVirtualization) { $argList += "-EnableNestedVirtualization" }
    if ($StartVmAfterCheckpoint)     { $argList += "-StartVmAfterCheckpoint" }
    if ($CheckpointOnly)             { $argList += "-CheckpointOnly" }
    if ($StopOnFailure)              { $argList += "-StopOnFailure" }
    if ($SkipPackaging)              { $argList += "-SkipPackaging" }
    & powershell.exe @argList
    exit $LASTEXITCODE
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing expected ${Description}: $Path"
    }
}

$checkpointScript = Join-Path $PSScriptRoot "New-HyperVBaseCheckpoint.ps1"
$matrixScript = Join-Path $PSScriptRoot "Invoke-HyperVTestMatrix.ps1"

Assert-PathExists -Path $checkpointScript -Description "checkpoint helper"
Assert-PathExists -Path $matrixScript -Description "matrix runner"

if ($RefreshCheckpoint) {
    Write-Step "Refreshing Hyper-V checkpoint"
    $checkpointArgs = @{
        VMName         = $VMName
        CheckpointName = $CheckpointName
        CheckpointType = $CheckpointType
        ReplaceExisting = $true
    }

    if ($EnableNestedVirtualization) {
        $checkpointArgs.EnableNestedVirtualization = $true
    }

    if ($StartVmAfterCheckpoint) {
        $checkpointArgs.StartVmAfter = $true
    }

    & $checkpointScript @checkpointArgs
} else {
    $checkpoint = Get-VMSnapshot -VMName $VMName -Name $CheckpointName -ErrorAction SilentlyContinue
    if (-not $checkpoint) {
        throw "Checkpoint '$CheckpointName' does not exist for VM '$VMName'. Finish guest prep, then re-run with -RefreshCheckpoint to create it."
    }
}

if ($CheckpointOnly) {
    Write-Step "Done"
    Write-Host "Checkpoint is ready. Re-run without -CheckpointOnly to execute the matrix." -ForegroundColor Green
    return
}

if (-not $GuestCredential) {
    Write-Step "Guest credential required"
    $GuestCredential = Get-Credential -Message "Enter the local admin credential for the guest VM."
}

Write-Step "Running Hyper-V test matrix"
$matrixArgs = @{
    VMName                = $VMName
    CheckpointName        = $CheckpointName
    GuestCredential       = $GuestCredential
    MatrixProfile         = $MatrixProfile
    SessionTimeoutSeconds = $SessionTimeoutSeconds
}

if ($MatrixFile) {
    $matrixArgs.MatrixFile = $MatrixFile
}

if ($ResultsRoot) {
    $matrixArgs.ResultsRoot = $ResultsRoot
}

if ($MatrixProfile -eq "cartesian") {
    $matrixArgs.CartesianDistros = $CartesianDistros
    $matrixArgs.CartesianDesktopEnvironments = $CartesianDesktopEnvironments
    $matrixArgs.CartesianVariants = $CartesianVariants
}

if ($StopOnFailure) {
    $matrixArgs.StopOnFailure = $true
}

if ($SkipPackaging) {
    $matrixArgs.SkipPackaging = $true
}

& $matrixScript @matrixArgs
