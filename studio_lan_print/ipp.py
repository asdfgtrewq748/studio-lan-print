"""Minimal IPP (RFC 8010/8011) encoder/decoder.

Only the subset needed for a print gateway is implemented.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import Any

# Operation codes
OP_PRINT_JOB = 0x0002
OP_VALIDATE_JOB = 0x0004
OP_CREATE_JOB = 0x0005
OP_SEND_DOCUMENT = 0x0006
OP_CANCEL_JOB = 0x0008
OP_GET_JOB_ATTRIBUTES = 0x0009
OP_GET_JOBS = 0x000A
OP_GET_PRINTER_ATTRIBUTES = 0x000B

# Status codes
STATUS_OK = 0x0000
STATUS_OK_IGNORED_OR_SUBSTITUTED = 0x0001
STATUS_CLIENT_ERROR_BAD_REQUEST = 0x0400
STATUS_CLIENT_ERROR_NOT_FOUND = 0x0406
STATUS_CLIENT_ERROR_NOT_POSSIBLE = 0x0404
STATUS_SERVER_ERROR_INTERNAL = 0x0500
STATUS_SERVER_ERROR_NOT_ACCEPTING = 0x0506

# Tags
tag_operation_attributes = 0x01
tag_job_attributes = 0x02
tag_end_of_attributes = 0x03
tag_printer_attributes = 0x04
tag_unsupported_attributes = 0x05

# Value tags
tag_integer = 0x21
tag_boolean = 0x22
tag_enum = 0x23
tag_octet_string = 0x30
tag_date_time = 0x31
tag_resolution = 0x32
tag_range_of_integer = 0x33
tag_beg_collection = 0x34
tag_text_language = 0x35
tag_name_with_language = 0x36
tag_end_collection = 0x37
tag_text_without_language = 0x41
tag_name_without_language = 0x42
tag_keyword = 0x44
tag_uri = 0x45
tag_uri_scheme = 0x46
tag_charset = 0x47
tag_natural_language = 0x48
tag_mime_media_type = 0x49


@dataclass
class Attribute:
    name: str
    tag: int
    values: list[Any] = field(default_factory=list)


@dataclass
class IPPRequest:
    version_major: int
    version_minor: int
    operation_id: int
    request_id: int
    operation_attributes: list[Attribute] = field(default_factory=list)
    job_attributes: list[Attribute] = field(default_factory=list)
    printer_attributes: list[Attribute] = field(default_factory=list)
    unsupported_attributes: list[Attribute] = field(default_factory=list)
    data: bytes = b""

    def get(self, name: str, default: Any = None) -> Any:
        for group in (self.operation_attributes, self.job_attributes, self.printer_attributes):
            for attr in group:
                if attr.name == name:
                    return attr.values[0] if attr.values else default
        return default

    def get_all(self, name: str) -> list[Any]:
        for group in (self.operation_attributes, self.job_attributes, self.printer_attributes):
            for attr in group:
                if attr.name == name:
                    return list(attr.values)
        return []


class IPPParseError(Exception):
    pass


def _read_attr_value(tag: int, data: bytes, offset: int) -> tuple[Any, int]:
    if offset + 2 > len(data):
        raise IPPParseError("truncated attribute value length")
    (length,) = struct.unpack_from(">H", data, offset)
    offset += 2
    if offset + length > len(data):
        raise IPPParseError("truncated attribute value")
    raw = data[offset:offset + length]
    offset += length

    if tag in (tag_integer, tag_enum):
        if length != 4:
            raise IPPParseError("bad integer length")
        return struct.unpack(">i", raw)[0], offset
    if tag == tag_boolean:
        if length != 1:
            raise IPPParseError("bad boolean length")
        return raw[0] != 0, offset
    if tag == tag_range_of_integer:
        if length != 8:
            raise IPPParseError("bad range length")
        lo, hi = struct.unpack(">ii", raw)
        return (lo, hi), offset
    if tag == tag_resolution:
        if length != 9:
            raise IPPParseError("bad resolution length")
        x, y, units = struct.unpack(">iiB", raw)
        return (x, y, units), offset
    if tag in (tag_text_without_language, tag_name_without_language, tag_keyword, tag_uri, tag_uri_scheme, tag_charset, tag_natural_language, tag_mime_media_type):
        return raw.decode("utf-8", errors="replace"), offset
    if tag in (tag_text_language, tag_name_with_language):
        if length < 4:
            raise IPPParseError("bad language string")
        (lang_len,) = struct.unpack_from(">H", raw, 0)
        lang = raw[2:2 + lang_len].decode("ascii", errors="replace")
        text = raw[2 + lang_len:].decode("utf-8", errors="replace")
        return (lang, text), offset
    if tag == tag_octet_string:
        return raw, offset
    if tag == tag_date_time:
        return raw, offset
    # Unknown tag: return raw bytes
    return raw, offset


def parse_request(data: bytes) -> IPPRequest:
    if len(data) < 8:
        raise IPPParseError("too short")
    version_major, version_minor, operation_id, request_id = struct.unpack_from(">BBHI", data, 0)
    offset = 8
    req = IPPRequest(version_major, version_minor, operation_id, request_id)

    current_group: list[Attribute] | None = None
    last_attr: Attribute | None = None

    while offset < len(data):
        tag = data[offset]
        offset += 1
        if tag == tag_end_of_attributes:
            break
        if offset + 2 > len(data):
            raise IPPParseError("truncated name length")
        (name_len,) = struct.unpack_from(">H", data, offset)
        offset += 2
        if offset + name_len > len(data):
            raise IPPParseError("truncated name")
        name = data[offset:offset + name_len].decode("utf-8", errors="replace")
        offset += name_len

        if tag in (tag_operation_attributes, tag_job_attributes, tag_printer_attributes, tag_unsupported_attributes):
            if tag == tag_operation_attributes:
                current_group = req.operation_attributes
            elif tag == tag_job_attributes:
                current_group = req.job_attributes
            elif tag == tag_printer_attributes:
                current_group = req.printer_attributes
            else:
                current_group = req.unsupported_attributes
            last_attr = None
            continue

        if current_group is None:
            raise IPPParseError("attribute outside group")

        if name_len == 0:
            if last_attr is None:
                raise IPPParseError("additional value without attribute")
            value, offset = _read_attr_value(tag, data, offset)
            last_attr.values.append(value)
        else:
            value, offset = _read_attr_value(tag, data, offset)
            attr = Attribute(name=name, tag=tag, values=[value])
            current_group.append(attr)
            last_attr = attr

    req.data = data[offset:]
    return req


def _encode_value(tag: int, value: Any) -> bytes:
    if tag in (tag_integer, tag_enum):
        return struct.pack(">H", 4) + struct.pack(">i", int(value))
    if tag == tag_boolean:
        return struct.pack(">H", 1) + (b"\x01" if value else b"\x00")
    if tag == tag_range_of_integer:
        lo, hi = value
        return struct.pack(">H", 8) + struct.pack(">ii", int(lo), int(hi))
    if tag == tag_resolution:
        x, y, units = value
        return struct.pack(">H", 9) + struct.pack(">iiB", int(x), int(y), int(units))
    if tag in (tag_text_without_language, tag_name_without_language, tag_keyword, tag_uri, tag_uri_scheme, tag_charset, tag_natural_language, tag_mime_media_type):
        raw = str(value).encode("utf-8")
        return struct.pack(">H", len(raw)) + raw
    if tag in (tag_text_language, tag_name_with_language):
        lang, text = value
        lang_b = lang.encode("ascii")
        text_b = text.encode("utf-8")
        raw = struct.pack(">H", len(lang_b)) + lang_b + text_b
        return struct.pack(">H", len(raw)) + raw
    if tag == tag_octet_string:
        raw = bytes(value)
        return struct.pack(">H", len(raw)) + raw
    if tag == tag_date_time:
        raw = bytes(value)
        return struct.pack(">H", len(raw)) + raw
    raise ValueError(f"unsupported tag {tag:#x}")


def _encode_attr(attr: Attribute) -> bytes:
    out = bytearray()
    name_b = attr.name.encode("utf-8")
    for i, value in enumerate(attr.values):
        if i == 0:
            out.append(attr.tag)
            out += struct.pack(">H", len(name_b))
            out += name_b
        else:
            out.append(attr.tag)
            out += struct.pack(">H", 0)
        out += _encode_value(attr.tag, value)
    return bytes(out)


def build_response(
    request_id: int,
    status_code: int,
    operation_attributes: list[Attribute] | None = None,
    job_attributes: list[Attribute] | None = None,
    printer_attributes: list[Attribute] | None = None,
    version_major: int = 1,
    version_minor: int = 1,
) -> bytes:
    out = bytearray()
    out += struct.pack(">BBHI", version_major, version_minor, status_code, request_id)
    if operation_attributes:
        out.append(tag_operation_attributes)
        for attr in operation_attributes:
            out += _encode_attr(attr)
    if job_attributes:
        out.append(tag_job_attributes)
        for attr in job_attributes:
            out += _encode_attr(attr)
    if printer_attributes:
        out.append(tag_printer_attributes)
        for attr in printer_attributes:
            out += _encode_attr(attr)
    out.append(tag_end_of_attributes)
    return bytes(out)


def attr(name: str, tag: int, *values: Any) -> Attribute:
    return Attribute(name=name, tag=tag, values=list(values))
