import random

from app.clustering import Report, cluster_reports
from app.scoring import FUERZA_TAREA, RECONOCIMIENTO
from app.service import build_clusters
from sim.simulator import jitter

CENTER = (20.14, -101.18)


def citizen_reports(count: int, center: tuple[float, float], first_id: int = 1) -> list[Report]:
    rng = random.Random(3)
    reports = []
    for offset in range(count):
        lat, lon = jitter(center[0], center[1], 35.0, rng)
        reports.append(
            Report(
                id=first_id + offset,
                node_id=1,
                verified=False,
                kind=0,
                severity=0,
                affected=2,
                lat=lat,
                lon=lon,
            )
        )
    return reports


def test_eighteen_nearby_reports_become_one_cluster():
    groups = cluster_reports(citizen_reports(18, CENTER), radius_m=80.0)
    assert len(groups) == 1
    assert len(groups[0]) == 18


def test_distant_reports_stay_separate():
    near = citizen_reports(5, CENTER)
    far = citizen_reports(3, (CENTER[0] + 0.02, CENTER[1] + 0.02), first_id=100)
    assert len(cluster_reports(near + far, radius_m=80.0)) == 2


def test_empty_input_yields_no_clusters():
    assert cluster_reports([], radius_m=80.0) == []


def test_unverified_cluster_gets_reconnaissance():
    clusters = build_clusters(citizen_reports(18, CENTER), radius_m=80.0)
    assert len(clusters) == 1
    assert clusters[0].recommendation == RECONOCIMIENTO
    assert not clusters[0].verified
    assert clusters[0].citizen_count == 18


def test_verification_upgrades_cluster_and_raises_urgency():
    reports = citizen_reports(18, CENTER)
    before = build_clusters(reports, radius_m=80.0)[0]
    verified = Report(
        id=500,
        node_id=900,
        verified=True,
        kind=0,
        severity=9,
        affected=4,
        lat=CENTER[0],
        lon=CENTER[1],
    )
    after = build_clusters(reports + [verified], radius_m=80.0)
    assert len(after) == 1
    assert after[0].recommendation == FUERZA_TAREA
    assert after[0].verified
    assert after[0].urgency > before.urgency


def test_clusters_are_sorted_by_urgency():
    near = citizen_reports(2, CENTER)
    far = citizen_reports(12, (CENTER[0] + 0.02, CENTER[1] + 0.02), first_id=100)
    clusters = build_clusters(near + far, radius_m=80.0)
    assert clusters[0].citizen_count == 12
    assert clusters[0].urgency >= clusters[1].urgency
