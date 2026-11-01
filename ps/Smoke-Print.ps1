param(
    [string]$Name = 'Studio-HP-LAN'
)
$ErrorActionPreference = 'Continue'
$tmp = Join-Path $env:TEMP 'studio-lan-smoke.txt'
Set-Content -LiteralPath $tmp -Value ('Studio LAN IPP smoke ' + (Get-Date).ToString('s')) -Encoding ASCII
try {
    Get-Content $tmp | Out-Printer -Name $Name
    Write-Host "smoke submitted via Out-Printer ($Name)"
} catch {
    Write-Host ('Out-Printer failed: ' + $_.Exception.Message)
}
Start-Sleep -Seconds 2
Get-PrintJob -PrinterName $Name -ErrorAction SilentlyContinue | Format-Table Id, DocumentName, JobStatus, Size -AutoSize
Get-Printer -Name $Name | Format-List Name, DriverName, PortName, PrinterStatus, JobCount
