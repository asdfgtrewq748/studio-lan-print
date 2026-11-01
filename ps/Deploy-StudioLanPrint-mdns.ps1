# Deploy-StudioLanPrint-mdns.ps1
# Run on the Windows host (elevated recommended).
# Stages from this folder -> ProgramData, ensures config.json, firewall, restart service.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$src = Join-Path $here 'StudioLanPrint.ps1'
$configLib = Join-Path $here 'StudioLanPrint.Config.ps1'
$example = Join-Path $here 'config.example.json'
foreach ($need in @($src, $configLib, $example)) {
    if (-not (Test-Path -LiteralPath $need)) { throw "missing $need" }
}

$stage = Join-Path $env:USERPROFILE 'Documents\studio-lan-print'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($name in @('StudioLanPrint.ps1', 'StudioLanPrint.Config.ps1', 'config.example.json', 'Install-StudioLanPrint.ps1')) {
    $from = Join-Path $here $name
    if (Test-Path -LiteralPath $from) {
        Copy-Item -LiteralPath $from -Destination (Join-Path $stage $name) -Force
    }
}

$destDir = Join-Path $env:ProgramData 'StudioLanPrint'
New-Item -ItemType Directory -Force -Path $destDir, (Join-Path $destDir 'logs'), (Join-Path $destDir 'jobs') | Out-Null
$dest = Join-Path $destDir 'StudioLanPrint.ps1'

# Stop existing service powershell hosting StudioLanPrint.ps1
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ForEach-Object {
    $cmd = $_.CommandLine
    if ($cmd -and ($cmd -like '*StudioLanPrint.ps1*')) {
        Write-Host "stopping pid $($_.ProcessId)"
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 1

foreach ($name in @('StudioLanPrint.ps1', 'StudioLanPrint.Config.ps1', 'config.example.json')) {
    Copy-Item -LiteralPath (Join-Path $here $name) -Destination (Join-Path $destDir $name) -Force
}
Write-Host "deployed $dest"

. $configLib
$init = Initialize-StudioLanPrintConfig -ExamplePath $example
if ($init.Created) { Write-Host "starter config: $($init.Path)" }
else { Write-Host "config kept: $($init.Path)" }
$settings = Get-StudioLanPrintSettings
$fileSettings = Get-StudioLanPrintSettings -Environment @{}
$overrideNote = Get-StudioLanPrintOverrideNote -Effective $settings -FromFile $fileSettings
if ($overrideNote) { Write-Warning $overrideNote }
$ports = @(Get-StudioLanPrintListenPorts -Effective $settings -FromFile $fileSettings)
$portSpec = $ports -join ','

# Firewall + URL ACL if admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    foreach ($p in $ports) {
        $aclUrl = "http://+:$p/"
        $acl = & netsh http show urlacl url=$aclUrl 2>&1 | Out-String
        if ($acl -notmatch ('http://\+:{0}/' -f $p)) {
            & netsh http add urlacl url=$aclUrl user=Everyone | Out-Null
            Write-Host "URL ACL added: $aclUrl"
        }
    }
    foreach ($rule in @(
        @{ Name = 'StudioLanPrint IPP'; Proto = 'TCP'; Port = $portSpec },
        @{ Name = 'StudioLanPrint mDNS'; Proto = 'UDP'; Port = 5353 }
    )) {
        & netsh advfirewall firewall delete rule name="$($rule.Name)" 2>$null | Out-Null
        & netsh advfirewall firewall add rule name="$($rule.Name)" dir=in action=allow protocol=$($rule.Proto) localport=$($rule.Port) profile=any | Out-Null
        Write-Host "firewall $($rule.Name) $($rule.Port)"
    }
}

# Startup lnk
$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'StudioLanPrint.lnk'
$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut($lnkPath)
$lnk.TargetPath = 'powershell.exe'
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dest`""
$lnk.WorkingDirectory = $destDir
$lnk.WindowStyle = 7
$lnk.Description = 'Studio LAN Print IPP + mDNS'
$lnk.Save()

Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $dest) -WindowStyle Hidden
Start-Sleep -Seconds 3
$healthUrl = "http://127.0.0.1:$($settings.Port)/health"
try {
    $h = (Invoke-WebRequest $healthUrl -UseBasicParsing -TimeoutSec 5).Content
    Write-Host "health: $h"
} catch {
    Write-Warning "health check failed: $($_.Exception.Message)"
}
Write-Host 'tail log:'
Get-Content (Join-Path $destDir 'logs\service.log') -Tail 30 -ErrorAction SilentlyContinue
Write-Host "Config: $($fileSettings.ConfigPath)"
Write-Host "Logon IPP port $($fileSettings.Port), mDNS $($fileSettings.ServiceInstance)._ipp._tcp.local"
Write-Host 'Change printer: set printerName in config.json (Get-Printer shows queue names), then run this deploy again.'
