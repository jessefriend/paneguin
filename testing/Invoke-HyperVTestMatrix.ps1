[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [Parameter(Mandatory = $true)]
    [string]$CheckpointName,

    [Parameter(Mandatory = $true)]
    [pscredential]$GuestCredential,

    [ValidateSet("quick", "full", "cartesian")]
    [string]$MatrixProfile = "quick",

    [string]$MatrixFile = "",

    [string]$ResultsRoot = "",

    [int]$SessionTimeoutSeconds = 300,

    [string[]]$CartesianDistros = @("Ubuntu", "FedoraLinux-42", "openSUSE-Tumbleweed"),

    [ValidateSet("kde", "xfce", "mate", "lxqt")]
    [string[]]$CartesianDesktopEnvironments = @("xfce", "mate", "lxqt", "kde"),

    [ValidateSet("basic", "chrome", "xrdp-guard", "kde-fallback")]
    [string[]]$CartesianVariants = @("basic", "chrome", "xrdp-guard", "kde-fallback"),

    [switch]$StopOnFailure,

    [switch]$SkipPackaging
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Resolve-RepoRoot {
    $candidate = Split-Path -Parent $PSScriptRoot

    while ($candidate) {
        $setupScript = Join-Path $candidate "setup.ps1"
        $launcherInstaller = Join-Path $candidate "windows\Install-WSL-Launcher.ps1"
        if ((Test-Path -LiteralPath $setupScript) -and (Test-Path -LiteralPath $launcherInstaller)) {
            return $candidate
        }

        $parent = Split-Path -Parent $candidate
        if ($parent -eq $candidate) {
            break
        }
        $candidate = $parent
    }

    throw "Could not locate the repo root from $PSScriptRoot"
}

function ConvertTo-CaseSlug {
    param([string]$Text)

    $lower = $Text.ToLowerInvariant()
    $normalized = $lower -replace "[^a-z0-9]+", "-"
    return $normalized.Trim("-")
}

function Get-CaseFlagSummary {
    param([object]$Case)

    $flags = @()
    if ($Case.InstallXfceFallback) { $flags += "xfce-fallback" }
    if ($Case.ApplyRdpMinimizeFix) { $flags += "rdp-minimize-fix" }
    if ($Case.ConfigureChromeIntegration) { $flags += "chrome" }
    if ($Case.RestrictXrdpToWindowsHost) { $flags += "xrdp-guard" }
    if ($Case.TestPackaging) { $flags += "packaging" }
    if ($Case.InstallPs2ExeIfMissing) { $flags += "ps2exe-auto-install" }
    if ($Case.ReuseExistingDistro) { $flags += "reuse-distro" }

    if ($flags.Count -eq 0) {
        return "none"
    }

    return ($flags -join ", ")
}

function Set-CaseBooleanProperty {
    param(
        [object]$Case,
        [string]$PropertyName,
        [bool]$Value
    )

    if ($Case.PSObject.Properties.Name -contains $PropertyName) {
        $Case.$PropertyName = $Value
    } else {
        $Case | Add-Member -NotePropertyName $PropertyName -NotePropertyValue $Value
    }
}

function New-CartesianMatrix {
    param(
        [string[]]$Distros,
        [string[]]$DesktopEnvironments,
        [string[]]$Variants,
        [bool]$SkipPackaging
    )

    $cases = @()
    $normalizedDistros = @($Distros | Where-Object { $_ } | Select-Object -Unique)
    $normalizedDesktops = @($DesktopEnvironments | Where-Object { $_ } | Select-Object -Unique)
    $normalizedVariants = @($Variants | Where-Object { $_ } | Select-Object -Unique)
    $packagingAssigned = $SkipPackaging

    if ($normalizedDistros.Count -eq 0) {
        throw "Cartesian matrix generation requires at least one distro."
    }

    if ($normalizedDesktops.Count -eq 0) {
        throw "Cartesian matrix generation requires at least one desktop environment."
    }

    if ($normalizedVariants.Count -eq 0) {
        throw "Cartesian matrix generation requires at least one variant."
    }

    foreach ($distro in $normalizedDistros) {
        foreach ($desktop in $normalizedDesktops) {
            foreach ($variant in $normalizedVariants) {
                if (($variant -eq "kde-fallback") -and ($desktop -ne "kde")) {
                    continue
                }

                $case = [ordered]@{
                    Name                = "{0}-{1}-{2}" -f (ConvertTo-CaseSlug -Text $distro), $desktop, (ConvertTo-CaseSlug -Text $variant)
                    Distro              = $distro
                    DesktopEnv          = $desktop
                    ApplyRdpMinimizeFix = $true
                    ReuseExistingDistro = $true
                }

                switch ($variant) {
                    "chrome" {
                        $case.ConfigureChromeIntegration = $true
                    }
                    "xrdp-guard" {
                        $case.RestrictXrdpToWindowsHost = $true
                    }
                    "kde-fallback" {
                        $case.InstallXfceFallback = $true
                    }
                }

                if (-not $packagingAssigned -and ($variant -eq "basic")) {
                    $case.TestPackaging = $true
                    $case.InstallPs2ExeIfMissing = $true
                    $packagingAssigned = $true
                }

                $cases += [pscustomobject]$case
            }
        }
    }

    if ((-not $SkipPackaging) -and (-not $packagingAssigned) -and ($cases.Count -gt 0)) {
        Set-CaseBooleanProperty -Case $cases[0] -PropertyName "TestPackaging" -Value $true
        Set-CaseBooleanProperty -Case $cases[0] -PropertyName "InstallPs2ExeIfMissing" -Value $true
    }

    return $cases
}

function Get-BuiltInMatrix {
    param(
        [string]$Profile,
        [bool]$SkipPackaging
    )

    $cases = @(
        [pscustomobject]@{
            Name                     = "ubuntu-xfce-basic"
            Distro                   = "Ubuntu"
            DesktopEnv               = "xfce"
            ApplyRdpMinimizeFix      = $true
            ReuseExistingDistro      = $true
            TestPackaging            = (-not $SkipPackaging)
            InstallPs2ExeIfMissing   = (-not $SkipPackaging)
        },
        [pscustomobject]@{
            Name                     = "ubuntu-kde-fallback"
            Distro                   = "Ubuntu"
            DesktopEnv               = "kde"
            InstallXfceFallback      = $true
            ApplyRdpMinimizeFix      = $true
            ReuseExistingDistro      = $true
        }
    )

    if ($Profile -eq "full") {
        $cases += @(
            [pscustomobject]@{
                Name                     = "ubuntu-mate-chrome"
                Distro                   = "Ubuntu"
                DesktopEnv               = "mate"
                ConfigureChromeIntegration = $true
                ApplyRdpMinimizeFix      = $true
                ReuseExistingDistro      = $true
            },
            [pscustomobject]@{
                Name                     = "ubuntu-xfce-xrdp-guard"
                Distro                   = "Ubuntu"
                DesktopEnv               = "xfce"
                ApplyRdpMinimizeFix      = $true
                RestrictXrdpToWindowsHost = $true
                ReuseExistingDistro      = $true
            },
            [pscustomobject]@{
                Name                     = "fedora-xfce"
                Distro                   = "FedoraLinux-42"
                DesktopEnv               = "xfce"
                ApplyRdpMinimizeFix      = $true
                ReuseExistingDistro      = $true
            },
            [pscustomobject]@{
                Name                     = "opensuse-lxqt-guard"
                Distro                   = "openSUSE-Tumbleweed"
                DesktopEnv               = "lxqt"
                ApplyRdpMinimizeFix      = $true
                RestrictXrdpToWindowsHost = $true
                ReuseExistingDistro      = $true
            }
        )
    }

    return $cases
}

function Import-Matrix {
    param(
        [string]$MatrixFile,
        [string]$Profile,
        [bool]$SkipPackaging,
        [string[]]$CartesianDistros,
        [string[]]$CartesianDesktopEnvironments,
        [string[]]$CartesianVariants
    )

    if ($MatrixFile) {
        if (-not (Test-Path -LiteralPath $MatrixFile)) {
            throw "Matrix file not found: $MatrixFile"
        }

        $raw = Get-Content -LiteralPath $MatrixFile -Raw
        $items = $raw | ConvertFrom-Json
        return @($items)
    }

    if ($Profile -eq "cartesian") {
        return @(New-CartesianMatrix -Distros $CartesianDistros -DesktopEnvironments $CartesianDesktopEnvironments -Variants $CartesianVariants -SkipPackaging:$SkipPackaging)
    }

    return @(Get-BuiltInMatrix -Profile $Profile -SkipPackaging:$SkipPackaging)
}

function New-StagingRepoCopy {
    param([string]$RepoRoot)

    $stagingParent = Join-Path ([System.IO.Path]::GetTempPath()) ("wsl-rdp-desktop-hyperv-" + [guid]::NewGuid().ToString("N"))
    $stagingRepo = Join-Path $stagingParent "wsl-rdp-desktop"
    New-Item -ItemType Directory -Path $stagingRepo -Force | Out-Null

    foreach ($item in @(".gitignore", "LICENSE", "README.md", "build-exe.ps1", "build-release.bat", "package-release.ps1", "setup.ps1", "setup-gui.ps1", "windows", "wsl", "testing")) {
        $source = Join-Path $RepoRoot $item
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $stagingRepo -Recurse -Force
        }
    }

    return $stagingParent
}

function Restore-TestVm {
    param(
        [string]$VMName,
        [string]$CheckpointName
    )

    $vm = Get-VM -Name $VMName -ErrorAction Stop
    if ($vm.State -ne "Off") {
        Stop-VM -Name $VMName -TurnOff -Force -Confirm:$false | Out-Null
    }

    $snapshot = Get-VMSnapshot -VMName $VMName -Name $CheckpointName -ErrorAction Stop
    Restore-VMSnapshot -VMSnapshot $snapshot -Confirm:$false | Out-Null
    Start-VM -Name $VMName | Out-Null
}

function Wait-GuestSession {
    param(
        [string]$VMName,
        [pscredential]$GuestCredential,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            return New-PSSession -VMName $VMName -Credential $GuestCredential -RunAsAdministrator -ErrorAction Stop
        } catch {
            Start-Sleep -Seconds 5
        }
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for PowerShell Direct connectivity to VM '$VMName'."
}

function Get-GuestRepoRoot {
    param([System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        Join-Path $env:USERPROFILE "Documents\wsl-rdp-desktop"
    }
}

function Copy-RepoToGuest {
    param(
        [System.Management.Automation.Runspaces.PSSession]$Session,
        [string]$HostStagingRepo,
        [string]$GuestRepoRoot
    )

    $guestParent = Split-Path -Parent $GuestRepoRoot
    Invoke-Command -Session $Session -ScriptBlock {
        param($GuestParent, $GuestRepoRoot)
        New-Item -ItemType Directory -Path $GuestParent -Force | Out-Null
        if (Test-Path -LiteralPath $GuestRepoRoot) {
            Remove-Item -LiteralPath $GuestRepoRoot -Recurse -Force
        }
    } -ArgumentList $guestParent, $GuestRepoRoot

    Copy-Item -Path $HostStagingRepo -Destination $guestParent -Recurse -Force -ToSession $Session
}

function Test-GuestDistros {
    param(
        [System.Management.Automation.Runspaces.PSSession]$Session,
        [object[]]$Cases
    )

    $requiredDistros = @(
        $Cases |
        Where-Object { $_.ReuseExistingDistro } |
        Select-Object -ExpandProperty Distro -Unique
    )

    if ($requiredDistros.Count -eq 0) {
        return
    }

    $installed = Invoke-Command -Session $Session -ScriptBlock {
        (& wsl.exe -l -q 2>$null) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    foreach ($distro in $requiredDistros) {
        if ($installed -notcontains $distro) {
            throw "Guest VM is missing required initialized distro '$distro'. The Hyper-V matrix runner currently assumes the base checkpoint already contains initialized distros for any case using -ReuseExistingDistro."
        }
    }
}

function Invoke-GuestSmokeTest {
    param(
        [System.Management.Automation.Runspaces.PSSession]$Session,
        [string]$GuestRepoRoot,
        [object]$Case
    )

    $caseJson = $Case | ConvertTo-Json -Depth 10 -Compress

    Invoke-Command -Session $Session -ScriptBlock {
        param($GuestRepoRoot, $CaseJson)

        $case = $CaseJson | ConvertFrom-Json
        $scriptPath = Join-Path $GuestRepoRoot "testing\smoke-test.ps1"
        $logDir = Join-Path $env:TEMP "wsl-rdp-desktop-tests"
        $logPath = Join-Path $logDir ("{0}.log" -f $case.Name)

        New-Item -ItemType Directory -Path $logDir -Force | Out-Null

        $argList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $scriptPath,
            "-Distro", $case.Distro,
            "-DesktopEnv", $case.DesktopEnv
        )

        if ($case.ReuseExistingDistro) { $argList += "-ReuseExistingDistro" }
        if ($case.InstallXfceFallback) { $argList += "-InstallXfceFallback" }
        if ($case.ApplyRdpMinimizeFix) { $argList += "-ApplyRdpMinimizeFix" }
        if ($case.ConfigureChromeIntegration) { $argList += "-ConfigureChromeIntegration" }
        if ($case.RestrictXrdpToWindowsHost) { $argList += "-RestrictXrdpToWindowsHost" }
        if ($case.TestPackaging) { $argList += "-TestPackaging" }
        if ($case.InstallPs2ExeIfMissing) { $argList += "-InstallPs2ExeIfMissing" }

        $output = & powershell.exe @argList 2>&1
        $exitCode = $LASTEXITCODE
        $text = ($output | Out-String)
        Set-Content -Path $logPath -Value $text -Encoding UTF8

        [pscustomobject]@{
            ExitCode       = $exitCode
            LogPath        = $logPath
            InstallLogPath = (Join-Path $env:PUBLIC "WSL-Desktop-Bootstrap\install.log")
            Output         = $text
        }
    } -ArgumentList $GuestRepoRoot, $caseJson
}

function Copy-GuestFileIfPresent {
    param(
        [System.Management.Automation.Runspaces.PSSession]$Session,
        [string]$GuestPath,
        [string]$DestinationPath
    )

    $exists = Invoke-Command -Session $Session -ScriptBlock {
        param($GuestPath)
        Test-Path -LiteralPath $GuestPath
    } -ArgumentList $GuestPath

    if ($exists) {
        Copy-Item -FromSession $Session -Path $GuestPath -Destination $DestinationPath -Force
    }
}

function Export-SummaryArtifacts {
    param(
        [object[]]$Summary,
        [string]$ResultsRoot,
        [string]$VMName,
        [string]$CheckpointName,
        [string]$MatrixProfile
    )

    $jsonPath = Join-Path $ResultsRoot "summary.json"
    $csvPath = Join-Path $ResultsRoot "summary.csv"
    $htmlPath = Join-Path $ResultsRoot "summary.html"

    $Summary | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8
    $Summary | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    $passedCount = @($Summary | Where-Object { $_.Status -eq "passed" }).Count
    $failedCount = @($Summary | Where-Object { $_.Status -eq "failed" }).Count
    $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
    $rows = foreach ($item in $Summary) {
        $statusClass = if ($item.Status -eq "passed") { "status-passed" } else { "status-failed" }
        @"
<tr class="$statusClass">
  <td>$([System.Net.WebUtility]::HtmlEncode($item.Name))</td>
  <td>$([System.Net.WebUtility]::HtmlEncode($item.Status))</td>
  <td>$([System.Net.WebUtility]::HtmlEncode($item.Distro))</td>
  <td>$([System.Net.WebUtility]::HtmlEncode($item.DesktopEnv))</td>
  <td>$([System.Net.WebUtility]::HtmlEncode($item.Flags))</td>
  <td>$([System.Net.WebUtility]::HtmlEncode($item.DurationSeconds.ToString()))</td>
  <td>$([System.Net.WebUtility]::HtmlEncode($item.Message))</td>
  <td>$([System.Net.WebUtility]::HtmlEncode($item.ArtifactsPath))</td>
</tr>
"@
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>WSL RDP Desktop Hyper-V Test Report</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1f2937; background: #f8fafc; }
    h1 { margin-bottom: 8px; }
    .meta { margin-bottom: 20px; color: #475569; }
    .cards { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 20px; }
    .card { background: #ffffff; border: 1px solid #dbe2ea; border-radius: 10px; padding: 12px 16px; min-width: 160px; }
    .card strong { display: block; font-size: 1.4rem; margin-top: 4px; }
    table { width: 100%; border-collapse: collapse; background: #ffffff; border: 1px solid #dbe2ea; }
    th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid #e5e7eb; vertical-align: top; }
    th { background: #e2e8f0; }
    .status-passed td:nth-child(2) { color: #166534; font-weight: 600; }
    .status-failed td:nth-child(2) { color: #991b1b; font-weight: 600; }
    code { background: #e2e8f0; padding: 2px 6px; border-radius: 6px; }
  </style>
</head>
<body>
  <h1>WSL RDP Desktop Hyper-V Test Report</h1>
  <p class="meta">Generated $generatedAt for VM <code>$([System.Net.WebUtility]::HtmlEncode($VMName))</code> from checkpoint <code>$([System.Net.WebUtility]::HtmlEncode($CheckpointName))</code> using profile <code>$([System.Net.WebUtility]::HtmlEncode($MatrixProfile))</code>.</p>
  <div class="cards">
    <div class="card">Cases<strong>$($Summary.Count)</strong></div>
    <div class="card">Passed<strong>$passedCount</strong></div>
    <div class="card">Failed<strong>$failedCount</strong></div>
  </div>
  <table>
    <thead>
      <tr>
        <th>Case</th>
        <th>Status</th>
        <th>Distro</th>
        <th>Desktop</th>
        <th>Flags</th>
        <th>Seconds</th>
        <th>Message</th>
        <th>Artifacts</th>
      </tr>
    </thead>
    <tbody>
$($rows -join "`r`n")
    </tbody>
  </table>
</body>
</html>
"@

    Set-Content -Path $htmlPath -Value $html -Encoding UTF8

    return [pscustomobject]@{
        JsonPath = $jsonPath
        CsvPath  = $csvPath
        HtmlPath = $htmlPath
    }
}

$repoRoot = Resolve-RepoRoot
if (-not $ResultsRoot) {
    $ResultsRoot = Join-Path $PSScriptRoot "artifacts"
}

$matrix = Import-Matrix `
    -MatrixFile $MatrixFile `
    -Profile $MatrixProfile `
    -SkipPackaging:$SkipPackaging `
    -CartesianDistros $CartesianDistros `
    -CartesianDesktopEnvironments $CartesianDesktopEnvironments `
    -CartesianVariants $CartesianVariants
if ($matrix.Count -eq 0) {
    throw "The test matrix is empty."
}

$stagingParent = $null
$session = $null
$summary = @()

try {
    Write-Step "Preparing staged repo copy"
    New-Item -ItemType Directory -Path $ResultsRoot -Force | Out-Null
    $stagingParent = New-StagingRepoCopy -RepoRoot $repoRoot
    $hostStagingRepo = Join-Path $stagingParent "wsl-rdp-desktop"

    foreach ($case in $matrix) {
        $caseStart = Get-Date
        $caseResultDir = Join-Path $ResultsRoot $case.Name
        New-Item -ItemType Directory -Path $caseResultDir -Force | Out-Null

        Write-Step ("Running case: {0}" -f $case.Name)
        $status = "passed"
        $message = ""

        try {
            Restore-TestVm -VMName $VMName -CheckpointName $CheckpointName
            $session = Wait-GuestSession -VMName $VMName -GuestCredential $GuestCredential -TimeoutSeconds $SessionTimeoutSeconds
            $guestRepoRoot = Get-GuestRepoRoot -Session $session
            Copy-RepoToGuest -Session $session -HostStagingRepo $hostStagingRepo -GuestRepoRoot $guestRepoRoot
            Test-GuestDistros -Session $session -Cases @($case)

            $guestResult = Invoke-GuestSmokeTest -Session $session -GuestRepoRoot $guestRepoRoot -Case $case
            $guestResult.Output | Set-Content -Path (Join-Path $caseResultDir "console-output.txt") -Encoding UTF8
            Copy-GuestFileIfPresent -Session $session -GuestPath $guestResult.LogPath -DestinationPath (Join-Path $caseResultDir "guest-smoke-test.log")
            Copy-GuestFileIfPresent -Session $session -GuestPath $guestResult.InstallLogPath -DestinationPath (Join-Path $caseResultDir "guest-install.log")

            if ($guestResult.ExitCode -ne 0) {
                throw "Guest smoke test failed with exit code $($guestResult.ExitCode)."
            }

            Write-Host "PASS: $($case.Name)" -ForegroundColor Green
        } catch {
            $status = "failed"
            $message = $_.Exception.Message
            Set-Content -Path (Join-Path $caseResultDir "host-error.txt") -Value $message -Encoding UTF8
            Write-Host "FAIL: $($case.Name) - $message" -ForegroundColor Red
            if ($StopOnFailure) {
                break
            }
        } finally {
            if ($session) {
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                $session = $null
            }

            $summary += [pscustomobject]@{
                Name            = $case.Name
                Status          = $status
                Distro          = $case.Distro
                DesktopEnv      = $case.DesktopEnv
                Flags           = Get-CaseFlagSummary -Case $case
                StartedAt       = $caseStart
                EndedAt         = Get-Date
                DurationSeconds = [math]::Round(((Get-Date) - $caseStart).TotalSeconds, 2)
                Message         = $message
                ArtifactsPath   = $caseResultDir
            }
        }
    }
} finally {
    if ($session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }

    if ($stagingParent -and (Test-Path -LiteralPath $stagingParent)) {
        Remove-Item -LiteralPath $stagingParent -Recurse -Force
    }
}

$summaryArtifacts = Export-SummaryArtifacts -Summary $summary -ResultsRoot $ResultsRoot -VMName $VMName -CheckpointName $CheckpointName -MatrixProfile $MatrixProfile

Write-Step "Done"
Write-Host "Saved test results to $ResultsRoot" -ForegroundColor Green
Write-Host "JSON summary: $($summaryArtifacts.JsonPath)"
Write-Host "CSV summary:  $($summaryArtifacts.CsvPath)"
Write-Host "HTML report:  $($summaryArtifacts.HtmlPath)"

if ($summary.Status -contains "failed") {
    throw "One or more Hyper-V matrix cases failed. Review the report files under $ResultsRoot."
}
