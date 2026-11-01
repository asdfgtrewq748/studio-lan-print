# Add Studio-HP-LAN via IPP URL. Run elevated.
$ErrorActionPreference = 'Stop'
$url = 'http://10.4.81.41:8631/ipp/print'
$health = 'http://10.4.81.41:8631/health'
$name = 'Studio-HP-LAN'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Write-Host 'relaunching elevated...'
  $p = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath) -Wait -PassThru
  exit $p.ExitCode
}

Write-Host 'elevated; health:'
try {
  $h = (Invoke-WebRequest $health -UseBasicParsing -TimeoutSec 5).Content
  Write-Host $h
} catch {
  Write-Host ('Cannot reach studio IPP: ' + $_.Exception.Message)
  exit 1
}

# Best-effort cleanup of prior attempts (never fail the script here)
$ErrorActionPreference = 'Continue'
Get-Printer -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
  try { Remove-Printer -Name $_.Name -Confirm:$false } catch {}
}
# Remove leftover IPP/WSD-ish ports if present (ignore failures)
Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object {
  $_.Name -eq 'IP_10.4.81.41_8631' -or $_.Name -like '*10.4.81.41*8631*' -or $_.Name -like '*ipp/print*'
} | ForEach-Object {
  try { Remove-PrinterPort -Name $_.Name -Confirm:$false } catch { Write-Host ('port cleanup skip: ' + $_.Name) }
}
$ErrorActionPreference = 'Stop'

# Prefer Microsoft IPP Class Driver path via -IppURL
$added = $false
try {
  Add-Printer -Name $name -IppURL $url -ErrorAction Stop
  $added = $true
  Write-Host 'Add-Printer -IppURL accepted'
} catch {
  Write-Host ('IppURL failed: ' + $_.Exception.Message)
  try {
    Add-Printer -Name $name -DeviceURL $url -ErrorAction Stop
    $added = $true
    Write-Host 'Add-Printer -DeviceURL accepted'
  } catch {
    Write-Host ('DeviceURL failed: ' + $_.Exception.Message)
  }
}

$prn = Get-Printer -Name $name -ErrorAction SilentlyContinue
if (-not $prn) {
  Write-Host 'FAILED: Studio-HP-LAN was not created'
  exit 1
}
$prn | Format-List Name, DriverName, PortName, PrinterStatus, Shared
Write-Host 'OK: Studio-HP-LAN installed'
exit 0
