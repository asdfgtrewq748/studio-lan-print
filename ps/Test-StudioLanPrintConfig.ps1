# Config and client-target tests. No Windows spooler required.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path -Parent $here
. (Join-Path $here 'StudioLanPrint.Config.ps1')
. (Join-Path (Join-Path $repo 'client') 'StudioClient.Config.ps1')

$script:Failed = 0
function Assert-True {
    param($Cond, [string]$Message)
    if (-not $Cond) {
        Write-Host "FAIL: $Message"
        $script:Failed++
    } else {
        Write-Host "OK: $Message"
    }
}
function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        Write-Host "FAIL: $Message"
        Write-Host "  expected: [$Expected]"
        Write-Host "  actual:   [$Actual]"
        $script:Failed++
    } else {
        Write-Host "OK: $Message"
    }
}
function Assert-Throws {
    param([scriptblock]$Block, [string]$MustContain, [string]$Message)
    $threw = $false
    $text = ''
    try { & $Block } catch { $threw = $true; $text = [string]$_.Exception.Message }
    if (-not $threw) {
        Write-Host "FAIL: $Message (no throw)"
        $script:Failed++
        return
    }
    if ($MustContain -and $text -notlike "*$MustContain*") {
        Write-Host "FAIL: $Message"
        Write-Host "  message: $text"
        $script:Failed++
        return
    }
    Write-Host "OK: $Message"
}

function New-TestPrinter {
    param([string]$Name, [string]$PortName, [string]$DriverName, [string]$Type = 'Local')
    return [pscustomobject]@{ Name = $Name; PortName = $PortName; DriverName = $DriverName; Type = $Type }
}

function Repo-Path {
    param([string]$Relative)
    $full = $repo
    foreach ($part in ($Relative -split '/')) { $full = Join-Path $full $part }
    return $full
}

$examplePath = Join-Path $here 'config.example.json'
$clientConfigPath = Join-Path (Join-Path $repo 'client') 'config.json'
$defaults = Merge-StudioLanPrintSettings -FileConfig $null -Environment @{} -ConfigPath 'C:\ProgramData\StudioLanPrint\config.json' -ConfigPresent $false

Assert-Equal $defaults.Port 8631 'default port 8631'
Assert-Equal $defaults.ServiceInstance 'Studio-HP-LAN' 'default service instance'
Assert-Equal $defaults.FallbackLanIp '10.4.81.41' 'default fallback IP'
Assert-Equal $defaults.PrinterName '' 'default printer name empty'
Assert-Equal $defaults.DisplayName '' 'default display name empty'
Assert-Equal $defaults.PrinterNameSource 'auto' 'default printer source auto'
Assert-Equal $defaults.PreferredPrinter 'HP LaserJet Professional P1108' 'preferred printer constant'

$fromExample = Get-StudioLanPrintSettings -ConfigPath $examplePath -Environment @{}
Assert-Equal $fromExample.Port $defaults.Port 'example json port matches defaults'
Assert-Equal $fromExample.ServiceInstance $defaults.ServiceInstance 'example json service matches defaults'
Assert-Equal $fromExample.FallbackLanIp $defaults.FallbackLanIp 'example json fallback matches defaults'
Assert-Equal $fromExample.PrinterName '' 'example json printerName empty'
Assert-Equal $fromExample.DisplayName '' 'example json displayName empty'
Assert-True ($fromExample.ConfigPresent) 'example json counts as present'
$exampleRaw = [IO.File]::ReadAllText($examplePath)
Assert-True ($exampleRaw -like '*STUDIO_LAN_PRINTER*') 'example documents STUDIO_LAN_PRINTER'
Assert-True ($exampleRaw -like '*HP LaserJet Professional P1108*') 'example documents P1108 preference'

$envPort = Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ port = 9000; printerName = 'Queued' }) -Environment @{ STUDIO_LAN_PORT = '9100'; STUDIO_LAN_PRINTER = 'From Env' } -ConfigPath 'c:\cfg.json' -ConfigPresent $true
Assert-Equal $envPort.Port 9100 'env port overrides file'
Assert-Equal $envPort.PrinterName 'From Env' 'env printer overrides file'
Assert-Equal $envPort.PrinterNameSource 'env' 'printer source env'

$blankEnv = Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ port = 9000; printerName = 'Queued' }) -Environment @{ STUDIO_LAN_PORT = '   '; STUDIO_LAN_PRINTER = '' } -ConfigPath 'c:\cfg.json' -ConfigPresent $true
Assert-Equal $blankEnv.Port 9000 'blank env port does not override'
Assert-Equal $blankEnv.PrinterName 'Queued' 'blank env printer does not override'
Assert-Equal $blankEnv.PrinterNameSource 'file' 'printer source file'

Assert-Throws { Merge-StudioLanPrintSettings -FileConfig $null -Environment @{ STUDIO_LAN_PORT = 'nope' } } '65535' 'invalid port throws'
Assert-Throws { Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ serviceInstance = 'Studio HP' }) -Environment @{} } 'DNS label' 'service name with spaces throws'
Assert-Throws { Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ serviceInstance = 'Studio-' }) -Environment @{} } 'DNS label' 'service name with trailing hyphen throws'
Assert-Throws { Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ fallbackLanIp = '10.4.81' }) -Environment @{} } 'IPv4' 'bad fallback IP throws'
$single = Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ serviceInstance = 'A' }) -Environment @{}
Assert-Equal $single.ServiceInstance 'A' 'single-letter service name allowed'

$samePorts = @(Get-StudioLanPrintListenPorts -Effective ([pscustomobject]@{ Port = 8631 }) -FromFile ([pscustomobject]@{ Port = 8631 }))
Assert-Equal $samePorts.Count 1 'one listen port when env matches file'
Assert-Equal $samePorts[0] 8631 'listen port is 8631'
$twoPorts = @(Get-StudioLanPrintListenPorts -Effective ([pscustomobject]@{ Port = 9000 }) -FromFile ([pscustomobject]@{ Port = 8631 }))
Assert-Equal $twoPorts.Count 2 'two listen ports when env differs'
Assert-Equal $twoPorts[0] 9000 'effective port is listed first'
Assert-Equal $twoPorts[1] 8631 'file port is listed second'
Assert-True ([string]::IsNullOrEmpty((Get-StudioLanPrintOverrideNote -Effective $defaults -FromFile $defaults))) 'no override note when settings match'
$note = Get-StudioLanPrintOverrideNote -Effective $envPort -FromFile $blankEnv
Assert-True ($note -like '*config.json*') 'override note mentions config.json'

Assert-Equal (ConvertTo-StudioHealthText 'HP LaserJet Professional P1108') 'HP LaserJet Professional P1108' 'health text leaves studio name unchanged'
Assert-Equal (ConvertTo-StudioHealthText 'a\b"c') 'a\\b\"c' 'health text escapes json'
Assert-Equal (ConvertTo-StudioHealthText "line`n2") 'line\n2' 'health text escapes newline'

$p1108 = New-TestPrinter 'HP LaserJet Professional P1108' 'USB001' 'HP LaserJet Professional P1108'
$brother = New-TestPrinter 'Brother HL-L2350DW' 'USB002' 'Brother HL-L2350DW'
$zebra = New-TestPrinter 'Zebra' 'USB001' 'Zebra'
$aaa = New-TestPrinter 'Aaa' 'USB002' 'Aaa'
$pdf = New-TestPrinter 'Microsoft Print to PDF' 'PORTPROMPT:' 'Microsoft Print To PDF'
$office = New-TestPrinter 'Office Laser' 'IP_192.168.0.20' 'Office Laser'
$remote = New-TestPrinter 'Hall Printer' '\\server\hall' 'Remote' 'Connection'
$cute = New-TestPrinter 'CutePDF Writer' 'USB001' 'CutePDF Writer'

$studio = New-StudioLanPrintIdentity -Settings $defaults -Printers @($pdf, $brother, $p1108, $remote)
Assert-Equal $studio.PrinterName 'HP LaserJet Professional P1108' 'prefers P1108 over other USB printers'
Assert-Equal $studio.PrinterSource 'preferred' 'P1108 source is preferred'
Assert-True $studio.UseStudioIdentity 'studio identity flag'
Assert-Equal $studio.ServiceInstance 'Studio-HP-LAN' 'studio service name'
Assert-Equal $studio.MdnsHost 'studio-hp-lan' 'studio mdns host label'
Assert-Equal $studio.Port 8631 'studio port'
Assert-Equal $studio.FallbackLanIp '10.4.81.41' 'studio fallback'
Assert-Equal $studio.PrinterInfo 'Studio LAN HP P1108' 'studio printer-info'
Assert-Equal $studio.MakeAndModel 'HP LaserJet Professional P1108' 'studio make and model'
Assert-Equal $studio.DeviceId 'MFG:HP;MDL:LaserJet Professional P1108;CMD:PDF,PCL;CLS:PRINTER;DES:Studio-HP-LAN;' 'studio device-id bytes'
Assert-Equal $studio.TxtTy 'Studio HP LAN' 'studio txt ty'
Assert-Equal $studio.TxtProduct '(Studio HP LAN)' 'studio txt product'
Assert-Equal $studio.UsbMfg 'HP' 'studio usb mfg'
Assert-Equal $studio.UsbMdl 'LaserJet Professional P1108' 'studio usb mdl'
Assert-Equal ('ty=' + $studio.TxtTy) 'ty=Studio HP LAN' 'composed ty record'
Assert-Equal ('product=' + $studio.TxtProduct) 'product=(Studio HP LAN)' 'composed product record'

$displaySettings = Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ displayName = 'Lab Printer' }) -Environment @{} -ConfigPath 'c:\cfg.json' -ConfigPresent $true
$customDisplay = New-StudioLanPrintIdentity -Settings $displaySettings -Printers @($p1108)
Assert-True (-not $customDisplay.UseStudioIdentity) 'explicit display leaves studio identity mode'
Assert-Equal $customDisplay.PrinterInfo 'Lab Printer' 'explicit display becomes printer-info'
Assert-Equal $customDisplay.TxtTy 'Lab Printer' 'explicit display becomes txt ty'
Assert-Equal $customDisplay.DeviceId 'MFG:HP;MDL:LaserJet Professional P1108;CMD:PDF,PCL;CLS:PRINTER;DES:Studio-HP-LAN;' 'P1108 device-id stays when service name is unchanged'

$usbOnly = New-StudioLanPrintIdentity -Settings $defaults -Printers @($pdf, $brother, $office, $remote)
Assert-Equal $usbOnly.PrinterName 'Brother HL-L2350DW' 'selects USB printer when P1108 is absent'
Assert-Equal $usbOnly.PrinterSource 'usb' 'usb source'
Assert-True (-not $usbOnly.UseStudioIdentity) 'non-P1108 is not studio identity'
Assert-Equal $usbOnly.MakeAndModel 'Brother HL-L2350DW' 'make and model is the queue name'
Assert-Equal $usbOnly.DisplayName 'Brother HL-L2350DW' 'display falls back to queue name'
Assert-True ($usbOnly.DeviceId -like '*MDL:Brother HL-L2350DW*') 'device-id uses the queue'
Assert-True ($usbOnly.DeviceId -notlike '*P1108*') 'device-id does not claim P1108'

$usbOrder = New-StudioLanPrintIdentity -Settings $defaults -Printers @($aaa, $zebra, $pdf)
Assert-Equal $usbOrder.PrinterName 'Zebra' 'lowest USB port name wins'

$skipCute = New-StudioLanPrintIdentity -Settings $defaults -Printers @($cute, $brother)
Assert-Equal $skipCute.PrinterName 'Brother HL-L2350DW' 'virtual USB queue is skipped'

$localOnly = New-StudioLanPrintIdentity -Settings $defaults -Printers @($pdf, $office, $remote)
Assert-Equal $localOnly.PrinterName 'Office Laser' 'local non-USB queue is the next choice'
Assert-Equal $localOnly.PrinterSource 'local' 'local source'

$pinned = Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ printerName = 'brother hl-l2350dw' }) -Environment @{} -ConfigPath 'c:\cfg.json' -ConfigPresent $true
$pinnedId = New-StudioLanPrintIdentity -Settings $pinned -Printers @($p1108, $brother)
Assert-Equal $pinnedId.PrinterName 'Brother HL-L2350DW' 'configured name wins over P1108'
Assert-Equal $pinnedId.PrinterSource 'file' 'configured source is file'

$pdfSettings = Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ printerName = 'Microsoft Print to PDF' }) -Environment @{} -ConfigPath 'c:\cfg.json' -ConfigPresent $true
$pdfId = New-StudioLanPrintIdentity -Settings $pdfSettings -Printers @($pdf, $brother)
Assert-Equal $pdfId.PrinterName 'Microsoft Print to PDF' 'explicit name may select a virtual queue'

Assert-Throws { New-StudioLanPrintIdentity -Settings $defaults -Printers @($pdf, $remote) } 'Microsoft Print to PDF' 'failure lists installed printers'
Assert-Throws { New-StudioLanPrintIdentity -Settings $defaults -Printers @() } '(none)' 'failure lists none when no printers exist'
$missing = Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ printerName = 'Nope' }) -Environment @{} -ConfigPath 'c:\cfg.json' -ConfigPresent $true
Assert-Throws { New-StudioLanPrintIdentity -Settings $missing -Printers @($brother, $pdf) } 'Brother HL-L2350DW' 'missing configured printer lists the queues that exist'
Assert-Throws { New-StudioLanPrintIdentity -Settings $missing -Printers @($brother) } 'Nope' 'missing configured printer names the requested queue'

$lab = Merge-StudioLanPrintSettings -FileConfig ([pscustomobject]@{ serviceInstance = 'Lab-Printer' }) -Environment @{} -ConfigPath 'c:\cfg.json' -ConfigPresent $true
$labId = New-StudioLanPrintIdentity -Settings $lab -Printers @($p1108)
Assert-Equal $labId.ServiceInstance 'Lab-Printer' 'custom service instance'
Assert-Equal $labId.MdnsHost 'lab-printer' 'mdns host is lowercased service name'
Assert-Equal $labId.DeviceId 'MFG:HP;MDL:LaserJet Professional P1108;CMD:PDF,PCL;CLS:PRINTER;DES:Lab-Printer;' 'device-id follows custom service name'
Assert-True (-not $labId.UseStudioIdentity) 'custom service is not the original studio identity'

$savedPd = $env:ProgramData
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('studio-lan-print-' + [guid]::NewGuid().ToString('n'))
try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $env:ProgramData = $tempRoot
    $init = Initialize-StudioLanPrintConfig -ExamplePath $examplePath
    Assert-True $init.Created 'starter config is created'
    Assert-True (Test-Path -LiteralPath $init.Path) 'starter config path exists'
    $seeded = Get-StudioLanPrintSettings -Environment @{}
    Assert-Equal $seeded.Port 8631 'seeded config keeps port 8631'
    $raw = [IO.File]::ReadAllText($init.Path)
    $raw = $raw -replace '"port": 8631', '"port": 9000'
    [IO.File]::WriteAllText($init.Path, $raw)
    $again = Initialize-StudioLanPrintConfig -ExamplePath $examplePath
    Assert-True (-not $again.Created) 'existing config is kept'
    $kept = Get-StudioLanPrintSettings -Environment @{}
    Assert-Equal $kept.Port 9000 're-init does not reset port'
    $badPath = Join-Path $tempRoot 'bad.json'
    [IO.File]::WriteAllText($badPath, '{')
    Assert-Throws { Get-StudioLanPrintSettings -ConfigPath $badPath -Environment @{} } 'not valid JSON' 'invalid config json throws'
} finally {
    if ($null -eq $savedPd) { Remove-Item Env:ProgramData -ErrorAction SilentlyContinue }
    else { $env:ProgramData = $savedPd }
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

$clientDefault = Resolve-StudioClientTarget -Bound @{} -FileConfig $null -Environment @{}
Assert-Equal $clientDefault.PrinterUrl 'http://10.4.81.41:8631/ipp/print' 'client default URL'
Assert-Equal $clientDefault.HealthUrl 'http://10.4.81.41:8631/health' 'client default health URL'
Assert-Equal $clientDefault.DisplayName 'Studio-HP-LAN' 'client default display name'
Assert-Equal $clientDefault.Host '10.4.81.41' 'client default host'
Assert-Equal $clientDefault.Port 8631 'client default port'

$fromDisk = Resolve-StudioClientTarget -Bound @{} -Environment @{} -ConfigPath $clientConfigPath
Assert-Equal $fromDisk.PrinterUrl $clientDefault.PrinterUrl 'shipped client config matches studio reference'
Assert-Equal $fromDisk.DisplayName 'Studio-HP-LAN' 'shipped client display name'

$fileClient = [pscustomobject]@{ host = '192.168.1.10'; port = 9000; printerUrl = ''; displayName = 'From File' }
$envClient = @{ STUDIO_LAN_HOST = '192.168.1.11'; STUDIO_LAN_PORT = '9001'; STUDIO_LAN_DISPLAY = 'From Env' }
$resolvedEnv = Resolve-StudioClientTarget -Bound @{} -FileConfig $fileClient -Environment $envClient
Assert-Equal $resolvedEnv.PrinterUrl 'http://192.168.1.11:9001/ipp/print' 'client env overrides file'
Assert-Equal $resolvedEnv.DisplayName 'From Env' 'client env display overrides file'
$resolvedBound = Resolve-StudioClientTarget -Bound @{ HostIp = '192.168.1.12'; Port = 9002; DisplayName = 'From Bound' } -FileConfig $fileClient -Environment $envClient
Assert-Equal $resolvedBound.PrinterUrl 'http://192.168.1.12:9002/ipp/print' 'client parameters override env'
Assert-Equal $resolvedBound.DisplayName 'From Bound' 'client parameter display overrides env'
$resolvedUrl = Resolve-StudioClientTarget -Bound @{ HostIp = '192.168.1.12'; PrinterUrl = 'http://10.9.9.9:8700/ipp/print' } -FileConfig $fileClient -Environment @{}
Assert-Equal $resolvedUrl.PrinterUrl 'http://10.9.9.9:8700/ipp/print' 'printer URL overrides host'
Assert-Equal $resolvedUrl.HealthUrl 'http://10.9.9.9:8700/health' 'health URL follows printer URL'
Assert-Equal $resolvedUrl.Host '10.9.9.9' 'cleanup host comes from printer URL'
Assert-Equal $resolvedUrl.Port 8700 'cleanup port comes from printer URL'
$portZero = Resolve-StudioClientTarget -Bound @{ Port = 0 } -FileConfig $fileClient -Environment @{}
Assert-Equal $portZero.PrinterUrl 'http://192.168.1.10:9000/ipp/print' 'port 0 means unset'
Assert-Throws { Resolve-StudioClientTarget -Bound @{ PrinterUrl = 'not a url' } -Environment @{} } 'not absolute' 'bad printer URL throws'

Assert-Throws { Get-StudioLanPrintIdentity } 'not available' 'identity lookup explains a missing Get-Printer'

$parseFiles = @(
    'ps/StudioLanPrint.ps1',
    'ps/StudioLanPrint.Config.ps1',
    'ps/Install-StudioLanPrint.ps1',
    'ps/Deploy-StudioLanPrint-mdns.ps1',
    'ps/Check-Printer.ps1',
    'ps/Smoke-Print.ps1',
    'ps/Try-AddIpp.ps1',
    'ps/Probe-FromClient.ps1',
    'ps/Test-StudioLanPrintConfig.ps1',
    'client/Add-StudioPrinter.ps1',
    'client/StudioClient.Config.ps1'
)
foreach ($rel in $parseFiles) {
    $path = Repo-Path $rel
    $tokens = $null
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    $errText = ''
    if ($errs) { $errText = ($errs | ForEach-Object { $_.ToString() }) -join '; ' }
    Assert-True ((-not $errs) -or $errs.Count -eq 0) ("parse " + $rel + " " + $errText)
}

if ($script:Failed -gt 0) {
    Write-Host ("FAILED " + $script:Failed + " assertion(s)")
    exit 1
}
Write-Host 'ALL PASSED'
exit 0
