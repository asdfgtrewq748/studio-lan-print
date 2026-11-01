# Contributing

## Scope of v0.1

This release is the **studio-shaped** edition that already runs in our lab:

- Windows host + USB **HP LaserJet Professional P1108**
- IPP on TCP **8631**, Bonjour-style mDNS name **Studio-HP-LAN**
- Client fallback hard-codes studio LAN IP **10.4.81.41**

Config generalization (arbitrary printer name / port / IP, installer UX, auth) is **next**, not in this first publish.

## What helps

- Bug reports with: Windows version, same-LAN or not, whether mDNS discovery works, `/health` JSON, and a redacted `service.log` snippet
- Patches that keep the PowerShell path working without requiring Python
- Docs that clarify campus Wi-Fi / multicast failure modes

## What to avoid

- Committing SumatraPDF / Acrobat binaries
- Committing probe dumps (`*.bin`, `*.b64`) or AI chat transcripts
- Assuming Windows “Share this printer” SMB share is a drop-in replacement (see `docs/EXPERIENCE.md`)

## Dev notes

Production path: `ps/StudioLanPrint.ps1` + `Install-StudioLanPrint.ps1`.  
`studio_lan_print/` is an experimental Python alternate (default port 631 there); do not treat it as the supported deploy.
