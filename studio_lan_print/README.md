# Experimental Python prototype

**Not the production path.** The supported deploy is PowerShell under `../ps/` (IPP, default `:8631`, plus embedded mDNS). That service can target any local Windows printer. This prototype still carries the original HP LaserJet Professional P1108 sample strings.

This package sketches the same idea in Python (`zeroconf` + `pywin32`), historically on port **631**. Kept for reference / future ports only.

```text
python -m venv .venv
.venv\Scripts\pip install -r ..\requirements.txt
.venv\Scripts\python -m studio_lan_print --help
```

Prefer `../ps/Install-StudioLanPrint.ps1` for real studio use.
