
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SupportedDistroPattern = '^(Ubuntu|Ubuntu-\d+\.\d+|Debian|FedoraLinux-\d+|openSUSE-Tumbleweed|openSUSE-Leap-\d+\.\d+)$'
$FallbackDistros = @(
    "Ubuntu",
    "Debian",
    "FedoraLinux-42",
    "openSUSE-Tumbleweed",
    "openSUSE-Leap-15.6"
)
$GuiStartedElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

try {
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
} catch {
    $exePath = $null
}

if ($PSScriptRoot) {
    $scriptRoot = $PSScriptRoot
} elseif ($exePath) {
    $scriptRoot = Split-Path -Parent $exePath
} elseif ($MyInvocation.MyCommand.Path) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $scriptRoot = [System.AppDomain]::CurrentDomain.BaseDirectory
}
$originalUserProfile = $env:USERPROFILE
$originalDesktopPath = [Environment]::GetFolderPath("Desktop")
$originalScriptsPath = Join-Path $originalUserProfile "Scripts"


function Run-Installer {
    param(
        [string]$Distro,
        [string]$DesktopEnv,
        [bool]$InstallXfceFallback,
        [bool]$ApplyRdpMinimizeFix,
        [bool]$ConfigureChromeIntegration,
        [bool]$RestrictXrdpToWindowsHost
    )

    $xfceValue = if ($InstallXfceFallback) { "1" } else { "0" }
    $rdpFixValue = if ($ApplyRdpMinimizeFix) { "1" } else { "0" }
    $chromeValue = if ($ConfigureChromeIntegration) { "1" } else { "0" }
    $xrdpGuardValue = if ($RestrictXrdpToWindowsHost) { "1" } else { "0" }

    $setupScript = Join-Path $scriptRoot "setup.ps1"
    $wslSetup = Join-Path $scriptRoot "wsl\setup.sh"
    $launcherInstaller = Join-Path $scriptRoot "windows\Install-WSL-Launcher.ps1"
    $launcherTemplate = Join-Path $scriptRoot "windows\Launch-WSL-Desktop.ps1"

    $logDir = Join-Path $env:PUBLIC "WSL-Desktop-Bootstrap"
    $logPath = Join-Path $logDir "install.log"

    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $bootstrapInfo = @"
scriptRoot: $scriptRoot
setupScript: $setupScript
wslSetup: $wslSetup
launcherInstaller: $launcherInstaller
launcherTemplate: $launcherTemplate
userProfile: $env:USERPROFILE
originalUserProfile: $originalUserProfile
originalDesktopPath: $originalDesktopPath
originalScriptsPath: $originalScriptsPath
"@
    Set-Content -Path $logPath -Value $bootstrapInfo -Encoding UTF8

    foreach ($required in @($setupScript, $wslSetup, $launcherInstaller, $launcherTemplate)) {
        if (-not (Test-Path $required)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Missing required file:`n$required",
                "WSL Desktop Bootstrap",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            Start-Process notepad.exe $logPath | Out-Null
            return
        }
    }

    $cmd = @"
Set-ExecutionPolicy Bypass -Scope Process -Force
'Starting setup.ps1 from: $setupScript' | Tee-Object -FilePath '$logPath' -Append
& '$setupScript' -Distro '$Distro' -DesktopEnv '$DesktopEnv' -InstallXfceFallback '$xfceValue' -ApplyRdpMinimizeFix '$rdpFixValue' -ConfigureChromeIntegration '$chromeValue' -RestrictXrdpToWindowsHost '$xrdpGuardValue' *>&1 | Tee-Object -FilePath '$logPath' -Append
'INSTALL_EXIT_CODE=' + $LASTEXITCODE | Tee-Object -FilePath '$logPath' -Append
exit $LASTEXITCODE
"@

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))

    $proc = Start-Process powershell.exe `
        -Verb RunAs `
        -WindowStyle Normal `
        -ArgumentList @("-NoProfile", "-EncodedCommand", $encoded) `
        -PassThru `
        -Wait

    $exitCode = $proc.ExitCode

    $launcherInstallSkipped = $false
    if ($exitCode -eq 0 -and -not $GuiStartedElevated) {
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcherInstaller -Distro $Distro -Port 3390 *>> $logPath
        } catch {
            "LAUNCHER_INSTALL_ERROR=$($_.Exception.Message)" | Tee-Object -FilePath $logPath -Append | Out-Null
        }
    } elseif ($exitCode -eq 0 -and $GuiStartedElevated) {
        $launcherInstallSkipped = $true
        "LAUNCHER_INSTALL_SKIPPED=GUI started elevated; per-user launcher install must be run from a normal user session." | Tee-Object -FilePath $logPath -Append | Out-Null
    }

    $launcherPath = Join-Path $originalScriptsPath "Launch-WSL-Desktop.ps1"
    $shortcutPath = Join-Path $originalDesktopPath "WSL Desktop.lnk"
    $hasExpectedOutput = (Test-Path $launcherPath) -and (Test-Path $shortcutPath)
    $hasLog = Test-Path $logPath

    if ($exitCode -eq 0 -and $hasExpectedOutput) {
        [System.Windows.Forms.MessageBox]::Show(
            "Setup finished.`n`nLauncher and shortcut created.`n`nLog:`n$logPath",
            "WSL Desktop Bootstrap",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } elseif ($exitCode -eq 0 -and $launcherInstallSkipped) {
        $msg = "Machine-level setup finished.`n`nBecause this GUI was started from an elevated session, the per-user launcher was not installed automatically.`n`nOpen a normal PowerShell window and run:`n  powershell -ExecutionPolicy Bypass -File .\windows\Install-WSL-Launcher.ps1 -Distro $Distro`n`nLog:`n$logPath"
        [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "WSL Desktop Bootstrap",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } else {
        $msg = "Setup may not have completed successfully.`n`nExit code: $exitCode`nLauncher + shortcut found: $hasExpectedOutput`nLog exists: $hasLog`n`nLog:`n$logPath"
        [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "WSL Desktop Bootstrap",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        if ($hasLog) {
            Start-Process notepad.exe $logPath | Out-Null
        }
    }
}
function Get-InstalledDistros {
    try {
        $raw = & wsl.exe -l -q 2>$null
        return @(
            $raw |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -match $SupportedDistroPattern } |
            Select-Object -Unique
        )
    } catch {
        return @()
    }
}

function Get-OnlineDistros {
    try {
        $raw = & wsl.exe --list --online 2>$null
        $names = @()
        foreach ($line in $raw) {
            $trim = $line.Trim()
            if (-not $trim) { continue }
            if ($trim -match '^(NAME|The following distributions)') { continue }
            $name = ($trim -split '\s+')[0]
            if ($name -and $name -match $SupportedDistroPattern) {
                $names += $name
            }
        }
        if ($names.Count -gt 0) {
            return @($names | Select-Object -Unique)
        }
    } catch {
    }
    return $FallbackDistros
}

function Get-SupportedDistros {
    return @(((Get-InstalledDistros) + (Get-OnlineDistros)) | Select-Object -Unique)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "WSL Desktop Bootstrap"
$form.Size = New-Object System.Drawing.Size(520, 470)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$font = New-Object System.Drawing.Font("Segoe UI", 10)

$label1 = New-Object System.Windows.Forms.Label
$label1.Text = "Linux distro"
$label1.Location = New-Object System.Drawing.Point(25, 25)
$label1.Size = New-Object System.Drawing.Size(120, 24)
$label1.Font = $font
$form.Controls.Add($label1)

$distroBox = New-Object System.Windows.Forms.ComboBox
$distroBox.Location = New-Object System.Drawing.Point(25, 50)
$distroBox.Size = New-Object System.Drawing.Size(450, 28)
$distroBox.DropDownStyle = "DropDownList"
$distroBox.Font = $font
(Get-SupportedDistros) | ForEach-Object { [void]$distroBox.Items.Add($_) }
if ($distroBox.Items.Count -gt 0) { $distroBox.SelectedIndex = 0 }
$form.Controls.Add($distroBox)

$label2 = New-Object System.Windows.Forms.Label
$label2.Text = "Desktop environment"
$label2.Location = New-Object System.Drawing.Point(25, 95)
$label2.Size = New-Object System.Drawing.Size(180, 24)
$label2.Font = $font
$form.Controls.Add($label2)

$desktopBox = New-Object System.Windows.Forms.ComboBox
$desktopBox.Location = New-Object System.Drawing.Point(25, 120)
$desktopBox.Size = New-Object System.Drawing.Size(220, 28)
$desktopBox.DropDownStyle = "DropDownList"
$desktopBox.Font = $font
@("kde","xfce","mate","lxqt") | ForEach-Object { [void]$desktopBox.Items.Add($_) }
$desktopBox.SelectedIndex = 0
$form.Controls.Add($desktopBox)

$xfceFallback = New-Object System.Windows.Forms.CheckBox
$xfceFallback.Text = "Install XFCE fallback for KDE blue-screen recovery"
$xfceFallback.Location = New-Object System.Drawing.Point(25, 170)
$xfceFallback.Size = New-Object System.Drawing.Size(420, 28)
$xfceFallback.Checked = $true
$xfceFallback.Font = $font
$form.Controls.Add($xfceFallback)

$rdpFix = New-Object System.Windows.Forms.CheckBox
$rdpFix.Text = "Apply Windows RDP minimize fix"
$rdpFix.Location = New-Object System.Drawing.Point(25, 205)
$rdpFix.Size = New-Object System.Drawing.Size(320, 28)
$rdpFix.Checked = $true
$rdpFix.Font = $font
$form.Controls.Add($rdpFix)

$chromeIntegration = New-Object System.Windows.Forms.CheckBox
$chromeIntegration.Text = "Set up optional WSL Chrome integration if Chrome is installed"
$chromeIntegration.Location = New-Object System.Drawing.Point(25, 240)
$chromeIntegration.Size = New-Object System.Drawing.Size(440, 28)
$chromeIntegration.Checked = $false
$chromeIntegration.Font = $font
$form.Controls.Add($chromeIntegration)

$xrdpGuard = New-Object System.Windows.Forms.CheckBox
$xrdpGuard.Text = "Restrict XRDP to the Windows host only when possible"
$xrdpGuard.Location = New-Object System.Drawing.Point(25, 275)
$xrdpGuard.Size = New-Object System.Drawing.Size(440, 28)
$xrdpGuard.Checked = $false
$xrdpGuard.Font = $font
$form.Controls.Add($xrdpGuard)

$note = New-Object System.Windows.Forms.Label
$note.Text = "Run this GUI from your normal Windows user session. The XRDP host-only option is best with default WSL networking and may block launch on unusual mirrored or bridged setups."
$note.Location = New-Object System.Drawing.Point(25, 310)
$note.Size = New-Object System.Drawing.Size(450, 60)
$note.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($note)

$installBtn = New-Object System.Windows.Forms.Button
$installBtn.Text = "Install"
$installBtn.Location = New-Object System.Drawing.Point(285, 390)
$installBtn.Size = New-Object System.Drawing.Size(90, 30)
$installBtn.Font = $font
$form.Controls.Add($installBtn)

$cancelBtn = New-Object System.Windows.Forms.Button
$cancelBtn.Text = "Cancel"
$cancelBtn.Location = New-Object System.Drawing.Point(385, 390)
$cancelBtn.Size = New-Object System.Drawing.Size(90, 30)
$cancelBtn.Font = $font
$form.Controls.Add($cancelBtn)

$desktopBox.add_SelectedIndexChanged({
    $xfceFallback.Enabled = ($desktopBox.SelectedItem -eq "kde")
})

$installBtn.Add_Click({
    if (-not $distroBox.SelectedItem) {
        [System.Windows.Forms.MessageBox]::Show("Please choose a distro.")
        return
    }
    if (-not $desktopBox.SelectedItem) {
        [System.Windows.Forms.MessageBox]::Show("Please choose a desktop environment.")
        return
    }
    Run-Installer -Distro $distroBox.SelectedItem.ToString() `
                  -DesktopEnv $desktopBox.SelectedItem.ToString() `
                  -InstallXfceFallback $xfceFallback.Checked `
                  -ApplyRdpMinimizeFix $rdpFix.Checked `
                  -ConfigureChromeIntegration $chromeIntegration.Checked `
                  -RestrictXrdpToWindowsHost $xrdpGuard.Checked
    $form.Close()
})

$cancelBtn.Add_Click({ $form.Close() })

if ($GuiStartedElevated) {
    [System.Windows.Forms.MessageBox]::Show(
        "This GUI was started from an elevated session.`n`nMachine-level setup will still work, but the per-user launcher will need to be installed manually from a normal Windows user session afterwards.",
        "WSL Desktop Bootstrap",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

[void]$form.ShowDialog()
