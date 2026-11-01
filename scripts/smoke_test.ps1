$ErrorActionPreference = "Stop"

$Base = "http://127.0.0.1:631"
Write-Host "Checking health at $Base/health ..."
$Health = Invoke-RestMethod -Uri "$Base/health" -Method Get
$Health | ConvertTo-Json -Compress

Write-Host "Fetching printer attributes via IPP ..."
$IppBody = [byte[]](0x01, 0x01, 0x00, 0x0B, 0x00, 0x00, 0x00, 0x01, 0x01, 0x47, 0x00, 0x12, 0x61, 0x74, 0x74, 0x72, 0x69, 0x62, 0x75, 0x74, 0x65, 0x73, 0x2D, 0x63, 0x68, 0x61, 0x72, 0x73, 0x65, 0x74, 0x00, 0x05, 0x75, 0x74, 0x66, 0x2D, 0x38, 0x03)
$Response = Invoke-WebRequest -Uri "$Base/ipp/print" -Method Post -Body $IppBody -ContentType "application/ipp" -UseBasicParsing
Write-Host "IPP response status: $($Response.StatusCode), bytes: $($Response.RawContentLength)"

Write-Host "Smoke test complete. To test printing, send a PDF to $Base/ipp/print from an IPP client."
