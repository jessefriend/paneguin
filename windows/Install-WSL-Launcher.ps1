param(
    [string]$Distro = "Ubuntu",
    [int]$Port = 3390,
    [string]$Username = ""
)

function Resolve-LinuxUsername {
    param(
        [string]$Distro,
        [string]$Username
    )

    if (-not [string]::IsNullOrWhiteSpace($Username)) {
        return $Username
    }

    $result = & wsl.exe -d $Distro -- sh -lc "id -un" 2>$null
    $detectedUser = ($result | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($detectedUser)) {
        throw "Could not detect the Linux username for distro '$Distro'. Re-run with -Username."
    }

    return $detectedUser
}

$ScriptsDir = Join-Path $env:USERPROFILE "Scripts"
$DesktopDir = Join-Path $env:USERPROFILE "Desktop"
$LauncherPs1 = Join-Path $ScriptsDir "Launch-WSL-Desktop.ps1"
$LauncherBat = Join-Path $ScriptsDir "Launch-WSL-Desktop.bat"
$ShortcutPath = Join-Path $DesktopDir "WSL Desktop.lnk"
$ResolvedUsername = Resolve-LinuxUsername -Distro $Distro -Username $Username

New-Item -ItemType Directory -Path $ScriptsDir -Force | Out-Null

$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1Template = Join-Path $sourceDir "Launch-WSL-Desktop.ps1"
$batTemplate = Join-Path $sourceDir "Launch-WSL-Desktop.bat"

if (-not (Test-Path $ps1Template)) { throw "Missing launcher template: $ps1Template" }
if (-not (Test-Path $batTemplate)) { throw "Missing launcher template: $batTemplate" }

$ps1Content = Get-Content $ps1Template -Raw
$ps1Content = $ps1Content -replace '\$Distro\s*=\s*".*?"', ('$Distro   = "{0}"' -f $Distro)
$ps1Content = $ps1Content -replace '\$Port\s*=\s*\d+', ('$Port     = {0}' -f $Port)
$ps1Content = $ps1Content -replace '\$Username\s*=\s*".*?"', ('$Username = "{0}"' -f $ResolvedUsername)

Set-Content -Path $LauncherPs1 -Value $ps1Content -Encoding UTF8
Copy-Item $batTemplate $LauncherBat -Force

$wsh = New-Object -ComObject WScript.Shell

if (Test-Path $ShortcutPath) {
    Remove-Item $ShortcutPath -Force
}

$shortcut = $wsh.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $LauncherBat
$shortcut.WorkingDirectory = $ScriptsDir
$shortcut.IconLocation = "$env:SystemRoot\System32\netshell.dll,29"
$shortcut.Save()
Write-Host "Created:"
Write-Host "  $LauncherPs1"
Write-Host "  $LauncherBat"
Write-Host "  $ShortcutPath"
Write-Host ""
Write-Host "Launcher settings:"
Write-Host "  Distro: $Distro"
Write-Host "  Port: $Port"
Write-Host "  Username: $ResolvedUsername"
