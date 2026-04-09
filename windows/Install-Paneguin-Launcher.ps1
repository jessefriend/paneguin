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
$LauncherPs1 = Join-Path $ScriptsDir "Launch-Paneguin.ps1"
$LauncherBat = Join-Path $ScriptsDir "Launch-Paneguin.bat"
$ShortcutPath = Join-Path $DesktopDir "Paneguin.lnk"
$PowerShellExe = Join-Path $PSHOME "powershell.exe"
$ResolvedUsername = Resolve-LinuxUsername -Distro $Distro -Username $Username

New-Item -ItemType Directory -Path $ScriptsDir -Force | Out-Null

$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $sourceDir
$ps1Template = Join-Path $sourceDir "Launch-Paneguin.ps1"
$batTemplate = Join-Path $sourceDir "Launch-Paneguin.bat"
$iconSource = Join-Path $repoRoot "assets\paneguin.ico"

if (-not (Test-Path $ps1Template)) { throw "Missing launcher template: $ps1Template" }
if (-not (Test-Path $batTemplate)) { throw "Missing launcher template: $batTemplate" }
if (-not (Test-Path $iconSource)) { throw "Missing launcher icon: $iconSource" }

$iconHash = (Get-FileHash -Algorithm SHA256 -Path $iconSource).Hash.Substring(0, 12).ToLowerInvariant()
$LauncherIcon = Join-Path $ScriptsDir ("paneguin-{0}.ico" -f $iconHash)

Get-ChildItem -Path $ScriptsDir -Filter 'paneguin*.ico' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $LauncherIcon } |
    Remove-Item -Force -ErrorAction SilentlyContinue

$ps1Content = Get-Content $ps1Template -Raw
$ps1Content = $ps1Content -replace '\$Distro\s*=\s*".*?"', ('$Distro   = "{0}"' -f $Distro)
$ps1Content = $ps1Content -replace '\$Port\s*=\s*\d+', ('$Port     = {0}' -f $Port)
$ps1Content = $ps1Content -replace '\$Username\s*=\s*".*?"', ('$Username = "{0}"' -f $ResolvedUsername)

Set-Content -Path $LauncherPs1 -Value $ps1Content -Encoding UTF8
Copy-Item $batTemplate $LauncherBat -Force
Copy-Item $iconSource $LauncherIcon -Force
foreach ($path in @($LauncherPs1, $LauncherBat, $LauncherIcon)) {
    if (Test-Path $path) {
        Unblock-File -Path $path -ErrorAction SilentlyContinue
    }
}

$wsh = New-Object -ComObject WScript.Shell

if (Test-Path $ShortcutPath) {
    Remove-Item $ShortcutPath -Force
}

$shortcut = $wsh.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $PowerShellExe
$shortcut.WorkingDirectory = $ScriptsDir
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$LauncherPs1`""
$shortcut.IconLocation = "$LauncherIcon,0"
$shortcut.Save()
Write-Host "Created:"
Write-Host "  $LauncherPs1"
Write-Host "  $LauncherBat"
Write-Host "  $LauncherIcon"
Write-Host "  $ShortcutPath"
Write-Host ""
Write-Host "Launcher settings:"
Write-Host "  Distro: $Distro"
Write-Host "  Port: $Port"
Write-Host "  Username: $ResolvedUsername"
