[CmdletBinding()]
param(
    [string]$Distro = "",
    [string]$DesktopEnv = "",
    [string]$InstallXfceFallback = "",
    [string]$ApplyRdpMinimizeFix = "",
    [string]$ConfigureChromeIntegration = "",
    [string]$RestrictXrdpToWindowsHost = ""
)

$ErrorActionPreference = "Stop"

$SupportedDistroPattern = '^(Ubuntu|Ubuntu-\d+\.\d+|Debian|FedoraLinux-\d+|openSUSE-Tumbleweed|openSUSE-Leap-\d+\.\d+)$'
$FallbackDistros = @(
    "Ubuntu",
    "Debian",
    "FedoraLinux-42",
    "openSUSE-Tumbleweed",
    "openSUSE-Leap-15.6"
)

function Resolve-BoolParam {
    param(
        [object]$Value,
        [bool]$Default
    )
    if ($null -eq $Value) { return $Default }
    $s = "$Value".Trim()
    if ([string]::IsNullOrWhiteSpace($s)) { return $Default }
    switch -Regex ($s.ToLower()) {
        '^(1|true|yes|y)$' { return $true }
        '^(0|false|no|n)$' { return $false }
        default { return $Default }
    }
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Require-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script in an elevated PowerShell window (Run as Administrator)."
    }
}

function Ensure-WSL {
    Write-Section "Checking WSL"
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        Write-Host "WSL not found. Installing..." -ForegroundColor Yellow
        & wsl.exe --install --no-distribution
        throw "WSL was installed. Reboot Windows, then run setup.ps1 again."
    }
}

function Get-InstalledDistros {
    $raw = (& wsl.exe -l -q 2>$null) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return @($raw)
}

function Get-OnlineDistros {
    $raw = & wsl.exe --list --online 2>$null
    $names = @()

    foreach ($line in $raw) {
        $trim = $line.Trim()
        if (-not $trim) { continue }
        $name = ($trim -split '\s+')[0]
        if ($name -match $SupportedDistroPattern) {
            $names += $name
        }
    }

    return @(($names + $FallbackDistros) | Select-Object -Unique)
}

function Prompt-Choice {
    param(
        [string]$Title,
        [string[]]$Options
    )

    if (-not $Options -or $Options.Count -eq 0) {
        throw "No options available for $Title"
    }

    Write-Host ""
    Write-Host $Title -ForegroundColor Green
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $Options[$i])
    }

    while ($true) {
        $selection = Read-Host "Enter number"
        if ($selection -match '^\d+$') {
            $idx = [int]$selection - 1
            if ($idx -ge 0 -and $idx -lt $Options.Count) {
                return $Options[$idx]
            }
        }
        Write-Host "Invalid selection. Try again." -ForegroundColor Yellow
    }
}

function Prompt-YesNo {
    param(
        [string]$Question,
        [bool]$Default = $true
    )
    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $r = Read-Host "$Question $suffix"
        if ([string]::IsNullOrWhiteSpace($r)) { return $Default }
        switch -Regex ($r.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Host "Please answer y or n." -ForegroundColor Yellow }
        }
    }
}

function Prompt-Distro {
    $installed = Get-InstalledDistros
    $online = Get-OnlineDistros
    $combined = @()

    foreach ($d in $installed) {
        if ($d -match $SupportedDistroPattern) { $combined += $d }
    }
    foreach ($d in $online) {
        if ($d -match $SupportedDistroPattern) { $combined += $d }
    }

    $combined = $combined | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique

    if ($combined.Count -eq 0) {
        throw "Could not enumerate usable WSL distros."
    }

    return Prompt-Choice -Title "Choose a Linux distro" -Options $combined
}

function Prompt-DesktopEnvironment {
    $envs = @("kde", "xfce", "mate", "lxqt")
    return Prompt-Choice -Title "Choose a desktop environment" -Options $envs
}

function Ensure-DistroInstalled {
    param([string]$Distro)

    $installed = Get-InstalledDistros
    if ($installed -contains $Distro) {
        Write-Host "WSL distro already installed: $Distro" -ForegroundColor Green
        return
    }

    Write-Section "Installing WSL distro: $Distro"
    & wsl.exe --install -d $Distro
    Write-Host ""
    Write-Host "If this was the first launch of the distro, complete the Linux username/password setup in the WSL window." -ForegroundColor Yellow
    Read-Host "Press Enter here after the distro has finished first-run setup"
}

function Get-LinuxUsername {
    param([string]$Distro)

    $result = & wsl.exe -d $Distro -- sh -lc "id -un" 2>$null
    $user = ($result | Out-String).Trim()
    if (-not $user) {
        $user = Read-Host "Could not detect the Linux username automatically. Enter the Linux username for distro '$Distro'"
    }
    return $user
}

function Get-RepoRoot {
    Split-Path -Parent $PSCommandPath
}

function Enable-RdpMinimizeFix {
    Write-Section "Applying RDP minimize fix"
    $paths = @(
        "HKCU:\Software\Microsoft\Terminal Server Client",
        "HKCU:\Software\Wow6432Node\Microsoft\Terminal Server Client",
        "HKLM:\Software\Microsoft\Terminal Server Client",
        "HKLM:\Software\Wow6432Node\Microsoft\Terminal Server Client"
    )

    foreach ($path in $paths) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        New-ItemProperty -Path $path -Name "RemoteDesktop_SuppressWhenMinimized" -PropertyType DWord -Value 2 -Force | Out-Null
    }

    Write-Host "Applied RemoteDesktop_SuppressWhenMinimized=2. A Windows sign-out or reboot may be needed before it fully takes effect." -ForegroundColor Green
}

function Copy-FileToWsl {
    param(
        [string]$Distro,
        [string]$SourceWindowsPath,
        [string]$TargetLinuxPath
    )

    if (-not (Test-Path -LiteralPath $SourceWindowsPath)) {
        throw "Source file not found: $SourceWindowsPath"
    }

    $fullWindowsPath = (Resolve-Path -LiteralPath $SourceWindowsPath).Path
    $normalized = $fullWindowsPath -replace '\\','/'

    if ($normalized -notmatch '^([A-Za-z]):/(.+)$') {
        throw "Could not convert Windows path to WSL path: $fullWindowsPath"
    }

    $drive = $matches[1].ToLower()
    $rest  = $matches[2]
    $sourceWsl = "/mnt/$drive/$rest"

    $targetDir = $TargetLinuxPath -replace '/[^/]+$',''
    if ([string]::IsNullOrWhiteSpace($targetDir) -or $targetDir -eq $TargetLinuxPath) {
        throw "Could not determine target directory from: $TargetLinuxPath"
    }

    & wsl.exe -d $Distro -- bash -lc "mkdir -p '$targetDir'"
    & wsl.exe -d $Distro -- bash -lc "cp '$sourceWsl' '$TargetLinuxPath'"
}

function Install-LinuxSide {
    param(
        [string]$Distro,
        [string]$LinuxUser,
        [string]$DesktopEnv,
        [string]$RepoRoot,
        [object]$InstallXfceFallback,
        [object]$ConfigureChromeIntegration,
        [object]$RestrictXrdpToWindowsHost
    )

    $setupShWin = Join-Path $RepoRoot "wsl\setup.sh"
    if (-not (Test-Path $setupShWin)) {
        throw "Missing Linux setup script: $setupShWin"
    }

    $setupShLinux = "/tmp/paneguin-setup.sh"
    Copy-FileToWsl -Distro $Distro -SourceWindowsPath $setupShWin -TargetLinuxPath $setupShLinux

    $fallbackValue = if (Resolve-BoolParam -Value $InstallXfceFallback -Default $false) { "1" } else { "0" }
    $chromeValue = if (Resolve-BoolParam -Value $ConfigureChromeIntegration -Default $false) { "1" } else { "0" }
    $xrdpGuardValue = if (Resolve-BoolParam -Value $RestrictXrdpToWindowsHost -Default $false) { "1" } else { "0" }
    $bashCommand = "chmod +x $setupShLinux ; DESKTOP_ENV='$DesktopEnv' LINUX_USER='$LinuxUser' INSTALL_XFCE_FALLBACK='$fallbackValue' CONFIGURE_CHROME_INTEGRATION='$chromeValue' RESTRICT_XRDP_TO_WINDOWS_HOST='$xrdpGuardValue' sudo bash $setupShLinux"

    Write-Section "Running Linux-side installer"
    & wsl.exe -d $Distro -- bash -lc $bashCommand
}

try {
    Require-Admin
    Ensure-WSL

    $repoRoot = Get-RepoRoot
    $distro = if ($Distro) { $Distro } else { Prompt-Distro }
    Ensure-DistroInstalled -Distro $distro
    $linuxUser = Get-LinuxUsername -Distro $distro
    $desktopEnv = if ($DesktopEnv) { $DesktopEnv } else { Prompt-DesktopEnvironment }
    $installXfceFallback = Resolve-BoolParam -Value $InstallXfceFallback -Default $false
    $applyRdpMinimizeFix = Resolve-BoolParam -Value $ApplyRdpMinimizeFix -Default $true
    $configureChromeIntegration = Resolve-BoolParam -Value $ConfigureChromeIntegration -Default $false
    $restrictXrdpToWindowsHost = Resolve-BoolParam -Value $RestrictXrdpToWindowsHost -Default $false

    if ([string]::IsNullOrWhiteSpace($InstallXfceFallback) -and $desktopEnv -eq "kde") {
        $installXfceFallback = Prompt-YesNo -Question "Install XFCE as a fallback if Plasma blue-screens?" -Default $true
    }

    if ([string]::IsNullOrWhiteSpace($ApplyRdpMinimizeFix)) {
        $applyRdpMinimizeFix = Prompt-YesNo -Question "Apply the Windows RDP minimize fix (recommended)?" -Default $true
    }

    if ($applyRdpMinimizeFix) {
        Enable-RdpMinimizeFix
    }

    if ([string]::IsNullOrWhiteSpace($ConfigureChromeIntegration)) {
        $configureChromeIntegration = Prompt-YesNo -Question "Set up optional WSL Chrome integration for browsing and link handling if Chrome is installed?" -Default $false
    }

    if ([string]::IsNullOrWhiteSpace($RestrictXrdpToWindowsHost)) {
        $restrictXrdpToWindowsHost = Prompt-YesNo -Question "Restrict XRDP to the Windows host only when possible? Recommended on shared networks." -Default $false
    }

    Install-LinuxSide -Distro $distro -LinuxUser $linuxUser -DesktopEnv $desktopEnv -RepoRoot $repoRoot -InstallXfceFallback $installXfceFallback -ConfigureChromeIntegration $configureChromeIntegration -RestrictXrdpToWindowsHost $restrictXrdpToWindowsHost

    Write-Section "Done"
    Write-Host "Machine-level setup complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next, run the launcher installer in your normal user context:" -ForegroundColor Yellow
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\windows\Install-Paneguin-Launcher.ps1"
} catch {
    Write-Host ""
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

