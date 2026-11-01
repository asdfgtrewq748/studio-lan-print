from __future__ import annotations

import json
import logging
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Optional

from . import ipp
from .config import CONFIG, Config
from .print_submit import save_document, submit_document

log = logging.getLogger(__name__)
_job_seq = int(time.time()) % 100000


class IPPHandler(BaseHTTPRequestHandler):
    server_version = "StudioLanPrint/0.1"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        log.info("%s - %s", self.address_string(), fmt % args)

    def _send_ipp_response(self, body: bytes, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "application/ipp")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, obj: dict, status: int = 200) -> None:
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path in ("/health", "/healthz"):
            self._send_json({"status": "ok", "printer": CONFIG.printer_name, "port": CONFIG.port})
        elif self.path in ("/", "/ipp/print", "/ipp/printer"):
            body = b"Studio LAN Print IPP gateway. POST IPP requests to /ipp/print.\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404)

    def do_POST(self) -> None:  # noqa: N802
        if self.path not in ("/ipp/print", "/ipp/printer"):
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", "0") or 0)
        if length <= 0:
            self.send_error(400, "Empty IPP request")
            return
        if length > CONFIG.max_job_bytes:
            self.send_error(413, "Request too large")
            return

        data = self.rfile.read(length)
        try:
            request = ipp.parse_request(data)
        except Exception as exc:  # noqa: BLE001
            log.warning("Failed to decode IPP request: %s", exc)
            self.send_error(400, "Bad IPP request")
            return

        try:
            response = self._handle_ipp(request)
        except Exception:  # noqa: BLE001
            log.exception("IPP handling failed")
            response = ipp.build_response(
                request.request_id,
                ipp.STATUS_SERVER_ERROR_INTERNAL,
                operation_attributes=[
                    ipp.attr("attributes-charset", ipp.tag_charset, "utf-8"),
                    ipp.attr("attributes-natural-language", ipp.tag_natural_language, "en"),
                ],
                version_major=request.version_major,
                version_minor=request.version_minor,
            )

        self._send_ipp_response(response)

    def _handle_ipp(self, request: ipp.IPPRequest) -> bytes:
        op = request.operation_id
        log.info("IPP operation 0x%04x from %s", op, self.address_string())
        op_attrs = [
            ipp.attr("attributes-charset", ipp.tag_charset, "utf-8"),
            ipp.attr("attributes-natural-language", ipp.tag_natural_language, "en"),
        ]

        if op == ipp.OP_GET_PRINTER_ATTRIBUTES:
            return ipp.build_response(
                request.request_id,
                ipp.STATUS_OK,
                operation_attributes=op_attrs,
                printer_attributes=_printer_attributes(),
                version_major=request.version_major,
                version_minor=request.version_minor,
            )

        if op == ipp.OP_VALIDATE_JOB:
            return ipp.build_response(
                request.request_id,
                ipp.STATUS_OK,
                operation_attributes=op_attrs,
                version_major=request.version_major,
                version_minor=request.version_minor,
            )

        if op == ipp.OP_PRINT_JOB:
            return self._handle_print_job(request, op_attrs)

        if op in (ipp.OP_GET_JOBS, ipp.OP_CANCEL_JOB, ipp.OP_GET_JOB_ATTRIBUTES):
            return ipp.build_response(
                request.request_id,
                ipp.STATUS_OK,
                operation_attributes=op_attrs,
                version_major=request.version_major,
                version_minor=request.version_minor,
            )

        log.warning("Unsupported IPP operation 0x%04x", op)
        return ipp.build_response(
            request.request_id,
            ipp.STATUS_CLIENT_ERROR_BAD_REQUEST,
            operation_attributes=op_attrs,
            version_major=request.version_major,
            version_minor=request.version_minor,
        )

    def _handle_print_job(self, request: ipp.IPPRequest, op_attrs: list) -> bytes:
        global _job_seq
        job_name = str(request.get("job-name", "Studio LAN Print Job"))
        document_format = str(request.get("document-format", "application/octet-stream"))
        document = request.data or b""

        if not document:
            log.warning("Print-Job without document data")
            return ipp.build_response(
                request.request_id,
                ipp.STATUS_CLIENT_ERROR_BAD_REQUEST,
                operation_attributes=op_attrs,
                version_major=request.version_major,
                version_minor=request.version_minor,
            )

        _job_seq += 1
        job_id = _job_seq
        CONFIG.ensure_dirs()
        path = save_document(document, document_format, CONFIG.jobs_dir, job_id)
        log.info("saved job %s (%s) %s bytes -> %s", job_id, job_name, len(document), path)

        try:
            method = submit_document(path, document_format, CONFIG.printer_name)
            log.info("submitted job %s via %s", job_id, method)
            status = ipp.STATUS_OK
            job_state = 9  # completed
        except Exception as exc:  # noqa: BLE001
            log.exception("Failed to submit print job: %s", exc)
            status = ipp.STATUS_SERVER_ERROR_INTERNAL
            job_state = 8  # aborted

        job_attrs = [
            ipp.attr("job-id", ipp.tag_integer, job_id),
            ipp.attr("job-state", ipp.tag_enum, job_state),
            ipp.attr("job-state-reasons", ipp.tag_keyword, "none"),
            ipp.attr("job-uri", ipp.tag_uri, f"ipp://{self._host()}/jobs/{job_id}"),
            ipp.attr("job-name", ipp.tag_name_without_language, job_name),
        ]
        return ipp.build_response(
            request.request_id,
            status,
            operation_attributes=op_attrs,
            job_attributes=job_attrs,
            version_major=request.version_major,
            version_minor=request.version_minor,
        )

    def _host(self) -> str:
        host = self.headers.get("Host")
        if host:
            return host
        return f"{self.server.server_address[0]}:{self.server.server_address[1]}"


def _printer_attributes() -> list[ipp.Attribute]:
    return [
        ipp.attr("printer-name", ipp.tag_name_without_language, CONFIG.printer_name),
        ipp.attr("printer-info", ipp.tag_text_without_language, CONFIG.service_name),
        ipp.attr("printer-make-and-model", ipp.tag_text_without_language, "HP LaserJet Professional P1108"),
        ipp.attr("printer-state", ipp.tag_enum, 3),
        ipp.attr("printer-state-reasons", ipp.tag_keyword, "none"),
        ipp.attr("printer-is-accepting-jobs", ipp.tag_boolean, True),
        ipp.attr("ipp-versions-supported", ipp.tag_keyword, "1.1"),
        ipp.attr(
            "operations-supported",
            ipp.tag_enum,
            ipp.OP_PRINT_JOB,
            ipp.OP_VALIDATE_JOB,
            ipp.OP_GET_PRINTER_ATTRIBUTES,
            ipp.OP_GET_JOBS,
            ipp.OP_CANCEL_JOB,
        ),
        ipp.attr(
            "document-format-supported",
            ipp.tag_mime_media_type,
            "application/pdf",
            "application/postscript",
            "application/octet-stream",
            "application/vnd.hp-pcl",
            "text/plain",
        ),
        ipp.attr("charset-configured", ipp.tag_charset, "utf-8"),
        ipp.attr("charset-supported", ipp.tag_charset, "utf-8"),
        ipp.attr("natural-language-configured", ipp.tag_natural_language, "en"),
        ipp.attr("generated-natural-language-supported", ipp.tag_natural_language, "en"),
        ipp.attr("uri-security-supported", ipp.tag_keyword, "none"),
        ipp.attr("uri-authentication-supported", ipp.tag_keyword, "none"),
        ipp.attr(
            "printer-uri-supported",
            ipp.tag_uri,
            f"ipp://{socket.gethostname()}:{CONFIG.port}/ipp/print",
        ),
    ]


class IPPServer:
    def __init__(self, config: Config = CONFIG) -> None:
        self.config = config
        self._httpd: Optional[ThreadingHTTPServer] = None

    def start(self) -> None:
        self.config.ensure_dirs()
        self._httpd = ThreadingHTTPServer((self.config.host, self.config.port), IPPHandler)
        self._httpd.daemon_threads = True
        log.info("IPP server listening on %s:%s", self.config.host, self.config.port)

    def serve_forever(self) -> None:
        if self._httpd is None:
            self.start()
        assert self._httpd is not None
        self._httpd.serve_forever()

    def shutdown(self) -> None:
        if self._httpd is not None:
            self._httpd.shutdown()
            self._httpd.server_close()
            self._httpd = None
