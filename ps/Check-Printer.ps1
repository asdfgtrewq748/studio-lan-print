Write-Host '=== printers matching Studio/HP/LAN ==='
Get-Printer | Where-Object { $_.Name -match 'Studio|HP|LAN|P1108' } | Format-List Name, DriverName, PortName, PrinterStatus, Shared
Write-Host '=== specifically Studio-HP-LAN ==='
$p = Get-Printer -Name 'Studio-HP-LAN' -ErrorAction SilentlyContinue
if ($p) {
  $p | Format-List *
  Write-Host 'RESULT=OK'
} else {
  Write-Host 'RESULT=MISSING'
}
Write-Host '=== recent cmd/powershell with Studio in cmdline? ==='
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='cmd.exe'" | ForEach-Object {
  if ($_.CommandLine -and ($_.CommandLine -like '*Studio*' -or $_.CommandLine -like '*Add-Studio*' -or $_.CommandLine -like '*Connect-Studio*')) {
    Write-Host ("pid={0} {1}" -f $_.ProcessId, $_.CommandLine)
  }
}
