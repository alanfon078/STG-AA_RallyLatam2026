DENSITY_SATURATION = 10
MAX_SEVERITY = 10

W_DENSITY = 30.0
W_VERIFIED = 20.0
W_SEVERITY = 50.0
W_VULNERABILITY = 10.0
W_ROAD_PENALTY = 15.0

RECONOCIMIENTO = "RECONOCIMIENTO"
FUERZA_TAREA = "FUERZA_TAREA"


def urgency_score(
    citizen_count: int,
    verified: bool,
    severity: int,
    vulnerability: float = 0.0,
    road_penalty: float = 0.0,
) -> float:
    density = min(citizen_count / DENSITY_SATURATION, 1.0) * W_DENSITY
    confirmed = 0.0
    if verified:
        confirmed = W_VERIFIED + min(severity, MAX_SEVERITY) / MAX_SEVERITY * W_SEVERITY
    score = density + confirmed + vulnerability * W_VULNERABILITY - road_penalty * W_ROAD_PENALTY
    return round(max(0.0, min(100.0, score)), 1)


def recommend(verified: bool) -> str:
    return FUERZA_TAREA if verified else RECONOCIMIENTO
