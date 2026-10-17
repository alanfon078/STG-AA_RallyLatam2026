from fastapi.testclient import TestClient

from app.main import app


def test_demo_end_to_end_flow():
    client = TestClient(app)

    # 1. Reiniciar el estado en memoria
    assert client.post("/demo/reset").status_code == 200

    # 2. Verificar que el Dashboard del Puesto de Comando carga correctamente
    home = client.get("/")
    assert home.status_code == 200
    assert "Dashboard del Puesto de Comando" in home.text

    # 3. Simular ráfaga de 18 alertas ciudadanas en Zona A y 3 en Zona B
    sim = client.post("/demo/simulate")
    assert sim.status_code == 200
    assert sim.json()["sent"] == 21

    state_before = client.get("/demo/state").json()
    assert len(state_before["clusters"]) == 2
    assert state_before["clusters"][0]["recommendation"] == "RECONOCIMIENTO"
    assert state_before["clusters"][0]["urgency"] == 30.0

    # 4. Enviar dictamen verificado desde el Mock de App Brigadista en Zona A
    verify = client.post(
        "/demo/report",
        json={
            "lat": 20.140,
            "lon": -101.180,
            "kind": 4,
            "affected": 4,
            "verified": True,
            "severity": 9,
        },
    )
    assert verify.status_code == 200

    # 5. Verificar que el clúster sube a FUERZA_TAREA y aumenta su urgencia
    state_after = client.get("/demo/state").json()
    top_cluster = state_after["clusters"][0]
    assert top_cluster["verified"] is True
    assert top_cluster["recommendation"] == "FUERZA_TAREA"
    assert top_cluster["urgency"] > 80.0
