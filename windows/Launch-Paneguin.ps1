Add-Type -AssemblyName PresentationFramework

$Distro   = "Ubuntu"
$Port     = 3390
$Username = ""
$RdpPath  = Join-Path $env:TEMP "paneguin.rdp"

function Show-ErrorAndExit {
    param([string]$Message)
    [System.Windows.MessageBox]::Show($Message, "Paneguin")
    exit 1
}

function Run-Wsl {
    param([string]$Command)

    $output = & wsl.exe -d $Distro -- bash -lc $Command 2>&1
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        Output   = ($output | Out-String).Trim()
        ExitCode = $exitCode
    }
}

wsl.exe -d $Distro -- echo "Starting $Distro..." | Out-Null

$prepareXrdp = Run-Wsl "if [ -x /usr/local/sbin/paneguin-ensure-xrdp ]; then sudo -n /usr/local/sbin/paneguin-ensure-xrdp; else pgrep -x xrdp >/dev/null || sudo service xrdp start; fi"
if ($prepareXrdp.ExitCode -ne 0) {
    Show-ErrorAndExit "Failed to prepare xrdp inside WSL.`n`nIf you enabled host-only XRDP protection, this can happen when WSL networking is unusual and the Windows host IP could not be identified.`n`nOutput:`n$($prepareXrdp.Output)"
}

Start-Sleep -Seconds 2

$getIp = Run-Wsl "hostname -I"
if ($getIp.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($getIp.Output)) {
    Show-ErrorAndExit "Could not get WSL IP address.`n`nOutput:`n$($getIp.Output)"
}

$IpAddress = ($getIp.Output -split '\s+')[0].Trim()
if ([string]::IsNullOrWhiteSpace($IpAddress)) {
    Show-ErrorAndExit "WSL returned an empty IP address."
}

$rdp = @"
screen mode id:i:2
use multimon:i:1
session bpp:i:32
compression:i:1
keyboardhook:i:2
audiocapturemode:i:0
videoplaybackmode:i:1
connection type:i:7
networkautodetect:i:1
bandwidthautodetect:i:1
displayconnectionbar:i:1
enableworkspacereconnect:i:0
remoteappmousemoveinject:i:1
disable wallpaper:i:0
allow font smoothing:i:0
allow desktop composition:i:0
disable full window drag:i:1
disable menu anims:i:1
disable themes:i:0
disable cursor setting:i:0
bitmapcachepersistenable:i:1
full address:s:$IpAddress`:$Port
audiomode:i:0
redirectprinters:i:0
redirectlocation:i:0
redirectcomports:i:0
redirectsmartcards:i:0
redirectwebauthn:i:0
redirectclipboard:i:1
redirectposdevices:i:0
autoreconnection enabled:i:1
authentication level:i:2
prompt for credentials:i:0
negotiate security layer:i:1
remoteapplicationmode:i:0
alternate shell:s:
shell working directory:s:
gatewayhostname:s:
gatewayusagemethod:i:4
gatewaycredentialssource:i:4
gatewayprofileusagemethod:i:0
promptcredentialonce:i:0
gatewaybrokeringtype:i:0
use redirection server name:i:0
rdgiskdcproxy:i:0
kdcproxyname:s:
enablerdsaadauth:i:0
username:s:$Username
"@

Set-Content -Path $RdpPath -Value $rdp -Encoding ASCII
Start-Process "mstsc.exe" -ArgumentList "`"$RdpPath`""
