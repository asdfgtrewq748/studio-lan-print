# StudioLanPrint host settings.
# Dot-source this file. It does not start the service.
# Precedence: environment variable, then %ProgramData%\StudioLanPrint\config.json, then built-in defaults.
# Empty printerName: prefer "HP LaserJet Professional P1108", else the first suitable local printer.

function Get-StudioPreferredPrinterName {
    return 'HP LaserJet Professional P1108'
}

function Get-StudioLanPrintConfigPath {
    $root = $env:ProgramData
    if ([string]::IsNullOrWhiteSpace($root)) { $root = 'C:\ProgramData' }
    return (Join-Path (Join-Path $root 'StudioLanPrint') 'config.json')
}

function Get-JsonField {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop) { return $null }
    return $prop.Value
}

function ConvertTo-StudioPort {
    param($Value, [string]$Label)
    if ($null -eq $Value) { return $null }
    $text = ''
    if ($Value -is [double] -or $Value -is [decimal] -or $Value -is [float]) {
        $rounded = [math]::Round([double]$Value)
        if ([math]::Abs([double]$Value - $rounded) -gt 0.0001) {
            throw "StudioLanPrint: $Label must be a TCP port from 1 to 65535 (got '$Value')."
        }
        $text = [string][int]$rounded
    } else {
        $text = ([string]$Value).Trim()
    }
    if ($text -eq '') { return $null }
    $n = 0
    $ok = [int]::TryParse($text, [ref]$n)
    if (-not $ok -or $n -lt 1 -or $n -gt 65535) {
        throw "StudioLanPrint: $Label must be a TCP port from 1 to 65535 (got '$Value')."
    }
    return [int]$n
}

function Test-StudioIPv4 {
    param([string]$Ip)
    if ([string]::IsNullOrWhiteSpace($Ip)) { return $false }
    if ($Ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $false }
    foreach ($part in $Ip.Split('.')) {
        if ($part.Length -gt 1 -and $part.StartsWith('0')) { return $false }
        $n = 0
        if (-not [int]::TryParse($part, [ref]$n)) { return $false }
        if ($n -lt 0 -or $n -gt 255) { return $false }
    }
    return $true
}

function Test-StudioDnsLabel {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value -match '^(?=.{1,63}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
}

function Get-StudioEnvText {
    param([hashtable]$Environment, [string]$Name)
    if ($null -eq $Environment) { return $null }
    if (-not $Environment.ContainsKey($Name)) { return $null }
    $text = [string]$Environment[$Name]
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text.Trim()
}

function Get-StudioProcessEnv {
    param([string[]]$Names)
    $map = @{}
    foreach ($name in $Names) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) { $map[$name] = $value.Trim() }
    }
    return $map
}

function Read-StudioJsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = [IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "StudioLanPrint: config file is empty: $Path"
    }
    try {
        $obj = $raw | ConvertFrom-Json
    } catch {
        throw "StudioLanPrint: config file is not valid JSON (${Path}): $($_.Exception.Message)"
    }
    if ($obj -is [System.Array]) {
        throw "StudioLanPrint: config file must be a JSON object: $Path"
    }
    return $obj
}

function Merge-StudioLanPrintSettings {
    param(
        $FileConfig,
        [hashtable]$Environment = @{},
        [string]$ConfigPath = '',
        [bool]$ConfigPresent = $false
    )
    if ($null -eq $Environment) { $Environment = @{} }

    $printer = ''
    $printerSource = 'auto'
    $filePrinter = Get-JsonField $FileConfig 'printerName'
    if ($null -ne $filePrinter -and -not [string]::IsNullOrWhiteSpace([string]$filePrinter)) {
        $printer = ([string]$filePrinter).Trim()
        $printerSource = 'file'
    }
    $envPrinter = Get-StudioEnvText $Environment 'STUDIO_LAN_PRINTER'
    if ($envPrinter) {
        $printer = $envPrinter
        $printerSource = 'env'
    }

    $port = 8631
    $filePort = ConvertTo-StudioPort (Get-JsonField $FileConfig 'port') 'config.json port'
    if ($null -ne $filePort) { $port = $filePort }
    if ($Environment.ContainsKey('STUDIO_LAN_PORT') -and -not [string]::IsNullOrWhiteSpace([string]$Environment['STUDIO_LAN_PORT'])) {
        $envPort = ConvertTo-StudioPort $Environment['STUDIO_LAN_PORT'] 'STUDIO_LAN_PORT'
        $port = $envPort
    }

    $service = 'Studio-HP-LAN'
    $fileService = Get-JsonField $FileConfig 'serviceInstance'
    if ($null -ne $fileService -and -not [string]::IsNullOrWhiteSpace([string]$fileService)) {
        $service = ([string]$fileService).Trim()
    }
    $envService = Get-StudioEnvText $Environment 'STUDIO_LAN_SERVICE'
    if ($envService) { $service = $envService }
    if (-not (Test-StudioDnsLabel $service)) {
        throw "StudioLanPrint: serviceInstance '$service' must be one DNS label (letters, digits, hyphen), for example Studio-HP-LAN."
    }

    $display = ''
    $fileDisplay = Get-JsonField $FileConfig 'displayName'
    if ($null -ne $fileDisplay -and -not [string]::IsNullOrWhiteSpace([string]$fileDisplay)) {
        $display = ([string]$fileDisplay).Trim()
    }
    $envDisplay = Get-StudioEnvText $Environment 'STUDIO_LAN_DISPLAY'
    if ($envDisplay) { $display = $envDisplay }

    $fallback = '10.4.81.41'
    $fileFallback = Get-JsonField $FileConfig 'fallbackLanIp'
    if ($null -ne $fileFallback -and -not [string]::IsNullOrWhiteSpace([string]$fileFallback)) {
        $fallback = ([string]$fileFallback).Trim()
    }
    $envFallback = Get-StudioEnvText $Environment 'STUDIO_LAN_FALLBACK_IP'
    if ($envFallback) { $fallback = $envFallback }
    if (-not (Test-StudioIPv4 $fallback)) {
        throw "StudioLanPrint: fallbackLanIp '$fallback' is not an IPv4 address."
    }

    return [pscustomobject]@{
        PrinterName = $printer
        PrinterNameSource = $printerSource
        Port = [int]$port
        ServiceInstance = $service
        DisplayName = $display
        FallbackLanIp = $fallback
        PreferredPrinter = (Get-StudioPreferredPrinterName)
        ConfigPath = $ConfigPath
        ConfigPresent = [bool]$ConfigPresent
    }
}

function Get-StudioLanPrintSettings {
    param(
        [string]$ConfigPath,
        [hashtable]$Environment
    )
    if (-not $PSBoundParameters.ContainsKey('ConfigPath') -or [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Get-StudioLanPrintConfigPath
    }
    $present = Test-Path -LiteralPath $ConfigPath
    $file = $null
    if ($present) { $file = Read-StudioJsonFile $ConfigPath }
    if (-not $PSBoundParameters.ContainsKey('Environment') -or $null -eq $Environment) {
        $Environment = Get-StudioProcessEnv -Names @(
            'STUDIO_LAN_PRINTER',
            'STUDIO_LAN_PORT',
            'STUDIO_LAN_SERVICE',
            'STUDIO_LAN_DISPLAY',
            'STUDIO_LAN_FALLBACK_IP'
        )
    }
    return Merge-StudioLanPrintSettings -FileConfig $file -Environment $Environment -ConfigPath $ConfigPath -ConfigPresent $present
}

function Initialize-StudioLanPrintConfig {
    param([Parameter(Mandatory = $true)][string]$ExamplePath)
    if (-not (Test-Path -LiteralPath $ExamplePath)) {
        throw "StudioLanPrint: missing config template: $ExamplePath"
    }
    $dest = Get-StudioLanPrintConfigPath
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $exampleDest = Join-Path $dir 'config.example.json'
    Copy-Item -LiteralPath $ExamplePath -Destination $exampleDest -Force
    $created = $false
    if (-not (Test-Path -LiteralPath $dest)) {
        Copy-Item -LiteralPath $ExamplePath -Destination $dest -Force
        $created = $true
    }
    return [pscustomobject]@{ Path = $dest; Created = $created }
}

function Get-StudioLanPrintOverrideNote {
    param($Effective, $FromFile)
    $notes = @()
    if ([string]$Effective.PrinterName -ne [string]$FromFile.PrinterName) {
        $notes += "printerName env='$($Effective.PrinterName)' file='$($FromFile.PrinterName)'"
    }
    if ([int]$Effective.Port -ne [int]$FromFile.Port) {
        $notes += "port env=$($Effective.Port) file=$($FromFile.Port)"
    }
    if ([string]$Effective.ServiceInstance -ne [string]$FromFile.ServiceInstance) {
        $notes += "serviceInstance env=$($Effective.ServiceInstance) file=$($FromFile.ServiceInstance)"
    }
    if ([string]$Effective.DisplayName -ne [string]$FromFile.DisplayName) {
        $notes += 'displayName overridden by STUDIO_LAN_DISPLAY'
    }
    if ([string]$Effective.FallbackLanIp -ne [string]$FromFile.FallbackLanIp) {
        $notes += "fallbackLanIp env=$($Effective.FallbackLanIp) file=$($FromFile.FallbackLanIp)"
    }
    if ($notes.Count -eq 0) { return $null }
    return ('Environment overrides config.json for this process (' + ($notes -join '; ') + '). The logon shortcut does not keep a temporary shell variable. Put lasting values in ' + $FromFile.ConfigPath + '.')
}

function Get-StudioLanPrintListenPorts {
    param($Effective, $FromFile)
    $result = New-Object System.Collections.Generic.List[int]
    foreach ($n in @([int]$Effective.Port, [int]$FromFile.Port)) {
        $seen = $false
        foreach ($existing in $result) {
            if ($existing -eq $n) { $seen = $true }
        }
        if (-not $seen) { [void]$result.Add($n) }
    }
    return @($result.ToArray())
}

function Test-StudioVirtualPrinter {
    param($Printer)
    $name = [string]$Printer.Name
    $driver = [string]$Printer.DriverName
    $port = [string]$Printer.PortName
    if ($port -match '^(?i)(PORTPROMPT:|nul:|SHRFAX:|FILE:)$') { return $true }
    if ($name -match '(?i)^(Fax|Microsoft Print to PDF|Microsoft XPS Document Writer)$') { return $true }
    $blob = "$name $driver"
    if ($blob -match '(?i)(Microsoft Print to PDF|XPS Document Writer|OneNote|Adobe PDF|Foxit Reader PDF|PDFCreator|CutePDF)') { return $true }
    if ($driver -match '(?i)Microsoft Shared Fax Driver') { return $true }
    return $false
}

function Test-StudioLocalQueue {
    param($Printer)
    $type = [string]$Printer.Type
    if ($type -eq 'Connection') { return $false }
    $port = [string]$Printer.PortName
    if ($port -like '\\*') { return $false }
    return $true
}

function Format-InstalledPrinterList {
    param([object[]]$Printers)
    $rows = @($Printers | Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) } | Sort-Object { [string]$_.Name })
    if ($rows.Count -eq 0) { return '  (none)' }
    $lines = foreach ($p in $rows) {
        $bits = @('name=' + [string]$p.Name)
        $port = [string]$p.PortName
        $driver = [string]$p.DriverName
        if ($port) { $bits += 'port=' + $port }
        if ($driver) { $bits += 'driver=' + $driver }
        '  - ' + ($bits -join ', ')
    }
    return ($lines -join "`n")
}

function Resolve-StudioLanPrintPrinter {
    param(
        [string]$ConfiguredName,
        [AllowEmptyCollection()][object[]]$Printers = @(),
        [string]$ConfigPath = '',
        [string]$PreferredName = ''
    )
    if ([string]::IsNullOrWhiteSpace($PreferredName)) { $PreferredName = Get-StudioPreferredPrinterName }
    $list = @($Printers | Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) })
    $where = $ConfigPath
    if ([string]::IsNullOrWhiteSpace($where)) { $where = '%ProgramData%\StudioLanPrint\config.json' }
    $listing = Format-InstalledPrinterList $list

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredName)) {
        $want = $ConfiguredName.Trim()
        $match = @($list | Where-Object { [string]$_.Name -eq $want })
        if ($match.Count -eq 0) {
            throw ("StudioLanPrint: printer '$want' is not installed.`nSet printerName in $where or set STUDIO_LAN_PRINTER to an installed queue name.`nInstalled printers:`n$listing")
        }
        return [pscustomobject]@{ Name = [string]$match[0].Name; Source = 'configured' }
    }

    $preferred = @($list | Where-Object { [string]$_.Name -eq $PreferredName })
    if ($preferred.Count -gt 0) {
        return [pscustomobject]@{ Name = [string]$preferred[0].Name; Source = 'preferred' }
    }

    $suitable = @($list | Where-Object { (Test-StudioLocalQueue $_) -and -not (Test-StudioVirtualPrinter $_) })
    $usb = @(
        $suitable |
            Where-Object { [string]$_.PortName -like 'USB*' } |
            Sort-Object @{ Expression = { [string]$_.PortName } }, @{ Expression = { [string]$_.Name } }
    )
    if ($usb.Count -gt 0) {
        return [pscustomobject]@{ Name = [string]$usb[0].Name; Source = 'usb' }
    }
    $local = @($suitable | Sort-Object { [string]$_.Name })
    if ($local.Count -gt 0) {
        return [pscustomobject]@{ Name = [string]$local[0].Name; Source = 'local' }
    }

    throw ("StudioLanPrint: no suitable local printer was found.`nAn empty printerName prefers '$PreferredName' when that queue exists; otherwise the first USB local printer (lowest port name), then any other local non-virtual queue.`nSet printerName in $where or set STUDIO_LAN_PRINTER.`nInstalled printers:`n$listing")
}

function Limit-StudioTxt {
    param([string]$Value, [int]$MaxBytes)
    if ($null -eq $Value) { return '' }
    $text = ($Value -replace "[\r\n\t]", ' ').Trim()
    $enc = [Text.Encoding]::UTF8
    while ($text.Length -gt 0 -and $enc.GetByteCount($text) -gt $MaxBytes) {
        $text = $text.Substring(0, $text.Length - 1)
    }
    return $text
}

function Get-StudioDeviceId {
    param([string]$PrinterName, [string]$ServiceInstance)
    $service = ($ServiceInstance -replace ';', '')
    if ($PrinterName -eq (Get-StudioPreferredPrinterName) -and $ServiceInstance -eq 'Studio-HP-LAN') {
        return 'MFG:HP;MDL:LaserJet Professional P1108;CMD:PDF,PCL;CLS:PRINTER;DES:Studio-HP-LAN;'
    }
    if ($PrinterName -eq (Get-StudioPreferredPrinterName)) {
        return "MFG:HP;MDL:LaserJet Professional P1108;CMD:PDF,PCL;CLS:PRINTER;DES:${service};"
    }
    $model = Limit-StudioTxt ($PrinterName -replace ';', ',') 120
    return "MFG:Generic;MDL:${model};CMD:PDF;CLS:PRINTER;DES:${service};"
}

function New-StudioLanPrintIdentity {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Printers
    )
    $resolved = Resolve-StudioLanPrintPrinter -ConfiguredName $Settings.PrinterName -Printers $Printers -ConfigPath $Settings.ConfigPath -PreferredName $Settings.PreferredPrinter
    $source = [string]$resolved.Source
    if ($source -eq 'configured') { $source = [string]$Settings.PrinterNameSource }
    $printerName = [string]$resolved.Name
    $service = [string]$Settings.ServiceInstance
    $explicitDisplay = -not [string]::IsNullOrWhiteSpace([string]$Settings.DisplayName)
    if ($explicitDisplay) {
        $display = ([string]$Settings.DisplayName).Trim()
    } elseif ($printerName -eq (Get-StudioPreferredPrinterName)) {
        $display = 'Studio LAN HP P1108'
    } else {
        $display = $printerName
    }

    $useStudio = (
        ($printerName -eq (Get-StudioPreferredPrinterName)) -and
        ($service -eq 'Studio-HP-LAN') -and
        (-not $explicitDisplay)
    )
    if ($useStudio) {
        $printerInfo = 'Studio LAN HP P1108'
        $txtTy = 'Studio HP LAN'
        $txtProduct = '(Studio HP LAN)'
        $usbMfg = 'HP'
        $usbMdl = 'LaserJet Professional P1108'
        $displayOut = 'Studio LAN HP P1108'
    } else {
        $printerInfo = $display
        $txtTy = Limit-StudioTxt $display 200
        $txtProduct = '(' + (Limit-StudioTxt $display 180) + ')'
        if ($printerName -eq (Get-StudioPreferredPrinterName)) {
            $usbMfg = 'HP'
            $usbMdl = 'LaserJet Professional P1108'
        } else {
            $usbMfg = 'Generic'
            $usbMdl = Limit-StudioTxt ($printerName -replace ';', ',') 180
        }
        $displayOut = $display
    }

    return [pscustomobject]@{
        PrinterName = $printerName
        PrinterSource = $source
        Port = [int]$Settings.Port
        ServiceInstance = $service
        MdnsHost = $service.ToLowerInvariant()
        DisplayName = $displayOut
        FallbackLanIp = [string]$Settings.FallbackLanIp
        ConfigPath = [string]$Settings.ConfigPath
        ConfigPresent = [bool]$Settings.ConfigPresent
        UseStudioIdentity = [bool]$useStudio
        PrinterInfo = $printerInfo
        MakeAndModel = $printerName
        DeviceId = (Get-StudioDeviceId -PrinterName $printerName -ServiceInstance $service)
        TxtTy = $txtTy
        TxtProduct = $txtProduct
        UsbMfg = $usbMfg
        UsbMdl = $usbMdl
    }
}

function ConvertTo-StudioHealthText {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    # -replace substitution text is literal, so one backslash in the pattern is written as '\\'.
    $text = $Value -replace '\\', '\\'
    $text = $text -replace '"', '\"'
    $text = $text -replace "`r", ''
    $text = $text -replace "`n", '\n'
    $text = $text -replace "`t", '\t'
    return $text
}

function Get-StudioLanPrintIdentity {
    if (-not (Get-Command Get-Printer -ErrorAction SilentlyContinue)) {
        throw 'StudioLanPrint: Get-Printer is not available. Run the service on Windows where the printer cmdlets exist.'
    }
    try {
        $raw = Get-Printer -ErrorAction Stop
    } catch {
        throw "StudioLanPrint: cannot list printers (Get-Printer failed): $($_.Exception.Message)"
    }
    if ($null -eq $raw) {
        $printers = @()
    } else {
        $printers = @($raw | Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) })
    }
    $settings = Get-StudioLanPrintSettings
    return New-StudioLanPrintIdentity -Settings $settings -Printers $printers
}
