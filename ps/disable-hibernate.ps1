$ErrorActionPreference = 'Stop'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("admin=" + $admin)
Write-Host 'before:'
Get-PSDrive C | Format-List Used,Free
if (Test-Path C:\hiberfil.sys) {
  $i = Get-Item C:\hiberfil.sys -Force
  Write-Host ("hiberfil sizeGB=" + [math]::Round($i.Length/1GB,2))
} else { Write-Host 'hiberfil missing' }
Write-Host 'running powercfg /hibernate off'
$out = & powercfg.exe /hibernate off 2>&1 | Out-String
Write-Host $out
Start-Sleep 2
Write-Host 'after:'
if (Test-Path C:\hiberfil.sys) {
  $i = Get-Item C:\hiberfil.sys -Force
  Write-Host ("hiberfil still there sizeGB=" + [math]::Round($i.Length/1GB,2))
} else { Write-Host 'hiberfil gone' }
Get-PSDrive C | Format-List Used,Free
# also confirm hibernate status
& powercfg.exe /a
