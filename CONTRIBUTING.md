# Contributing

## Scope

The supported deploy is the PowerShell service in `ps/`. It shares a Windows-installed local printer over IPP and mDNS.

- Printer queue, IPP port, mDNS instance name, and optional display name come from `%ProgramData%\StudioLanPrint\config.json`. Environment variables override that file for the current process.
- An empty `printerName` prefers **HP LaserJet Professional P1108** when that queue exists, otherwise the first suitable local printer.
- Studio reference values remain the defaults: port **8631**, mDNS **Studio-HP-LAN**, client example `http://10.4.81.41:8631/ipp/print`.
- Authentication and TLS are out of scope.

`studio_lan_print/` is an experimental Python alternate (default port 631 there); do not treat it as the supported deploy.

## What helps

- Bug reports with: Windows version, same-LAN or not, whether mDNS discovery works, `/health` JSON, and a redacted `service.log` snippet
- Patches that keep the PowerShell path working without requiring Python
- Docs that clarify campus Wi-Fi / multicast failure modes

## What to avoid

- Committing SumatraPDF / Acrobat binaries
- Committing probe dumps (`*.bin`, `*.b64`) or AI chat transcripts
- Assuming Windows “Share this printer” SMB share is a drop-in replacement (see `docs/EXPERIENCE.md`)

## Dev notes

Production path: `ps/StudioLanPrint.ps1`, `ps/StudioLanPrint.Config.ps1`, and `Install-StudioLanPrint.ps1`.  
Config template: `ps/config.example.json`. Client defaults: `client/config.json`.
