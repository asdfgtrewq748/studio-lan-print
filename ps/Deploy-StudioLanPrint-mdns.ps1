# Deploy-StudioLanPrint-mdns.ps1
# Run on the studio Windows host (elevated recommended).
# Stages from this folder -> ProgramData, firewall, restart service.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$src = Join-Path $here 'StudioLanPrint.ps1'
if (-not (Test-Path $src)) { throw "missing $src" }

$stage = Join-Path $env:USERPROFILE 'Documents\studio-lan-print'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item $src (Join-Path $stage 'StudioLanPrint.ps1') -Force
Copy-Item (Join-Path $here 'Install-StudioLanPrint.ps1') (Join-Path $stage 'Install-StudioLanPrint.ps1') -Force -ErrorAction SilentlyContinue

$destDir = Join-Path $env:ProgramData 'StudioLanPrint'
New-Item -ItemType Directory -Force -Path $destDir,(Join-Path $destDir 'logs'),(Join-Path $destDir 'jobs') | Out-Null
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

Copy-Item $src $dest -Force
Write-Host "deployed $dest"

# Firewall + URL ACL if admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
  $acl = & netsh http show urlacl url=http://+:8631/ 2>&1 | Out-String
  if ($acl -notmatch 'http://\+:8631/') {
    & netsh http add urlacl url=http://+:8631/ user=Everyone | Out-Null
  }
  foreach ($rule in @(
    @{ Name='StudioLanPrint IPP'; Proto='TCP'; Port=8631 },
    @{ Name='StudioLanPrint mDNS'; Proto='UDP'; Port=5353 }
  )) {
    & netsh advfirewall firewall delete rule name="$($rule.Name)" 2>$null | Out-Null
    & netsh advfirewall firewall add rule name="$($rule.Name)" dir=in action=allow protocol=$($rule.Proto) localport=$($rule.Port) profile=any | Out-Null
    Write-Host "firewall $($rule.Name)"
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

Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', $dest) -WindowStyle Hidden
Start-Sleep -Seconds 3
try {
  $h = (Invoke-WebRequest 'http://127.0.0.1:8631/health' -UseBasicParsing -TimeoutSec 5).Content
  Write-Host "health: $h"
} catch {
  Write-Warning "health check failed: $($_.Exception.Message)"
}
Write-Host 'tail log:'
Get-Content (Join-Path $destDir 'logs\service.log') -Tail 30 -ErrorAction SilentlyContinue
