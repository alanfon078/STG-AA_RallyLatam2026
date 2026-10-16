from sqlalchemy import text

from .clustering import Report
from .db import engine
from .frame import FLAG_BRIGADISTA, Frame

_INSERT = text(
    """
    INSERT INTO reports (node_id, seq, node_time, flags, kind, severity, affected, geom)
    VALUES (
        :node_id, :seq, :node_time, :flags, :kind, :severity, :affected,
        ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)
    )
    ON CONFLICT (node_id, seq, node_time) DO NOTHING
    """
)

_SELECT = text(
    """
    SELECT id, node_id, flags, kind, severity, affected,
           ST_Y(geom) AS lat, ST_X(geom) AS lon
    FROM reports
    WHERE (flags & :verified_flag) = :verified_flag
       OR received_at > now() - make_interval(mins => :window)
    ORDER BY id
    """
)


def insert_report(frame: Frame) -> bool:
    with engine.begin() as conn:
        result = conn.execute(
            _INSERT,
            {
                "node_id": frame.node_id,
                "seq": frame.seq,
                "node_time": frame.node_time,
                "flags": frame.flags,
                "kind": frame.kind,
                "severity": frame.severity,
                "affected": frame.affected,
                "lat": frame.lat,
                "lon": frame.lon,
            },
        )
        return result.rowcount == 1


def fetch_reports(window_min: int) -> list[Report]:
    with engine.connect() as conn:
        rows = conn.execute(
            _SELECT, {"verified_flag": FLAG_BRIGADISTA, "window": window_min}
        ).all()
    return [
        Report(
            id=row.id,
            node_id=row.node_id,
            verified=bool(row.flags & FLAG_BRIGADISTA),
            kind=row.kind,
            severity=row.severity,
            affected=row.affected,
            lat=row.lat,
            lon=row.lon,
        )
        for row in rows
    ]
