from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Config:
    host: str = "0.0.0.0"
    port: int = 631
    printer_name: str = "HP LaserJet Professional P1108"
    service_name: str = "Studio HP P1108"
    queue_name: str = "studio-hp-p1108"
    max_job_bytes: int = 200 * 1024 * 1024
    data_dir: Path = field(default_factory=lambda: Path(os.environ.get("ProgramData", r"C:\ProgramData")) / "StudioLanPrint")

    @property
    def jobs_dir(self) -> Path:
        return self.data_dir / "jobs"

    @property
    def log_dir(self) -> Path:
        return self.data_dir / "logs"

    def ensure_dirs(self) -> None:
        self.jobs_dir.mkdir(parents=True, exist_ok=True)
        self.log_dir.mkdir(parents=True, exist_ok=True)


CONFIG = Config()
