from __future__ import annotations

import logging
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

log = logging.getLogger("print_submit")


def _is_windows() -> bool:
    return sys.platform.startswith("win")


def _powershell() -> str:
    return shutil.which("powershell.exe") or shutil.which("powershell") or "powershell.exe"


def _run_ps(script: str, timeout: int = 120) -> tuple[int, str, str]:
    cmd = [_powershell(), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script]
    log.debug("powershell: %s", script)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return proc.returncode, proc.stdout, proc.stderr


def submit_pdf_via_printto(path: Path, printer_name: str) -> None:
    """Use Windows Shell 'PrintTo' verb to print a PDF/XPS to a named printer."""
    if not _is_windows():
        raise RuntimeError("PrintTo verb requires Windows")
    # Escape single quotes for PowerShell single-quoted strings
    p = str(path).replace("'", "''")
    prn = printer_name.replace("'", "''")
    script = (
        f"$ErrorActionPreference='Stop'; "
        f"Start-Process -FilePath '{p}' -Verb PrintTo -ArgumentList '\"{prn}\"' -Wait"
    )
    rc, out, err = _run_ps(script, timeout=300)
    if rc != 0:
        raise RuntimeError(f"PrintTo failed rc={rc} err={err.strip()} out={out.strip()}")


def submit_raw_via_win32print(path: Path, printer_name: str) -> None:
    """Send raw bytes to a Windows printer via win32print (RAW datatype)."""
    if not _is_windows():
        raise RuntimeError("win32print requires Windows")
    try:
        import win32print  # type: ignore
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError(f"pywin32 not installed: {exc}") from exc

    data = path.read_bytes()
    handle = win32print.OpenPrinter(printer_name)
    try:
        job_id = win32print.StartDocPrinter(handle, 1, (path.name, None, "RAW"))
        try:
            win32print.StartPagePrinter(handle)
            win32print.WritePrinter(handle, data)
            win32print.EndPagePrinter(handle)
        finally:
            win32print.EndDocPrinter(handle)
        log.info("raw job %s sent to %s (%d bytes)", job_id, printer_name, len(data))
    finally:
        win32print.ClosePrinter(handle)


def submit_text_via_out_printer(path: Path, printer_name: str) -> None:
    if not _is_windows():
        raise RuntimeError("Out-Printer requires Windows")
    p = str(path).replace("'", "''")
    prn = printer_name.replace("'", "''")
    script = (
        f"$ErrorActionPreference='Stop'; "
        f"Get-Content -LiteralPath '{p}' -Raw | Out-Printer -Name '{prn}'"
    )
    rc, out, err = _run_ps(script, timeout=120)
    if rc != 0:
        raise RuntimeError(f"Out-Printer failed rc={rc} err={err.strip()} out={out.strip()}")


def submit_document(path: Path, content_type: str, printer_name: str) -> str:
    """Submit a saved document to the printer. Returns a short method description."""
    ct = (content_type or "").lower().split(";", 1)[0].strip()
    suffix = path.suffix.lower()

    if ct == "application/pdf" or suffix == ".pdf":
        submit_pdf_via_printto(path, printer_name)
        return "pdf-printto"
    if ct in ("application/xps", "application/oxps") or suffix in (".xps", ".oxps"):
        submit_pdf_via_printto(path, printer_name)
        return "xps-printto"
    if ct.startswith("text/") or suffix in (".txt", ".log"):
        submit_text_via_out_printer(path, printer_name)
        return "text-out-printer"
    # Default: raw passthrough (PCL, PostScript, JPEG, PNG, octet-stream)
    submit_raw_via_win32print(path, printer_name)
    return "raw-win32print"


def save_document(data: bytes, content_type: str, jobs_dir: Path, job_id: int) -> Path:
    ct = (content_type or "").lower().split(";", 1)[0].strip()
    ext = ".bin"
    if ct == "application/pdf":
        ext = ".pdf"
    elif ct in ("application/xps", "application/oxps"):
        ext = ".xps"
    elif ct == "application/postscript":
        ext = ".ps"
    elif ct == "image/jpeg":
        ext = ".jpg"
    elif ct == "image/png":
        ext = ".png"
    elif ct.startswith("text/"):
        ext = ".txt"
    elif ct in ("application/vnd.hp-pcl", "application/pcl"):
        ext = ".pcl"

    jobs_dir.mkdir(parents=True, exist_ok=True)
    path = jobs_dir / f"job-{job_id:06d}{ext}"
    path.write_bytes(data)
    return path
