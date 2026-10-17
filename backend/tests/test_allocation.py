import pytest
from fastapi.testclient import TestClient

from app.allocation import (
    DispatchConsole,
    IncidentLifecycleStatus,
    ResourceCategory,
    ResourceClass,
    ResourceStatus,
    RouteStatus,
    dispatch_console,
    estimate_route,
)
from app.main import app


def test_sci211_resource_model_validation():
    console = DispatchConsole()
    r = console.register_resource(
        code="FT-USAR-01",
        name="Fuerza de Tarea USAR Guanajuato",
        resource_class=ResourceClass.FUERZA_TAREA,
        resource_type=1,
        category=ResourceCategory.RESCATE_URBANO,
        lat=20.140,
        lon=-101.180,
        leader="Cap. Ramírez",
        subordinates_count=5,
    )
    assert r.resource_type == 1
    assert r.resource_class == ResourceClass.FUERZA_TAREA
    assert r.status == ResourceStatus.DISPONIBLE

    with pytest.raises(ValueError, match="resource_type"):
        console.register_resource(
            code="INVALID-01",
            name="Tipo invalido",
            resource_class=ResourceClass.RECURSO_SIMPLE,
            resource_type=5,
            category=ResourceCategory.MEDICO,
            lat=20.14,
            lon=-101.18,
        )


def test_routing_and_eta_with_roadblocks():
    console = DispatchConsole()
    origin = (20.135, -101.180)
    dest = (20.145, -101.180)

    clear_route = estimate_route(origin[0], origin[1], dest[0], dest[1], speed_kmh=45.0)
    assert clear_route.status == RouteStatus.LIBRE
    assert clear_route.blocking_ids == []
    assert clear_route.eta_minutes > 0

    # Bloqueo vial exactamente a mitad del camino (20.140, -101.180)
    block = console.add_road_block(
        lat=20.140,
        lon=-101.180,
        radius_m=80.0,
        severity=7,
        description="Puente colapsado sobre avenida principal",
    )
    detour_route = estimate_route(
        origin[0],
        origin[1],
        dest[0],
        dest[1],
        speed_kmh=45.0,
        road_blocks=console.list_road_blocks(),
    )
    assert detour_route.status == RouteStatus.DESVIO_POR_BLOQUEO
    assert block.id in detour_route.blocking_ids
    assert detour_route.effective_distance_m > clear_route.effective_distance_m
    assert detour_route.eta_minutes > clear_route.eta_minutes


def test_optimal_allocation_respects_two_phase_sci_and_reinforces():
    console = DispatchConsole()
    # Recurso 1: Fuerza de Tarea USAR pesada (Tipo 1)
    usar = console.register_resource(
        code="FT-USAR-1",
        name="USAR Pesado",
        resource_class=ResourceClass.FUERZA_TAREA,
        resource_type=1,
        category=ResourceCategory.RESCATE_URBANO,
        lat=20.139,
        lon=-101.179,
    )
    # Recurso 2: Unidad rápida de reconocimiento (Tipo 4)
    recon = console.register_resource(
        code="REC-MOTO-1",
        name="Unidad Reconocimiento Motorizada",
        resource_class=ResourceClass.RECURSO_SIMPLE,
        resource_type=4,
        category=ResourceCategory.RECONOCIMIENTO,
        lat=20.141,
        lon=-101.181,
    )
    # Recurso 3: Ambulancia de soporte vital (Tipo 2)
    amb = console.register_resource(
        code="AMB-02",
        name="Ambulancia SVA",
        resource_class=ResourceClass.RECURSO_SIMPLE,
        resource_type=2,
        category=ResourceCategory.MEDICO,
        lat=20.138,
        lon=-101.178,
    )

    clusters = [
        {
            "id": 10,
            "lat": 20.140,
            "lon": -101.180,
            "urgency": 92.0,
            "verified": True,
            "severity": 9,
            "recommendation": "FUERZA_TAREA",
            "kinds": ["DERRUMBE", "PERSONA_ATRAPADA"],
        },
        {
            "id": 20,
            "lat": 20.150,
            "lon": -101.190,
            "urgency": 30.0,
            "verified": False,
            "severity": 0,
            "recommendation": "RECONOCIMIENTO",
            "kinds": ["INUNDACION"],
        },
    ]

    proposals = console.optimize_and_dispatch(clusters, apply=True, actor="MOTOR_SCI")
    by_res = {p.resource_id: p for p in proposals}

    # La Fuerza de Tarea USAR debe ir al incidente verificado #10, nunca al no verificado #20
    assert by_res[usar.id].cluster_id == 10
    # La unidad rápida de reconocimiento cubre el clúster ciudadano #20
    assert by_res[recon.id].cluster_id == 20
    # Como el clúster #10 tiene severidad >= 7, la ambulancia sobrante se asigna como refuerzo a #10
    assert by_res[amb.id].cluster_id == 10

    assert console.get_resource(usar.id).status == ResourceStatus.ASIGNADO
    assert console.get_or_create_incident(10).status == IncidentLifecycleStatus.EN_ATENCION
    assert console.get_or_create_incident(20).status == IncidentLifecycleStatus.EN_ATENCION


def test_console_assign_reassign_release_and_incident_lifecycle():
    console = DispatchConsole()
    amb = console.register_resource(
        code="AMB-10",
        name="Ambulancia Cruz Roja",
        resource_class=ResourceClass.RECURSO_SIMPLE,
        resource_type=2,
        category=ResourceCategory.MEDICO,
        lat=20.14,
        lon=-101.18,
    )

    # 1. Asignar a incidente #100 -> pasa de PENDIENTE a EN_ATENCION
    console.assign_resource(
        resource_id=amb.id,
        cluster_id=100,
        actor="CMD_GORDILLO",
        reason="Herido confirmado",
        cluster_lat=20.142,
        cluster_lon=-101.182,
    )
    inc100 = console.get_or_create_incident(100)
    assert inc100.status == IncidentLifecycleStatus.EN_ATENCION
    assert amb.id in inc100.assigned_resource_ids

    # 2. Reasignar a incidente #200 -> libera #100 y atiende #200
    console.reassign_resource(
        resource_id=amb.id,
        target_cluster_id=200,
        actor="CMD_GORDILLO",
        reason="Mayor prioridad en zona norte",
        target_lat=20.150,
        target_lon=-101.185,
    )
    assert console.get_resource(amb.id).assigned_cluster_id == 200
    assert inc100.status == IncidentLifecycleStatus.PENDIENTE
    assert console.get_or_create_incident(200).status == IncidentLifecycleStatus.EN_ATENCION

    # 3. Cerrar incidente #200 como RESUELTO -> fija closed_at y libera automáticamente la ambulancia
    closed = console.update_incident_status(
        cluster_id=200,
        new_status=IncidentLifecycleStatus.RESUELTO,
        actor="CMD_GORDILLO",
        notes="Víctima trasladada a hospital",
    )
    assert closed.status == IncidentLifecycleStatus.RESUELTO
    assert closed.closed_at is not None
    assert closed.assigned_resource_ids == []
    assert console.get_resource(amb.id).status == ResourceStatus.DISPONIBLE

    # 4. Verificar bitácora de auditoría
    audits = console.list_audit_log(actor="CMD_GORDILLO")
    actions = [a.action for a in audits]
    assert "ASIGNAR_RECURSO" in actions
    assert "REASIGNAR_RECURSO" in actions
    assert "CAMBIO_ESTADO_INCIDENTE" in actions


def test_api_endpoints_for_dispatch_and_audit():
    dispatch_console.reset()
    client = TestClient(app)

    # 1. Check-in de recurso SCI-211
    res_resp = client.post(
        "/resources",
        json={
            "code": "BOMB-01",
            "name": "Motobomba Tipo 1",
            "resource_class": "EQUIPO_INTERVENCION",
            "resource_type": 1,
            "category": "BOMBEROS",
            "lat": 20.14,
            "lon": -101.18,
            "actor": "OPERADOR_SCI",
        },
    )
    assert res_resp.status_code == 201
    res_id = res_resp.json()["id"]

    # 2. Registrar bloqueo vial y consultar ruta
    rb_resp = client.post(
        "/roadblocks",
        json={
            "lat": 20.145,
            "lon": -101.18,
            "radius_m": 75.0,
            "severity": 8,
            "description": "Escombros en vía",
        },
    )
    assert rb_resp.status_code == 201
    block_id = rb_resp.json()["id"]

    route_resp = client.get(
        "/dispatch/route",
        params={
            "origin_lat": 20.14,
            "origin_lon": -101.18,
            "dest_lat": 20.15,
            "dest_lon": -101.18,
        },
    )
    assert route_resp.status_code == 200
    assert route_resp.json()["status"] == "DESVIO_POR_BLOQUEO"

    # 3. Asignar y luego liberar recurso
    assign_resp = client.post(
        "/dispatch/assign",
        json={
            "resource_id": res_id,
            "cluster_id": 77,
            "actor": "COMANDANTE_PC",
            "reason": "Incendio activo",
            "cluster_lat": 20.15,
            "cluster_lon": -101.18,
        },
    )
    assert assign_resp.status_code == 200
    assert assign_resp.json()["incident"]["status"] == "EN_ATENCION"

    release_resp = client.post(
        "/dispatch/release",
        json={"resource_id": res_id, "actor": "COMANDANTE_PC", "reason": "Fuego controlado"},
    )
    assert release_resp.status_code == 200
    assert release_resp.json()["resource"]["status"] == "DISPONIBLE"

    # 4. Marcar incidente como FALSA_ALARMA y verificar closed_at
    inc_resp = client.patch(
        "/incidents/77/status",
        json={"status": "FALSA_ALARMA", "actor": "COMANDANTE_PC", "notes": "Humo de cocina"},
    )
    assert inc_resp.status_code == 200
    assert inc_resp.json()["closed_at"] is not None

    # 5. Eliminar bloqueo vial y consultar bitácora de auditoría
    del_rb = client.delete(f"/roadblocks/{block_id}")
    assert del_rb.status_code == 200
    assert del_rb.json()["active"] is False

    audit_resp = client.get("/dispatch/audit", params={"cluster_id": 77})
    assert audit_resp.status_code == 200
    assert len(audit_resp.json()) >= 3
