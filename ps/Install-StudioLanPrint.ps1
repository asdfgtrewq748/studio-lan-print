# Install-StudioLanPrint.ps1
# Copy service script to ProgramData, URL ACL, firewall, Startup shortcut.
# Run elevated once.

$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'StudioLanPrint.ps1'
if (-not (Test-Path -LiteralPath $source)) {
    throw "source script missing: $source"
}

$baseDir = Join-Path $env:ProgramData 'StudioLanPrint'
$logsDir = Join-Path $baseDir 'logs'
$jobsDir = Join-Path $baseDir 'jobs'
foreach ($d in @($baseDir, $logsDir, $jobsDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

$target = Join-Path $baseDir 'StudioLanPrint.ps1'
Copy-Item -LiteralPath $source -Destination $target -Force
Write-Host "copied: $target" -ForegroundColor Green

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    try {
        $existing = & netsh http show urlacl url=http://+:8631/ 2>&1 | Out-String
        if ($existing -notmatch 'http://\+:8631/') {
            & netsh http add urlacl url=http://+:8631/ user=Everyone | Out-Null
            Write-Host 'URL ACL added: http://+:8631/ user=Everyone' -ForegroundColor Green
        } else {
            Write-Host 'URL ACL already present' -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "URL ACL failed: $($_.Exception.Message)"
    }

    foreach ($rule in @(
        @{ Name = 'StudioLanPrint IPP'; Proto = 'TCP'; Port = 8631 },
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
    Write-Warning 'not admin: skipped URL ACL and firewall. Elevate to add http://+:8631/ ACL and UDP 5353 / TCP 8631 inbound.'
}

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
Write-Host 'IPP: http://<LAN-IP>:8631/ipp/print'
Write-Host 'mDNS service: Studio-HP-LAN._ipp._tcp.local'

Write-Host 'PDF: place SumatraPDF.exe in this folder (preferred):' (Join-Path $baseDir 'SumatraPDF.exe')
Write-Host '     download: https://www.sumatrapdfreader.org/  (do not commit the exe to git)'
Write-Host 'Optional Acrobat fallback: set env STUDIO_LAN_ACROBAT to Acrobat.exe full path'

