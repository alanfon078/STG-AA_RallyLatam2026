import time
from dataclasses import dataclass

from .clustering import Report
from .frame import Frame


@dataclass
class StoredReport:
    report: Report
    received_at: float


_reports: list[StoredReport] = []
_seen_keys: set[tuple[int, int, int]] = set()
_last_frame_hex: str = ""
_roadblocks: list[dict] = []
_resource_requests: list[dict] = []


def insert_report(frame: Frame) -> bool:
    """Guarda un reporte en memoria evitando duplicados por (node_id, seq, node_time)."""
    global _last_frame_hex
    key = (frame.node_id, frame.seq, frame.node_time)
    if key in _seen_keys:
        return False

    _seen_keys.add(key)
    _last_frame_hex = frame.encode().hex()
    new_id = len(_reports) + 1
    _reports.append(
        StoredReport(
            report=Report(
                id=new_id,
                node_id=frame.node_id,
                verified=frame.verified,
                kind=frame.kind,
                severity=frame.severity,
                affected=frame.affected,
                lat=frame.lat,
                lon=frame.lon,
            ),
            received_at=time.time(),
        )
    )
    return True


def fetch_reports(window_min: int = 10) -> list[Report]:
    """Devuelve los reportes recientes dentro de la ventana de tiempo o verificados."""
    cutoff = time.time() - (window_min * 60)
    return [
        item.report
        for item in _reports
        if item.report.verified or item.received_at >= cutoff
    ]


def add_roadblock(street: str, cause: str, closure: str, lat: float, lon: float) -> dict:
    entry = {
        "id": len(_roadblocks) + 1,
        "street": street,
        "cause": cause,
        "closure": closure,
        "lat": lat,
        "lon": lon,
    }
    _roadblocks.insert(0, entry)
    return entry


def fetch_roadblocks() -> list[dict]:
    return list(_roadblocks)


def add_resource_request(zone: str, resource: str, unit_status: str, notes: str) -> dict:
    entry = {
        "id": len(_resource_requests) + 1,
        "zone": zone,
        "resource": resource,
        "unit_status": unit_status,
        "notes": notes,
    }
    _resource_requests.insert(0, entry)
    return entry


def fetch_resource_requests() -> list[dict]:
    return list(_resource_requests)


def get_last_frame_hex() -> str:
    return _last_frame_hex


def clear_reports() -> None:
    """Limpia los reportes en memoria para reiniciar la demostración en vivo."""
    global _last_frame_hex
    _reports.clear()
    _seen_keys.clear()
    _roadblocks.clear()
    _resource_requests.clear()
    _last_frame_hex = ""
