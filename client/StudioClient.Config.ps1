# Client target resolution. The client folder does not depend on ps/.
# Precedence: bound parameters, then environment, then client/config.json, then studio reference defaults.
# Defaults: host 10.4.81.41, port 8631, display name Studio-HP-LAN.

function Get-ClientJsonField {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop) { return $null }
    return $prop.Value
}

function ConvertTo-ClientPort {
    param($Value, [string]$Label)
    if ($null -eq $Value) { return $null }
    $text = ''
    if ($Value -is [double] -or $Value -is [decimal] -or $Value -is [float]) {
        $rounded = [math]::Round([double]$Value)
        if ([math]::Abs([double]$Value - $rounded) -gt 0.0001) {
            throw "StudioLanPrint client: $Label must be a TCP port from 1 to 65535 (got '$Value')."
        }
        $text = [string][int]$rounded
    } else {
        $text = ([string]$Value).Trim()
    }
    if ($text -eq '') { return $null }
    $n = 0
    $ok = [int]::TryParse($text, [ref]$n)
    if (-not $ok -or $n -lt 1 -or $n -gt 65535) {
        throw "StudioLanPrint client: $Label must be a TCP port from 1 to 65535 (got '$Value')."
    }
    return [int]$n
}

function Get-ClientEnvText {
    param([hashtable]$Environment, [string]$Name)
    if ($null -eq $Environment) { return $null }
    if (-not $Environment.ContainsKey($Name)) { return $null }
    $text = [string]$Environment[$Name]
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text.Trim()
}

function Resolve-StudioClientTarget {
    param(
        [hashtable]$Bound = @{},
        $FileConfig = $null,
        [hashtable]$Environment = $null,
        [string]$ConfigPath
    )
    if ($PSBoundParameters.ContainsKey('ConfigPath') -and -not [string]::IsNullOrWhiteSpace($ConfigPath) -and -not $PSBoundParameters.ContainsKey('FileConfig')) {
        if (Test-Path -LiteralPath $ConfigPath) {
            $raw = [IO.File]::ReadAllText($ConfigPath)
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                try {
                    $FileConfig = $raw | ConvertFrom-Json
                } catch {
                    throw "StudioLanPrint client: config is not valid JSON (${ConfigPath}): $($_.Exception.Message)"
                }
            }
        }
    }
    if ($null -eq $Bound) { $Bound = @{} }
    if ($null -eq $Environment) {
        $Environment = @{}
        foreach ($name in @('STUDIO_LAN_HOST', 'STUDIO_LAN_PORT', 'STUDIO_LAN_PRINTER_URL', 'STUDIO_LAN_DISPLAY')) {
            $value = [Environment]::GetEnvironmentVariable($name)
            if (-not [string]::IsNullOrWhiteSpace($value)) { $Environment[$name] = $value.Trim() }
        }
    }

    $hostIp = '10.4.81.41'
    $fileHost = Get-ClientJsonField $FileConfig 'host'
    if ($null -ne $fileHost -and -not [string]::IsNullOrWhiteSpace([string]$fileHost)) {
        $hostIp = ([string]$fileHost).Trim()
    }
    $envHost = Get-ClientEnvText $Environment 'STUDIO_LAN_HOST'
    if ($envHost) { $hostIp = $envHost }
    if ($Bound.ContainsKey('HostIp') -and -not [string]::IsNullOrWhiteSpace([string]$Bound['HostIp'])) {
        $hostIp = ([string]$Bound['HostIp']).Trim()
    }

    $port = 8631
    $filePort = ConvertTo-ClientPort (Get-ClientJsonField $FileConfig 'port') 'config.json port'
    if ($null -ne $filePort) { $port = $filePort }
    $envPortText = Get-ClientEnvText $Environment 'STUDIO_LAN_PORT'
    if ($envPortText) { $port = ConvertTo-ClientPort $envPortText 'STUDIO_LAN_PORT' }
    if ($Bound.ContainsKey('Port')) {
        $rawPort = $Bound['Port']
        $portText = ([string]$rawPort).Trim()
        if (-not [string]::IsNullOrWhiteSpace($portText) -and $portText -ne '0') {
            $port = ConvertTo-ClientPort $rawPort '-Port'
        }
    }

    $url = $null
    $fileUrl = Get-ClientJsonField $FileConfig 'printerUrl'
    if ($null -ne $fileUrl -and -not [string]::IsNullOrWhiteSpace([string]$fileUrl)) {
        $url = ([string]$fileUrl).Trim()
    }
    $envUrl = Get-ClientEnvText $Environment 'STUDIO_LAN_PRINTER_URL'
    if ($envUrl) { $url = $envUrl }
    if ($Bound.ContainsKey('PrinterUrl') -and -not [string]::IsNullOrWhiteSpace([string]$Bound['PrinterUrl'])) {
        $url = ([string]$Bound['PrinterUrl']).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($url)) {
        $url = "http://${hostIp}:${port}/ipp/print"
    }

    $display = 'Studio-HP-LAN'
    $fileDisplay = Get-ClientJsonField $FileConfig 'displayName'
    if ($null -ne $fileDisplay -and -not [string]::IsNullOrWhiteSpace([string]$fileDisplay)) {
        $display = ([string]$fileDisplay).Trim()
    }
    $envDisplay = Get-ClientEnvText $Environment 'STUDIO_LAN_DISPLAY'
    if ($envDisplay) { $display = $envDisplay }
    if ($Bound.ContainsKey('DisplayName') -and -not [string]::IsNullOrWhiteSpace([string]$Bound['DisplayName'])) {
        $display = ([string]$Bound['DisplayName']).Trim()
    }

    $uri = $null
    $created = [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri)
    if (-not $created -or -not $uri.IsAbsoluteUri) {
        throw "StudioLanPrint client: printer URL is not absolute: $url"
    }
    if ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') {
        throw "StudioLanPrint client: printer URL must be http or https: $url"
    }
    $builder = New-Object System.UriBuilder $uri
    $builder.Path = '/health'
    $builder.Query = ''
    $builder.Fragment = ''
    $health = $builder.Uri.AbsoluteUri

    return [pscustomobject]@{
        Host = [string]$uri.Host
        Port = [int]$uri.Port
        PrinterUrl = $url
        HealthUrl = $health
        DisplayName = $display
    }
}
