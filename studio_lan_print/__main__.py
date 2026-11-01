from __future__ import annotations

import argparse
import logging
import sys

from .config import CONFIG
from .server import IPPServer


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="studio_lan_print", description="LAN IPP print gateway for HP LaserJet Professional P1108")
    parser.add_argument("--host", default=CONFIG.host, help="bind host (default 0.0.0.0)")
    parser.add_argument("--port", type=int, default=CONFIG.port, help="bind port (default 631)")
    parser.add_argument("--printer", default=CONFIG.printer_name, help="Windows printer name")
    parser.add_argument("--no-mdns", action="store_true", help="disable mDNS advertisement")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    CONFIG.host = args.host
    CONFIG.port = args.port
    CONFIG.printer_name = args.printer

    server = IPPServer(CONFIG)
    server.start()

    mdns = None
    if not args.no_mdns:
        try:
            from .mdns import MDNSAdvertiser
            mdns = MDNSAdvertiser(CONFIG)
            mdns.start()
        except Exception as exc:  # noqa: BLE001
            logging.getLogger("mdns").warning("mDNS disabled: %s", exc)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if mdns is not None:
            mdns.stop()
        server.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
