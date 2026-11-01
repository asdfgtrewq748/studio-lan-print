# Add a LAN IPP printer. Run elevated.
# Studio reference defaults: http://10.4.81.41:8631/ipp/print named Studio-HP-LAN.
# Override with client/config.json, -HostIp / -Port / -PrinterUrl / -DisplayName,
# or STUDIO_LAN_HOST, STUDIO_LAN_PORT, STUDIO_LAN_PRINTER_URL, STUDIO_LAN_DISPLAY.
param(
    [Alias('Ip')]
    [string]$HostIp,
    [Alias('Url')]
    [string]$PrinterUrl,
    [Alias('Name')]
    [string]$DisplayName,
    [int]$Port = 0
)

$ErrorActionPreference = 'Stop'
$clientLib = Join-Path $PSScriptRoot 'StudioClient.Config.ps1'
if (-not (Test-Path -LiteralPath $clientLib)) { throw "missing $clientLib" }
. $clientLib

$target = Resolve-StudioClientTarget -Bound $PSBoundParameters -ConfigPath (Join-Path $PSScriptRoot 'config.json')
$url = $target.PrinterUrl
$health = $target.HealthUrl
$name = $target.DisplayName

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host 'relaunching elevated...'
    $urlArg = $target.PrinterUrl -replace '"', ''
    $nameArg = $target.DisplayName -replace '"', ''
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -PrinterUrl "' + $urlArg + '" -DisplayName "' + $nameArg + '"'
    $p = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $argLine -Wait -PassThru
    if (-not $p) {
        Write-Host 'elevation cancelled'
        exit 1
    }
    exit $p.ExitCode
}

Write-Host ("elevated; printer URL: " + $url)
Write-Host 'health:'
try {
    $h = (Invoke-WebRequest $health -UseBasicParsing -TimeoutSec 5).Content
    Write-Host $h
} catch {
    Write-Host ('Cannot reach IPP at ' + $health + ': ' + $_.Exception.Message)
    exit 1
}

# Best-effort cleanup of prior attempts (never fail the script here)
$ErrorActionPreference = 'Continue'
Get-Printer -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
    try { Remove-Printer -Name $_.Name -Confirm:$false } catch {}
}
$hostIp = $target.Host
$port = $target.Port
Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object {
    $n = [string]$_.Name
    ($n -eq "IP_$hostIp") -or ($n -like "*${hostIp}*${port}*") -or ($n -like "*${hostIp}*ipp/print*")
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
    Write-Host ("FAILED: " + $name + " was not created")
    exit 1
}
$prn | Format-List Name, DriverName, PortName, PrinterStatus, Shared
Write-Host ("OK: " + $name + " installed")
exit 0
