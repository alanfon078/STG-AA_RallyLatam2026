from dataclasses import dataclass

from .clustering import Report, cluster_reports
from .frame import KINDS
from .scoring import recommend, urgency_score


@dataclass
class Cluster:
    id: int
    lat: float
    lon: float
    report_count: int
    citizen_count: int
    verified_count: int
    verified: bool
    severity: int
    affected: int
    kinds: list[str]
    urgency: float
    recommendation: str
    report_ids: list[int]


def _centroid(reports: list[Report]) -> tuple[float, float]:
    lat = sum(r.lat for r in reports) / len(reports)
    lon = sum(r.lon for r in reports) / len(reports)
    return lat, lon


def build_clusters(reports: list[Report], radius_m: float) -> list[Cluster]:
    clusters = []
    for group in cluster_reports(reports, radius_m):
        verified_reports = [r for r in group if r.verified]
        citizen_count = len(group) - len(verified_reports)
        severity = max((r.severity for r in verified_reports), default=0)
        affected = sum(r.affected for r in group)
        verified = bool(verified_reports)
        lat, lon = _centroid(verified_reports or group)
        clusters.append(
            Cluster(
                id=min(r.id for r in group),
                lat=lat,
                lon=lon,
                report_count=len(group),
                citizen_count=citizen_count,
                verified_count=len(verified_reports),
                verified=verified,
                severity=severity,
                affected=affected,
                kinds=sorted({KINDS.get(r.kind, "DESCONOCIDO") for r in group}),
                urgency=urgency_score(citizen_count, verified, severity),
                recommendation=recommend(verified),
                report_ids=sorted(r.id for r in group),
            )
        )
    return sorted(clusters, key=lambda c: c.urgency, reverse=True)
