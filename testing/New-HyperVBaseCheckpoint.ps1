[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [string]$CheckpointName = "clean-wsl-base",

    [ValidateSet("Production", "ProductionOnly", "Standard")]
    [string]$CheckpointType = "Production",

    [switch]$EnableNestedVirtualization,

    [switch]$ReplaceExisting,

    [switch]$StartVmAfter
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Wait-VMState {
    param(
        [string]$VMName,
        [string]$DesiredState,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $vm = Get-VM -Name $VMName -ErrorAction Stop
        if ($vm.State.ToString() -eq $DesiredState) {
            return
        }

        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for VM '$VMName' to reach state '$DesiredState'."
}

function Stop-VMForCheckpoint {
    param([string]$VMName)

    $vm = Get-VM -Name $VMName -ErrorAction Stop
    if ($vm.State -eq "Off") {
        return
    }

    Write-Host "Stopping VM '$VMName' so the checkpoint starts from a clean powered-off state..."
    Stop-VM -Name $VMName -Force -Confirm:$false | Out-Null
    Wait-VMState -VMName $VMName -DesiredState "Off"
}

Write-Step "Inspecting VM"
$vm = Get-VM -Name $VMName -ErrorAction Stop
Write-Host ("Current state: {0}" -f $vm.State)

if ($EnableNestedVirtualization) {
    Write-Step "Enabling nested virtualization"
    Stop-VMForCheckpoint -VMName $VMName
    Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
    Write-Host "ExposeVirtualizationExtensions enabled for $VMName"
}

Write-Step "Configuring checkpoint behavior"
Set-VM -Name $VMName -CheckpointType $CheckpointType
Write-Host "Checkpoint type set to $CheckpointType"

Write-Step "Preparing clean checkpoint state"
Stop-VMForCheckpoint -VMName $VMName

if (-not $ReplaceExisting) {
    $existing = Get-VMSnapshot -VMName $VMName -Name $CheckpointName -ErrorAction SilentlyContinue
    if ($existing) {
        throw "A checkpoint named '$CheckpointName' already exists for VM '$VMName'. Re-run with -ReplaceExisting if you want to overwrite that baseline."
    }
}

if ($ReplaceExisting) {
    $existing = Get-VMSnapshot -VMName $VMName -Name $CheckpointName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Step "Removing existing checkpoint"
        Remove-VMSnapshot -VMSnapshot $existing -IncludeAllChildSnapshots -Confirm:$false
    }
}

Write-Step "Creating checkpoint"
$snapshot = Checkpoint-VM -Name $VMName -SnapshotName $CheckpointName -Passthru
Write-Host ("Created checkpoint '{0}' for VM '{1}'." -f $snapshot.Name, $VMName) -ForegroundColor Green

if ($StartVmAfter) {
    Write-Step "Restarting VM"
    Start-VM -Name $VMName | Out-Null
    Write-Host "VM restarted."
}

Write-Step "Next steps"
Write-Host "You can now run the matrix harness against this checkpoint:"
Write-Host ""
Write-Host ('$cred = Get-Credential')
Write-Host ('.\testing\Invoke-HyperVTestMatrix.ps1 -VMName "{0}" -CheckpointName "{1}" -GuestCredential $cred -MatrixProfile full' -f $VMName, $CheckpointName)
