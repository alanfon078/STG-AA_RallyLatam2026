import struct
from dataclasses import dataclass

VERSION = 1
FLAG_BRIGADISTA = 0x01
FLAG_PRIORITY = 0x02

KINDS = {
    0: "DERRUMBE",
    1: "PERSONA_ATRAPADA",
    2: "INUNDACION",
    3: "INCENDIO",
    4: "HERIDO_GRAVE",
}

MAX_SEVERITY = 10
COORD_SCALE = 1_000_000

_HEADER = struct.Struct("<BBBBHHI")
_BODY = struct.Struct("<iiBH")
_CRC = struct.Struct("<H")

FRAME_SIZE = _HEADER.size + _BODY.size + _CRC.size


class FrameError(ValueError):
    pass


def crc16_ccitt(data: bytes) -> int:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else (crc << 1)
            crc &= 0xFFFF
    return crc


@dataclass(frozen=True)
class Frame:
    flags: int
    kind: int
    node_id: int
    seq: int
    node_time: int
    lat: float
    lon: float
    severity: int = 0
    affected: int = 0
    ttl: int = 3
    version: int = VERSION

    @property
    def verified(self) -> bool:
        return bool(self.flags & FLAG_BRIGADISTA)

    def encode(self) -> bytes:
        head = _HEADER.pack(
            self.version, self.flags, self.kind, self.ttl, self.node_id, self.seq, self.node_time
        )
        body = _BODY.pack(
            round(self.lat * COORD_SCALE),
            round(self.lon * COORD_SCALE),
            self.severity,
            self.affected,
        )
        payload = head + body
        return payload + _CRC.pack(crc16_ccitt(payload))

    @classmethod
    def decode(cls, raw: bytes) -> "Frame":
        if len(raw) != FRAME_SIZE:
            raise FrameError(f"longitud invalida: {len(raw)} bytes, se esperaban {FRAME_SIZE}")
        payload, crc_raw = raw[:-_CRC.size], raw[-_CRC.size:]
        if _CRC.unpack(crc_raw)[0] != crc16_ccitt(payload):
            raise FrameError("CRC invalido")
        version, flags, kind, ttl, node_id, seq, node_time = _HEADER.unpack_from(payload, 0)
        lat_e6, lon_e6, severity, affected = _BODY.unpack_from(payload, _HEADER.size)
        if version != VERSION:
            raise FrameError(f"version no soportada: {version}")
        if kind not in KINDS:
            raise FrameError(f"tipo de emergencia desconocido: {kind}")
        if severity > MAX_SEVERITY:
            raise FrameError(f"severidad fuera de rango: {severity}")
        lat, lon = lat_e6 / COORD_SCALE, lon_e6 / COORD_SCALE
        if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
            raise FrameError("coordenadas fuera de rango")
        return cls(
            flags=flags,
            kind=kind,
            node_id=node_id,
            seq=seq,
            node_time=node_time,
            lat=lat,
            lon=lon,
            severity=severity,
            affected=affected,
            ttl=ttl,
            version=version,
        )
