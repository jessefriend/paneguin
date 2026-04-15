[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu",
    [ValidateSet("kde", "xfce", "mate", "lxqt")]
    [string]$DesktopEnv = "xfce",
    [switch]$InstallXfceFallback,
    [switch]$ApplyRdpMinimizeFix,
    [switch]$ConfigureChromeIntegration,
    [switch]$RestrictXrdpToWindowsHost,
    [switch]$ReuseExistingDistro,
    [switch]$TestPackaging,
    [switch]$InstallPs2ExeIfMissing
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Resolve-RepoRoot {
    $candidate = Split-Path -Parent $PSCommandPath

    while ($candidate) {
        $setupScript = Join-Path $candidate "setup.ps1"
        $launcherInstaller = Join-Path $candidate "windows\Install-Paneguin-Launcher.ps1"
        if ((Test-Path -LiteralPath $setupScript) -and (Test-Path -LiteralPath $launcherInstaller)) {
            return $candidate
        }

        $parent = Split-Path -Parent $candidate
        if ($parent -eq $candidate) {
            break
        }
        $candidate = $parent
    }

    throw "Could not locate the repo root from $PSCommandPath"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing expected ${Description}: $Path"
    }

    Write-Host "OK: $Description" -ForegroundColor Green
}

function Invoke-WslCommand {
    param(
        [string]$Distro,
        [string]$Command
    )

    $output = & wsl.exe -d $Distro -- bash -lc $Command 2>&1
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        Output   = ($output | Out-String).Trim()
        ExitCode = $exitCode
    }
}

function Invoke-ElevatedSetup {
    param(
        [string]$RepoRoot,
        [string]$Distro,
        [string]$DesktopEnv,
        [bool]$InstallXfceFallback,
        [bool]$ApplyRdpMinimizeFix,
        [bool]$ConfigureChromeIntegration,
        [bool]$RestrictXrdpToWindowsHost
    )

    $setupScript = Join-Path $RepoRoot "setup.ps1"
    $xfceValue = if ($InstallXfceFallback) { "1" } else { "0" }
    $rdpFixValue = if ($ApplyRdpMinimizeFix) { "1" } else { "0" }
    $chromeValue = if ($ConfigureChromeIntegration) { "1" } else { "0" }
    $xrdpGuardValue = if ($RestrictXrdpToWindowsHost) { "1" } else { "0" }

    $command = @"
Set-ExecutionPolicy Bypass -Scope Process -Force
& '$setupScript' -Distro '$Distro' -DesktopEnv '$DesktopEnv' -InstallXfceFallback '$xfceValue' -ApplyRdpMinimizeFix '$rdpFixValue' -ConfigureChromeIntegration '$chromeValue' -RestrictXrdpToWindowsHost '$xrdpGuardValue'
exit `$LASTEXITCODE
"@

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process = Start-Process powershell.exe `
        -Verb RunAs `
        -ArgumentList @("-NoProfile", "-EncodedCommand", $encoded) `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        throw "setup.ps1 failed with exit code $($process.ExitCode)"
    }
}

function Invoke-Setup {
    param(
        [string]$RepoRoot,
        [string]$Distro,
        [string]$DesktopEnv,
        [bool]$InstallXfceFallback,
        [bool]$ApplyRdpMinimizeFix,
        [bool]$ConfigureChromeIntegration,
        [bool]$RestrictXrdpToWindowsHost
    )

    $setupScript = Join-Path $RepoRoot "setup.ps1"
    $xfceValue = if ($InstallXfceFallback) { "1" } else { "0" }
    $rdpFixValue = if ($ApplyRdpMinimizeFix) { "1" } else { "0" }
    $chromeValue = if ($ConfigureChromeIntegration) { "1" } else { "0" }
    $xrdpGuardValue = if ($RestrictXrdpToWindowsHost) { "1" } else { "0" }

    if (Test-IsAdministrator) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript `
            -Distro $Distro `
            -DesktopEnv $DesktopEnv `
            -InstallXfceFallback $xfceValue `
            -ApplyRdpMinimizeFix $rdpFixValue `
            -ConfigureChromeIntegration $chromeValue `
            -RestrictXrdpToWindowsHost $xrdpGuardValue

        if ($LASTEXITCODE -ne 0) {
            throw "setup.ps1 failed with exit code $LASTEXITCODE"
        }

        return
    }

    Invoke-ElevatedSetup -RepoRoot $RepoRoot -Distro $Distro -DesktopEnv $DesktopEnv -InstallXfceFallback:$InstallXfceFallback -ApplyRdpMinimizeFix:$ApplyRdpMinimizeFix -ConfigureChromeIntegration:$ConfigureChromeIntegration -RestrictXrdpToWindowsHost:$RestrictXrdpToWindowsHost
}

function Test-DistroAlreadyInstalled {
    param([string]$Distro)

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        return $false
    }

    try {
        $check = (& wsl.exe -d $Distro -- sh -c "echo 'installed'" 2>$null) | Out-String
        return $check.Trim() -eq "installed"
    } catch {
        return $false
    }
}

$repoRoot = Resolve-RepoRoot
$launcherInstaller = Join-Path $repoRoot "windows\Install-Paneguin-Launcher.ps1"
$launcherPs1 = Join-Path $env:USERPROFILE "Scripts\Launch-Paneguin.ps1"
$launcherBat = Join-Path $env:USERPROFILE "Scripts\Launch-Paneguin.bat"
$launcherShortcut = Join-Path $env:USERPROFILE "Desktop\Paneguin.lnk"

Write-Step "Preflight"
Assert-PathExists -Path (Join-Path $repoRoot "setup.ps1") -Description "machine-level installer"
Assert-PathExists -Path (Join-Path $repoRoot "setup-gui.ps1") -Description "GUI installer"
Assert-PathExists -Path (Join-Path $repoRoot "wsl\setup.sh") -Description "Linux-side installer"
Assert-PathExists -Path $launcherInstaller -Description "launcher installer"

if (Test-IsAdministrator) {
    Write-Warning "Running from an elevated session. setup.ps1 will be executed directly instead of triggering a second elevation prompt."
}

if (-not $ReuseExistingDistro -and (Test-DistroAlreadyInstalled -Distro $Distro)) {
    throw "WSL distro '$Distro' is already installed. Re-run with -ReuseExistingDistro if you intentionally want to test against an existing distro."
}

if ($TestPackaging) {
    Write-Step "Packaging"
    $buildCmd = "& '$(Join-Path $repoRoot "build-exe.ps1")' -NoConsole"
    if ($InstallPs2ExeIfMissing) { $buildCmd += " -InstallPs2ExeIfMissing" }    
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $buildCmd      
    if ($LASTEXITCODE -ne 0) {
        throw "build-exe.ps1 failed."
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '$(Join-Path $repoRoot "package-release.ps1")' -ZipRelease"
    if ($LASTEXITCODE -ne 0) {
        throw "package-release.ps1 failed."
    }

    Assert-PathExists -Path (Join-Path $repoRoot "dist\Paneguin.exe") -Description "built EXE"
    Assert-PathExists -Path (Join-Path $repoRoot "dist\release\Run-Paneguin.bat") -Description "release launcher batch file"
    Assert-PathExists -Path (Join-Path $repoRoot "dist\release.zip") -Description "release zip"
}

Write-Step "Machine-level setup"
Write-Host "If this is a brand-new distro install, expect a manual Linux first-run username/password step during setup." -ForegroundColor Yellow
Invoke-Setup -RepoRoot $repoRoot -Distro $Distro -DesktopEnv $DesktopEnv -InstallXfceFallback:$InstallXfceFallback -ApplyRdpMinimizeFix:$ApplyRdpMinimizeFix -ConfigureChromeIntegration:$ConfigureChromeIntegration -RestrictXrdpToWindowsHost:$RestrictXrdpToWindowsHost

Write-Step "Launcher install"
$launcherArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $launcherInstaller,
    "-Distro", $Distro,
    "-Port", "3390"
)
if ($TestPackaging) {
    if ($InstallPs2ExeIfMissing) {
        $launcherArgs += "-InstallPs2ExeIfMissing"
    }
} else {
    $launcherArgs += "-SkipExe"
}

& powershell.exe @launcherArgs
if ($LASTEXITCODE -ne 0) {
    throw "Install-Paneguin-Launcher.ps1 failed."
}

Assert-PathExists -Path $launcherPs1 -Description "per-user launcher PowerShell script"
Assert-PathExists -Path $launcherBat -Description "per-user launcher batch file"
Assert-PathExists -Path $launcherShortcut -Description "desktop shortcut"

Write-Step "WSL-side validation"
$checks = @(
    @{ Description = "xrdp package"; Command = "command -v xrdp >/dev/null" },
    @{ Description = "DBus session helper"; Command = "command -v dbus-run-session >/dev/null || command -v dbus-launch >/dev/null" },
    @{ Description = "xauth"; Command = "command -v xauth >/dev/null" },
    @{ Description = "session starter"; Command = "test -x ~/bin/wsl-session-start" },
    @{ Description = "xsession file"; Command = "test -x ~/.xsession" },
    @{ Description = "repair helper"; Command = "test -x ~/bin/paneguin-repair" },
    @{ Description = "XRDP helper"; Command = "test -x /usr/local/sbin/paneguin-ensure-xrdp" }
)

foreach ($check in $checks) {
    $result = Invoke-WslCommand -Distro $Distro -Command $check.Command
    if ($result.ExitCode -ne 0) {
        throw "WSL validation failed for $($check.Description). Output: $($result.Output)"
    }

    Write-Host "OK: $($check.Description)" -ForegroundColor Green
}

$desktopChecks = switch ($DesktopEnv) {
    "kde" {
        @(
            @{ Description = "KDE session command"; Command = "command -v startplasma-x11 >/dev/null" },
            @{ Description = "KDE shell"; Command = "command -v plasmashell >/dev/null" }
        )
    }
    "xfce" {
        @(
            @{ Description = "XFCE session command"; Command = "command -v startxfce4 >/dev/null" },
            @{ Description = "XFCE session manager"; Command = "command -v xfce4-session >/dev/null" }
        )
    }
    "mate" {
        @(
            @{ Description = "MATE session command"; Command = "command -v mate-session >/dev/null" },
            @{ Description = "MATE window manager"; Command = "command -v marco >/dev/null" },
            @{ Description = "MATE panel"; Command = "command -v mate-panel >/dev/null" }
        )
    }
    "lxqt" {
        @(
            @{ Description = "LXQt session command"; Command = "command -v startlxqt >/dev/null" },
            @{ Description = "LXQt window manager"; Command = "command -v openbox >/dev/null" },
            @{ Description = "LXQt panel"; Command = "command -v lxqt-panel >/dev/null" }
        )
    }
}

foreach ($check in $desktopChecks) {
    $result = Invoke-WslCommand -Distro $Distro -Command $check.Command
    if ($result.ExitCode -ne 0) {
        throw "WSL desktop validation failed for $($check.Description). Output: $($result.Output)"
    }

    Write-Host "OK: $($check.Description)" -ForegroundColor Green
}

if ($RestrictXrdpToWindowsHost) {
    $guardCheck = Invoke-WslCommand -Distro $Distro -Command "grep -q '^RESTRICT_XRDP_TO_WINDOWS_HOST=1$' /etc/paneguin.conf"
    if ($guardCheck.ExitCode -ne 0) {
        throw "XRDP host-only restriction was requested, but the Linux config file does not show it as enabled."
    }

    Write-Host "OK: XRDP host-only restriction enabled" -ForegroundColor Green
}

if ($ConfigureChromeIntegration) {
    $chromePresent = Invoke-WslCommand -Distro $Distro -Command "command -v google-chrome-stable >/dev/null"
    if ($chromePresent.ExitCode -eq 0) {
        $chromeChecks = @(
            @{ Description = "Chrome wrapper"; Command = "test -x ~/bin/google-chrome-wsl" },
            @{ Description = "Chrome desktop file"; Command = "test -x ~/.local/share/applications/google-chrome-wsl.desktop" }
        )

        foreach ($check in $chromeChecks) {
            $result = Invoke-WslCommand -Distro $Distro -Command $check.Command
            if ($result.ExitCode -ne 0) {
                throw "Chrome integration validation failed for $($check.Description). Output: $($result.Output)"
            }

            Write-Host "OK: $($check.Description)" -ForegroundColor Green
        }
    } else {
        Write-Warning "Chrome integration was requested, but google-chrome-stable is not installed in WSL. The installer should have skipped that integration cleanly."
    }
}

Write-Step "Manual follow-up"
Write-Host "Smoke test passed for the CLI path." -ForegroundColor Green
Write-Host "Manual checks still recommended:" -ForegroundColor Yellow
Write-Host "  1. Run .\setup-gui.ps1 from a normal user session and verify launcher auto-install behavior."
Write-Host "  2. Run .\setup-gui.ps1 from an elevated session and verify the manual-launcher warning appears."
Write-Host "  3. Run the installed desktop shortcut and confirm the XRDP desktop actually opens."
