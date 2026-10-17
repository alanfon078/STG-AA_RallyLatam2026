import logging
from contextlib import asynccontextmanager
from dataclasses import asdict

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from .allocation import (
    IncidentLifecycleStatus,
    ResourceCategory,
    ResourceClass,
    ResourceStatus,
    dispatch_console,
    estimate_route,
)
from .config import settings
from .db import init_db
from .ingest import SerialIngest, ingest_hex
from .repository import fetch_reports
from .service import build_clusters

logging.basicConfig(level=logging.INFO)


class FrameIn(BaseModel):
    hex: str


class ResourceCreateIn(BaseModel):
    code: str
    name: str
    resource_class: ResourceClass = ResourceClass.RECURSO_SIMPLE
    resource_type: int = Field(default=2, ge=1, le=4)
    category: ResourceCategory
    lat: float = Field(ge=-90.0, le=90.0)
    lon: float = Field(ge=-180.0, le=180.0)
    status: ResourceStatus = ResourceStatus.DISPONIBLE
    speed_kmh: float = Field(default=45.0, gt=0.0)
    capacity: int = Field(default=4, ge=1)
    leader: str | None = None
    subordinates_count: int = Field(default=0, ge=0)
    actor: str = "COMANDANTE_PC"


class ResourceUpdateIn(BaseModel):
    status: ResourceStatus | None = None
    lat: float | None = Field(default=None, ge=-90.0, le=90.0)
    lon: float | None = Field(default=None, ge=-180.0, le=180.0)
    actor: str = "COMANDANTE_PC"
    reason: str = ""


class RoadBlockCreateIn(BaseModel):
    lat: float = Field(ge=-90.0, le=90.0)
    lon: float = Field(ge=-180.0, le=180.0)
    radius_m: float = Field(default=60.0, gt=0.0)
    severity: int = Field(default=8, ge=1, le=10)
    description: str = ""
    actor: str = "COMANDANTE_PC"


class DispatchAssignIn(BaseModel):
    resource_id: int
    cluster_id: int
    actor: str = "COMANDANTE_PC"
    reason: str = ""
    cluster_lat: float | None = None
    cluster_lon: float | None = None


class DispatchReassignIn(BaseModel):
    resource_id: int
    target_cluster_id: int
    actor: str = "COMANDANTE_PC"
    reason: str = ""
    target_lat: float | None = None
    target_lon: float | None = None


class DispatchReleaseIn(BaseModel):
    resource_id: int
    actor: str = "COMANDANTE_PC"
    reason: str = "Misión completada"


class DispatchOptimizeIn(BaseModel):
    apply: bool = False
    actor: str = "MOTOR_ALGORITMICO"
    clusters: list[dict] | None = None


class IncidentStatusUpdateIn(BaseModel):
    status: IncidentLifecycleStatus
    actor: str = "COMANDANTE_PC"
    notes: str = ""


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    reader = None
    if settings.serial_port:
        reader = SerialIngest(settings.serial_port, settings.serial_baud)
        reader.start()
    yield
    if reader:
        reader.stop()


app = FastAPI(title="STG-AA Servidor Tactico", lifespan=lifespan)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/ingest/frame")
def ingest_frame(body: FrameIn) -> dict:
    try:
        frame, created = ingest_hex(body.hex)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {
        "stored": created,
        "node_id": frame.node_id,
        "seq": frame.seq,
        "verified": frame.verified,
    }


@app.get("/clusters")
def clusters() -> list[dict]:
    reports = fetch_reports(settings.cluster_window_min)
    built = [asdict(c) for c in build_clusters(reports, settings.cluster_radius_m)]
    for c in built:
        inc = dispatch_console.get_or_create_incident(int(c["id"]))
        c["lifecycle_status"] = inc.status.value
        c["closed_at"] = inc.closed_at
        c["assigned_resource_ids"] = list(inc.assigned_resource_ids)
    return built


# --- Recursos SCI-211 ---


@app.post("/resources", status_code=201)
def create_resource(body: ResourceCreateIn) -> dict:
    try:
        res = dispatch_console.register_resource(
            code=body.code,
            name=body.name,
            resource_class=body.resource_class,
            resource_type=body.resource_type,
            category=body.category,
            lat=body.lat,
            lon=body.lon,
            status=body.status,
            speed_kmh=body.speed_kmh,
            capacity=body.capacity,
            leader=body.leader,
            subordinates_count=body.subordinates_count,
            actor=body.actor,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return asdict(res)


@app.get("/resources")
def get_resources(
    status: ResourceStatus | None = None,
    category: ResourceCategory | None = None,
    resource_class: ResourceClass | None = None,
    resource_type: int | None = Query(default=None, ge=1, le=4),
) -> list[dict]:
    items = dispatch_console.list_resources(
        status=status,
        category=category,
        resource_class=resource_class,
        resource_type=resource_type,
    )
    return [asdict(r) for r in items]


@app.patch("/resources/{resource_id}")
def patch_resource(resource_id: int, body: ResourceUpdateIn) -> dict:
    try:
        res = dispatch_console.update_resource(
            resource_id=resource_id,
            status=body.status,
            lat=body.lat,
            lon=body.lon,
            actor=body.actor,
            reason=body.reason,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return asdict(res)


# --- Bloqueos Viales y Ruteo/ETA ---


@app.post("/roadblocks", status_code=201)
def create_roadblock(body: RoadBlockCreateIn) -> dict:
    block = dispatch_console.add_road_block(
        lat=body.lat,
        lon=body.lon,
        radius_m=body.radius_m,
        severity=body.severity,
        description=body.description,
        actor=body.actor,
    )
    return asdict(block)


@app.get("/roadblocks")
def get_roadblocks(active_only: bool = True) -> list[dict]:
    return [asdict(b) for b in dispatch_console.list_road_blocks(active_only=active_only)]


@app.delete("/roadblocks/{block_id}")
def delete_roadblock(block_id: int, actor: str = "COMANDANTE_PC") -> dict:
    try:
        block = dispatch_console.remove_road_block(block_id=block_id, actor=actor)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return asdict(block)


@app.get("/dispatch/route")
def calculate_route(
    origin_lat: float = Query(ge=-90.0, le=90.0),
    origin_lon: float = Query(ge=-180.0, le=180.0),
    dest_lat: float = Query(ge=-90.0, le=90.0),
    dest_lon: float = Query(ge=-180.0, le=180.0),
    speed_kmh: float = Query(default=45.0, gt=0.0),
) -> dict:
    est = estimate_route(
        origin_lat=origin_lat,
        origin_lon=origin_lon,
        dest_lat=dest_lat,
        dest_lon=dest_lon,
        speed_kmh=speed_kmh,
        road_blocks=dispatch_console.list_road_blocks(active_only=True),
    )
    return asdict(est)


# --- Consola de Despacho y Optimización ---


@app.post("/dispatch/optimize")
def optimize_dispatch(body: DispatchOptimizeIn) -> list[dict]:
    target_clusters = body.clusters
    if target_clusters is None:
        reports = fetch_reports(settings.cluster_window_min)
        target_clusters = [
            asdict(c) for c in build_clusters(reports, settings.cluster_radius_m)
        ]
    proposals = dispatch_console.optimize_and_dispatch(
        clusters=target_clusters,
        apply=body.apply,
        actor=body.actor,
    )
    return [asdict(p) for p in proposals]


@app.post("/dispatch/assign")
def assign_dispatch(body: DispatchAssignIn) -> dict:
    try:
        result = dispatch_console.assign_resource(
            resource_id=body.resource_id,
            cluster_id=body.cluster_id,
            actor=body.actor,
            reason=body.reason,
            cluster_lat=body.cluster_lat,
            cluster_lon=body.cluster_lon,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {
        "resource": asdict(result["resource"]),
        "incident": asdict(result["incident"]),
        "route": asdict(result["route"]) if result["route"] else None,
        "audit": asdict(result["audit"]),
    }


@app.post("/dispatch/reassign")
def reassign_dispatch(body: DispatchReassignIn) -> dict:
    try:
        result = dispatch_console.reassign_resource(
            resource_id=body.resource_id,
            target_cluster_id=body.target_cluster_id,
            actor=body.actor,
            reason=body.reason,
            target_lat=body.target_lat,
            target_lon=body.target_lon,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {
        "resource": asdict(result["resource"]),
        "previous_cluster_id": result["previous_cluster_id"],
        "incident": asdict(result["incident"]),
        "route": asdict(result["route"]) if result["route"] else None,
        "audit": asdict(result["audit"]),
    }


@app.post("/dispatch/release")
def release_dispatch(body: DispatchReleaseIn) -> dict:
    try:
        result = dispatch_console.release_resource(
            resource_id=body.resource_id,
            actor=body.actor,
            reason=body.reason,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {
        "resource": asdict(result["resource"]),
        "released_from_cluster_id": result["released_from_cluster_id"],
        "audit": asdict(result["audit"]),
    }


# --- Ciclo de Vida de Incidentes y Auditoría ---


@app.get("/incidents")
def list_incidents(status: IncidentLifecycleStatus | None = None) -> list[dict]:
    return [asdict(i) for i in dispatch_console.list_incidents(status=status)]


@app.patch("/incidents/{cluster_id}/status")
def patch_incident_status(cluster_id: int, body: IncidentStatusUpdateIn) -> dict:
    inc = dispatch_console.update_incident_status(
        cluster_id=cluster_id,
        new_status=body.status,
        actor=body.actor,
        notes=body.notes,
    )
    return asdict(inc)


@app.get("/dispatch/audit")
def get_dispatch_audit(
    cluster_id: int | None = None,
    resource_id: int | None = None,
    actor: str | None = None,
    action: str | None = None,
) -> list[dict]:
    entries = dispatch_console.list_audit_log(
        cluster_id=cluster_id,
        resource_id=resource_id,
        actor=actor,
        action=action,
    )
    return [asdict(e) for e in entries]
