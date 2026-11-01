# Install-StudioLanPrint.ps1
# Copy service script to ProgramData, write a starter config, URL ACL, firewall, Startup shortcut.
# Run elevated once. An existing config.json is left in place.

$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'StudioLanPrint.ps1'
$configLib = Join-Path $PSScriptRoot 'StudioLanPrint.Config.ps1'
$example = Join-Path $PSScriptRoot 'config.example.json'
foreach ($need in @($source, $configLib, $example)) {
    if (-not (Test-Path -LiteralPath $need)) { throw "source file missing: $need" }
}

$baseDir = Join-Path $env:ProgramData 'StudioLanPrint'
$logsDir = Join-Path $baseDir 'logs'
$jobsDir = Join-Path $baseDir 'jobs'
foreach ($d in @($baseDir, $logsDir, $jobsDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

foreach ($name in @('StudioLanPrint.ps1', 'StudioLanPrint.Config.ps1', 'config.example.json')) {
    $from = Join-Path $PSScriptRoot $name
    $to = Join-Path $baseDir $name
    Copy-Item -LiteralPath $from -Destination $to -Force
    Write-Host "copied: $to" -ForegroundColor Green
}

. $configLib
$init = Initialize-StudioLanPrintConfig -ExamplePath $example
if ($init.Created) { Write-Host "starter config: $($init.Path)" -ForegroundColor Green }
else { Write-Host "config kept: $($init.Path)" -ForegroundColor Yellow }

$settings = Get-StudioLanPrintSettings
$fileSettings = Get-StudioLanPrintSettings -Environment @{}
$overrideNote = Get-StudioLanPrintOverrideNote -Effective $settings -FromFile $fileSettings
if ($overrideNote) { Write-Warning $overrideNote }
$ports = @(Get-StudioLanPrintListenPorts -Effective $settings -FromFile $fileSettings)
$portSpec = $ports -join ','

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    foreach ($p in $ports) {
        $aclUrl = "http://+:$p/"
        try {
            $existing = & netsh http show urlacl url=$aclUrl 2>&1 | Out-String
            if ($existing -notmatch ('http://\+:{0}/' -f $p)) {
                & netsh http add urlacl url=$aclUrl user=Everyone | Out-Null
                Write-Host "URL ACL added: $aclUrl user=Everyone" -ForegroundColor Green
            } else {
                Write-Host "URL ACL already present: $aclUrl" -ForegroundColor Yellow
            }
        } catch {
            Write-Warning "URL ACL failed for ${aclUrl}: $($_.Exception.Message)"
        }
    }

    foreach ($rule in @(
        @{ Name = 'StudioLanPrint IPP'; Proto = 'TCP'; Port = $portSpec },
        @{ Name = 'StudioLanPrint mDNS'; Proto = 'UDP'; Port = 5353 }
    )) {
        try {
            & netsh advfirewall firewall delete rule name="$($rule.Name)" 2>$null | Out-Null
            & netsh advfirewall firewall add rule name="$($rule.Name)" dir=in action=allow protocol=$($rule.Proto) localport=$($rule.Port) profile=any | Out-Null
            Write-Host ("firewall set: {0} {1}/{2}" -f $rule.Name, $rule.Proto, $rule.Port) -ForegroundColor Green
        } catch {
            Write-Warning ("firewall rule {0} failed: {1}" -f $rule.Name, $_.Exception.Message)
        }
    }
} else {
    Write-Warning ("not admin: skipped URL ACL and firewall. Elevate to add http://+:$($fileSettings.Port)/ ACL and UDP 5353 / TCP $portSpec inbound.")
}

$target = Join-Path $baseDir 'StudioLanPrint.ps1'
$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'StudioLanPrint.lnk'
$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut($lnkPath)
$lnk.TargetPath = 'powershell.exe'
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target`""
$lnk.WorkingDirectory = $baseDir
$lnk.WindowStyle = 7
$lnk.Description = 'Studio LAN Print IPP + mDNS'
$lnk.Save()
Write-Host "startup shortcut: $lnkPath" -ForegroundColor Green

Write-Host ''
Write-Host 'install done.' -ForegroundColor Cyan
Write-Host "manual start: powershell -ExecutionPolicy Bypass -File `"$target`""
Write-Host "IPP: http://<LAN-IP>:$($fileSettings.Port)/ipp/print"
Write-Host "mDNS service: $($fileSettings.ServiceInstance)._ipp._tcp.local"
Write-Host "Config: $($fileSettings.ConfigPath)"
Write-Host 'To share a different printer, set printerName in that file to the exact queue from:'
Write-Host '  Get-Printer | Select-Object Name, PortName, DriverName'
Write-Host 'Leave printerName empty to prefer "HP LaserJet Professional P1108" when it is installed, otherwise the first suitable local printer.'
Write-Host 'Restart the service after editing the config. Re-run this installer after changing port (URL ACL and firewall).'
Write-Host 'Environment overrides: STUDIO_LAN_PRINTER, STUDIO_LAN_PORT, STUDIO_LAN_SERVICE, STUDIO_LAN_DISPLAY, STUDIO_LAN_FALLBACK_IP.'
Write-Host 'PDF: place SumatraPDF.exe in this folder (preferred):' (Join-Path $baseDir 'SumatraPDF.exe')
Write-Host '     download: https://www.sumatrapdfreader.org/  (do not commit the exe to git)'
Write-Host 'Optional Acrobat fallback: set env STUDIO_LAN_ACROBAT to Acrobat.exe full path'
