$ErrorActionPreference = 'Stop'
$desk = [Environment]::GetFolderPath('Desktop')
$health = (Invoke-WebRequest 'http://10.4.81.41:8631/health' -UseBasicParsing -TimeoutSec 5).Content
Write-Host ('health: ' + $health)
$reqPath = Join-Path $desk 'probe-get-attrs.bin'
$req = [IO.File]::ReadAllBytes($reqPath)
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('Content-Type','application/ipp')
$resp = $wc.UploadData('http://10.4.81.41:8631/ipp/print', 'POST', $req)
$out = Join-Path $desk 'probe-resp.bin'
[IO.File]::WriteAllBytes($out, $resp)
Write-Host ('resp bytes=' + $resp.Length + ' status=0x' + ((([int]$resp[2] -shl 8) -bor $resp[3]).ToString('X4')))
& (Join-Path $desk 'Decode-IppAttrs.ps1') -Path $out
