# Experimental Python prototype

**Not the production path.** The supported studio deploy is PowerShell under `../ps/` (IPP `:8631` + embedded mDNS).

This package sketches the same idea in Python (`zeroconf` + `pywin32`), historically on port **631**. Kept for reference / future ports only.

```text
python -m venv .venv
.venv\Scripts\pip install -r ..\requirements.txt
.venv\Scripts\python -m studio_lan_print --help
```

Prefer `../ps/Install-StudioLanPrint.ps1` for real studio use.
