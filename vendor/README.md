# Vendor binaries (not shipped)

This folder is intentionally empty in git.

PDF jobs are rendered with **SumatraPDF** (preferred):

1. Download the Windows 64-bit build from <https://www.sumatrapdfreader.org/>
2. Place `SumatraPDF.exe` either:
   - in `%ProgramData%\StudioLanPrint\` (next to the installed service script), or
   - in `%USERPROFILE%\Documents\studio-lan-print\`, or
   - temporarily beside the install scripts before you run `Deploy-StudioLanPrint-mdns.ps1` / copy it into ProgramData yourself

Optional fallback: Adobe Acrobat / Reader on the host. Set env `STUDIO_LAN_ACROBAT` to the full path of `Acrobat.exe` if needed. Do not commit vendor executables.
