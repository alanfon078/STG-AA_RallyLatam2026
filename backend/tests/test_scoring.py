from app.scoring import FUERZA_TAREA, RECONOCIMIENTO, recommend, urgency_score


def test_unverified_cluster_never_reaches_verified_ceiling():
    assert urgency_score(citizen_count=50, verified=False, severity=10) == 30.0


def test_verified_severity_dominates():
    low = urgency_score(citizen_count=5, verified=True, severity=2)
    high = urgency_score(citizen_count=5, verified=True, severity=9)
    assert high > low


def test_density_saturates():
    assert urgency_score(10, False, 0) == urgency_score(40, False, 0)


def test_road_penalty_lowers_score():
    clear = urgency_score(8, True, 7)
    blocked = urgency_score(8, True, 7, road_penalty=1.0)
    assert blocked < clear


def test_score_is_clamped():
    assert urgency_score(50, True, 10, vulnerability=1.0) == 100.0
    assert urgency_score(0, False, 0, road_penalty=1.0) == 0.0


def test_recommendation_follows_verification():
    assert recommend(False) == RECONOCIMIENTO
    assert recommend(True) == FUERZA_TAREA
