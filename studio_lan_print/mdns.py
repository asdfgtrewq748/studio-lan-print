from __future__ import annotations

import logging
import socket

from zeroconf import ServiceInfo, Zeroconf

from .config import CONFIG, Config

log = logging.getLogger(__name__)


class MDNSAdvertiser:
    def __init__(self, config: Config = CONFIG) -> None:
        self.config = config
        self._zeroconf: Zeroconf | None = None
        self._info: ServiceInfo | None = None

    def start(self) -> None:
        hostname = socket.gethostname()
        address = _local_ip()
        service_type = "_ipp._tcp.local."
        service_name = f"{self.config.service_name}.{service_type}"

        properties = {
            "txtvers": "1",
            "qtotal": "1",
            "rp": "ipp/print",
            "ty": "HP LaserJet Professional P1108",
            "adminurl": f"http://{address}:{self.config.port}/",
            "note": "Studio LAN Print",
            "pdl": "application/pdf,application/postscript,application/octet-stream,application/vnd.hp-pcl,text/plain",
            "product": "(Studio LAN Print)",
            "Color": "F",
            "Duplex": "F",
            "usb_MFG": "HP",
            "usb_MDL": "LaserJet Professional P1108",
        }

        self._info = ServiceInfo(
            type_=service_type,
            name=service_name,
            addresses=[socket.inet_aton(address)],
            port=self.config.port,
            properties=properties,
            server=f"{hostname}.local.",
        )

        self._zeroconf = Zeroconf()
        self._zeroconf.register_service(self._info)
        log.info("mDNS advertising %s at %s:%s", service_name, address, self.config.port)

    def stop(self) -> None:
        if self._zeroconf is not None and self._info is not None:
            self._zeroconf.unregister_service(self._info)
            self._zeroconf.close()
        self._zeroconf = None
        self._info = None


def _local_ip() -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()
