param(
    [string]$HostIp = '10.4.81.41',
    [int]$Port = 8631,
    [string]$Name = 'Studio-HP-LAN',
    [string]$PrinterUrl
)
$ErrorActionPreference = 'Continue'
if ([string]::IsNullOrWhiteSpace($PrinterUrl)) {
    $url = "http://${HostIp}:${Port}/ipp/print"
} else {
    $url = $PrinterUrl
}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ('admin=' + $admin)
Write-Host ("url=" + $url + " name=" + $Name)

# network discovery helpers (best effort, no fail)
try { Start-Service fdPHost -ErrorAction SilentlyContinue; Write-Host 'fdPHost started/ok' } catch { Write-Host ('fdPHost: ' + $_.Exception.Message) }
try { Start-Service FDResPub -ErrorAction SilentlyContinue; Write-Host 'FDResPub started/ok' } catch { Write-Host ('FDResPub: ' + $_.Exception.Message) }
try {
    Get-NetConnectionProfile | ForEach-Object {
        Write-Host ('profile ' + $_.Name + ' = ' + $_.NetworkCategory)
    }
} catch {}

Get-Printer -Name $Name -ErrorAction SilentlyContinue | ForEach-Object {
    try { Remove-Printer -Name $_.Name -Confirm:$false } catch {}
}

Write-Host 'trying Add-Printer -IppURL ...'
try {
    Add-Printer -Name $Name -IppURL $url -ErrorAction Stop
    Write-Host 'Add-Printer -IppURL SUCCEEDED'
} catch {
    Write-Host ('Add-Printer -IppURL FAILED: ' + $_.Exception.Message)
    Write-Host ('FullyQualifiedErrorId: ' + $_.FullyQualifiedErrorId)
    try {
        Add-Printer -Name $Name -DeviceURL $url -ErrorAction Stop
        Write-Host 'Add-Printer -DeviceURL SUCCEEDED'
    } catch {
        Write-Host ('Add-Printer -DeviceURL FAILED: ' + $_.Exception.Message)
    }
}

$p = Get-Printer -Name $Name -ErrorAction SilentlyContinue
if ($p) {
    $p | Format-List Name, DriverName, PortName, PrinterStatus
    Write-Host 'RESULT=OK'
    exit 0
} else {
    Write-Host 'RESULT=MISSING'
    exit 1
}
