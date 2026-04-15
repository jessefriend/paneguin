[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [string]$Distro = "Ubuntu",

    [pscredential]$GuestCredential,

    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -ge 6) {
    throw "PowerShell Direct (New-PSSession -VMName) is not supported in PowerShell $($PSVersionTable.PSVersion). Run this script from Windows PowerShell 5.1 (powershell.exe) instead of pwsh."
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Invoke-GuestWslText {
    param(
        [System.Management.Automation.Runspaces.PSSession]$Session,
        [string]$Distro,
        [string]$Command,
        [switch]$RunAsRoot
    )

    Invoke-Command -Session $Session -ScriptBlock {
        param($Distro, $Command, $RunAsRoot)

        if ($RunAsRoot) {
            $raw = & wsl.exe -u root -d $Distro -- bash -lc $Command 2>&1
        } else {
            $raw = & wsl.exe -d $Distro -- bash -lc $Command 2>&1
        }

        [pscustomobject]@{
            Output   = ((($raw | Out-String) -replace '\x00', '')).TrimEnd()
            ExitCode = $LASTEXITCODE
        }
    } -ArgumentList $Distro, $Command, [bool]$RunAsRoot
}

if (-not $GuestCredential) {
    Write-Step "Guest credential required"
    $GuestCredential = Get-Credential -Message "Enter the local admin credential for the guest VM."
}

if (-not $OutputPath) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $PSScriptRoot ("artifacts\{0}-{1}-wsl-diagnostics.txt" -f $VMName, $timestamp)
}

$outputDir = Split-Path -Parent $OutputPath
if ($outputDir) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Write-Step "Connecting to guest VM"
$session = New-PSSession -VMName $VMName -Credential $GuestCredential -ErrorAction Stop

try {
    Write-Step "Collecting WSL diagnostics"

    $linuxUserDetectCmd = @'
user_name="$(getent passwd 1000 2>/dev/null | cut -d: -f1)"
if [ -z "$user_name" ]; then
  user_name="$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" { print $1; exit }' /etc/passwd 2>/dev/null)"
fi
if [ -z "$user_name" ]; then
  user_name="$(id -un 2>/dev/null || true)"
fi
printf '%s\n' "$user_name"
'@
    $linuxUserResult = Invoke-GuestWslText -Session $session -Distro $Distro -RunAsRoot -Command $linuxUserDetectCmd
    $linuxUser = (($linuxUserResult.Output -split "`r?`n")[0]).Trim()
    if ([string]::IsNullOrWhiteSpace($linuxUser)) {
        $linuxUser = "unknown"
    }

    $linuxUserForBash = $linuxUser -replace "'", "'\\''"
    $homeDirResult = Invoke-GuestWslText -Session $session -Distro $Distro -RunAsRoot -Command ("getent passwd '$linuxUserForBash' | cut -d: -f6")
    $homeDir = $homeDirResult.Output.Trim()
    if ([string]::IsNullOrWhiteSpace($homeDir)) {
        $homeDir = "/home/$linuxUser"
    }

    $commandCheckCmd = @'
for c in 'xrdp' 'xauth' 'dbus-run-session' 'dbus-launch' 'startplasma-x11' 'plasmashell' 'startxfce4' 'xfce4-session' 'mate-session' 'marco' 'mate-panel' 'startlxqt' 'openbox' 'lxqt-panel'; do
  path="$(command -v "$c" 2>/dev/null || true)"
  if [ -n "$path" ]; then
    printf '%s -> %s\n' "$c" "$path"
  else
    printf '%s -> MISSING\n' "$c"
  fi
done
'@
    $homeDirForBash = $homeDir -replace "'", "'\\''"

    $commandChecks = Invoke-GuestWslText -Session $session -Distro $Distro -RunAsRoot -Command $commandCheckCmd
    $startwm = Invoke-GuestWslText -Session $session -Distro $Distro -RunAsRoot -Command 'if [ -f /etc/xrdp/startwm.sh ]; then sed -n "1,200p" /etc/xrdp/startwm.sh; else echo MISSING; fi'
    $xsession = Invoke-GuestWslText -Session $session -Distro $Distro -RunAsRoot -Command ("if [ -f '$homeDirForBash/.xsession' ]; then sed -n ""1,120p"" '$homeDirForBash/.xsession'; else echo MISSING; fi")
    $paneguinSession = Invoke-GuestWslText -Session $session -Distro $Distro -RunAsRoot -Command ("if [ -f '$homeDirForBash/.paneguin-session.log' ]; then tail -n 200 '$homeDirForBash/.paneguin-session.log'; else echo MISSING; fi")
    $xsessionErrors = Invoke-GuestWslText -Session $session -Distro $Distro -RunAsRoot -Command ("if [ -f '$homeDirForBash/.xsession-errors' ]; then tail -n 200 '$homeDirForBash/.xsession-errors'; else echo MISSING; fi")
    $xorgLogCmd = @"
latest=`$(ls -1t '$homeDirForBash'/.xorgxrdp.*.log 2>/dev/null | head -n 1)
if [ -n "`$latest" ]; then
  printf '%s\n' "`$latest"
  tail -n 200 "`$latest"
else
  echo MISSING
fi
"@
    $xorgLog = Invoke-GuestWslText -Session $session -Distro $Distro -RunAsRoot -Command $xorgLogCmd
    $xrdpLog = Invoke-GuestWslText -Session $session -Distro $Distro -RunAsRoot -Command 'if [ -f /var/log/xrdp.log ]; then tail -n 200 /var/log/xrdp.log; else echo MISSING; fi'
    $sesmanLog = Invoke-GuestWslText -Session $session -Distro $Distro -RunAsRoot -Command 'if [ -f /var/log/xrdp-sesman.log ]; then tail -n 200 /var/log/xrdp-sesman.log; else echo MISSING; fi'

    $reportLines = @(
        "=== VM ===",
        $VMName,
        "",
        "=== Distro ===",
        $Distro,
        "",
        "=== Linux User ===",
        $linuxUser,
        "",
        "=== Home ===",
        $homeDir,
        "",
        "=== Command Checks ===",
        $commandChecks.Output,
        "",
        "=== /etc/xrdp/startwm.sh ===",
        $startwm.Output,
        "",
        "=== ~/.xsession ===",
        $xsession.Output,
        "",
        "=== ~/.paneguin-session.log ===",
        $paneguinSession.Output,
        "",
        "=== ~/.xsession-errors ===",
        $xsessionErrors.Output,
        "",
        "=== ~/.xorgxrdp.*.log ===",
        $xorgLog.Output,
        "",
        "=== /var/log/xrdp.log ===",
        $xrdpLog.Output,
        "",
        "=== /var/log/xrdp-sesman.log ===",
        $sesmanLog.Output
    )

    Set-Content -Path $OutputPath -Value ($reportLines -join "`r`n") -Encoding UTF8
    Write-Host "Saved diagnostics to $OutputPath" -ForegroundColor Green
} finally {
    if ($session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }
}
