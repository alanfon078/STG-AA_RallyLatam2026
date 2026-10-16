from dataclasses import dataclass

import numpy as np
from sklearn.cluster import DBSCAN

EARTH_RADIUS_M = 6_371_000.0


@dataclass(frozen=True)
class Report:
    id: int
    node_id: int
    verified: bool
    kind: int
    severity: int
    affected: int
    lat: float
    lon: float


def cluster_reports(reports: list[Report], radius_m: float) -> list[list[Report]]:
    if not reports:
        return []
    coords = np.radians([[r.lat, r.lon] for r in reports])
    labels = (
        DBSCAN(
            eps=radius_m / EARTH_RADIUS_M,
            min_samples=1,
            metric="haversine",
            algorithm="ball_tree",
        )
        .fit(coords)
        .labels_
    )
    groups: dict[int, list[Report]] = {}
    for report, label in zip(reports, labels):
        groups.setdefault(int(label), []).append(report)
    return list(groups.values())
