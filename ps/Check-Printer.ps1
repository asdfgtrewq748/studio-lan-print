param(
    [string]$Name = 'Studio-HP-LAN'
)
Write-Host '=== installed printers ==='
Get-Printer | Format-Table Name, DriverName, PortName, PrinterStatus, Type -AutoSize
Write-Host "=== specifically $Name ==="
$p = Get-Printer -Name $Name -ErrorAction SilentlyContinue
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
