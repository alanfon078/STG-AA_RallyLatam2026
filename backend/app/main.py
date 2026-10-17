import logging
import random
import time
from contextlib import asynccontextmanager
from dataclasses import asdict
from pathlib import Path
from urllib.parse import parse_qs

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from .config import settings
from .frame import FLAG_BRIGADISTA, FLAG_PRIORITY, Frame
from .ingest import SerialIngest, ingest_hex
from .repository import clear_reports, fetch_reports, get_last_frame_hex
from .service import build_clusters

logging.basicConfig(level=logging.INFO)

DASHBOARD_HTML_PATH = Path(__file__).parent / "static" / "dashboard.html"
PORTAL_HTML_PATH = Path(__file__).resolve().parents[2] / "firmware" / "data" / "index.html"
_seq_counter = 0


def _next_seq() -> int:
    global _seq_counter
    _seq_counter = (_seq_counter % 65535) + 1
    return _seq_counter


class FrameIn(BaseModel):
    hex: str


class DemoReportIn(BaseModel):
    lat: float = Field(default=20.140, ge=-90.0, le=90.0)
    lon: float = Field(default=-101.180, ge=-180.0, le=180.0)
    kind: int = Field(default=0, ge=0, le=4)
    affected: int = Field(default=1, ge=0, le=999)
    verified: bool = False
    severity: int = Field(default=0, ge=0, le=10)


def _seed_initial_data() -> None:
    """Carga un escenario operativo inicial para el Puesto de Comando."""
    if fetch_reports(settings.cluster_window_min):
        return
    rng = random.Random(42)
    now = int(time.time()) & 0xFFFFFFFF

    # Zona 1: Centro (12 reportes ciudadanos + 1 verificación de Brigadista SCI)
    for _ in range(12):
        f = Frame(
            flags=0, kind=0, node_id=rng.randint(1, 3), seq=_next_seq(), node_time=now,
            lat=20.1410 + rng.uniform(-0.0002, 0.0002),
            lon=-101.1790 + rng.uniform(-0.0002, 0.0002),
            affected=rng.randint(2, 5),
        )
        ingest_hex(f.encode().hex())
    f_sci = Frame(
        flags=FLAG_BRIGADISTA | FLAG_PRIORITY, kind=0, node_id=901, seq=_next_seq(),
        node_time=now, lat=20.1410, lon=-101.1790, severity=9, affected=6,
    )
    ingest_hex(f_sci.encode().hex())

    # Zona 2: Sector Sur (15 reportes ciudadanos sin verificar -> Reconocimiento)
    for _ in range(15):
        f = Frame(
            flags=0, kind=2, node_id=rng.randint(2, 4), seq=_next_seq(), node_time=now,
            lat=20.1355 + rng.uniform(-0.0002, 0.0002),
            lon=-101.1845 + rng.uniform(-0.0002, 0.0002),
            affected=rng.randint(1, 4),
        )
        ingest_hex(f.encode().hex())

    # Zona 3: Sector Oriente (4 reportes ciudadanos sin verificar -> Reconocimiento)
    for _ in range(4):
        f = Frame(
            flags=0, kind=1, node_id=rng.randint(3, 5), seq=_next_seq(), node_time=now,
            lat=20.1475 + rng.uniform(-0.00015, 0.00015),
            lon=-101.1710 + rng.uniform(-0.00015, 0.00015),
            affected=rng.randint(1, 3),
        )
        ingest_hex(f.encode().hex())


@asynccontextmanager
async def lifespan(_: FastAPI):
    _seed_initial_data()
    reader = None
    if settings.serial_port:
        reader = SerialIngest(settings.serial_port, settings.serial_baud)
        reader.start()
    yield
    if reader:
        reader.stop()


_seed_initial_data()
app = FastAPI(title="STG-AA Servidor Tactico (Prototipo Rally)", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", response_class=HTMLResponse)
@app.get("/dashboard", response_class=HTMLResponse)
def dashboard_ui() -> str:
    return DASHBOARD_HTML_PATH.read_text(encoding="utf-8")


@app.get("/portal", response_class=HTMLResponse)
def portal_ui() -> str:
    return PORTAL_HTML_PATH.read_text(encoding="utf-8")


@app.post("/sos")
async def portal_sos(request: Request) -> dict:
    raw = (await request.body()).decode("utf-8")
    params = parse_qs(raw)
    kind = int(params.get("kind", ["0"])[0] or 0)
    affected = max(1, min(999, int(params.get("affected", ["1"])[0] or 1)))
    lat_raw = params.get("lat", [""])[0]
    lon_raw = params.get("lon", [""])[0]
    lat = float(lat_raw) if lat_raw else 20.1355
    lon = float(lon_raw) if lon_raw else -101.1845
    if abs(lat - 20.141) > 0.03 or abs(lon - (-101.179)) > 0.03:
        lat, lon = 20.1355, -101.1845
    frame = Frame(
        flags=0,
        kind=max(0, min(4, kind)),
        node_id=1,
        seq=_next_seq(),
        node_time=int(time.time()) & 0xFFFFFFFF,
        lat=lat,
        lon=lon,
        affected=affected,
    )
    ingest_hex(frame.encode().hex())
    return {"ok": True}


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
    return [asdict(c) for c in build_clusters(reports, settings.cluster_radius_m)]


@app.get("/demo/state")
def demo_state() -> dict:
    reports = fetch_reports(settings.cluster_window_min)
    return {
        "last_frame_hex": get_last_frame_hex(),
        "total_reports": len(reports),
        "clusters": [asdict(c) for c in build_clusters(reports, settings.cluster_radius_m)],
    }


@app.post("/demo/report")
def demo_report(body: DemoReportIn) -> dict:
    flags = (FLAG_BRIGADISTA | FLAG_PRIORITY) if body.verified else 0
    node_id = 900 if body.verified else 1
    frame = Frame(
        flags=flags,
        kind=body.kind,
        node_id=node_id,
        seq=_next_seq(),
        node_time=int(time.time()) & 0xFFFFFFFF,
        lat=body.lat,
        lon=body.lon,
        severity=body.severity if body.verified else 0,
        affected=body.affected,
    )
    _, stored = ingest_hex(frame.encode().hex())
    return {"stored": stored, "seq": frame.seq, "hex": frame.encode().hex()}


@app.post("/demo/simulate")
def demo_simulate() -> dict:
    rng = random.Random(int(time.time()))
    now = int(time.time()) & 0xFFFFFFFF
    sent = 0
    for _ in range(18):
        frame = Frame(
            flags=0,
            kind=0,
            node_id=rng.randint(1, 5),
            seq=_next_seq(),
            node_time=now,
            lat=20.140 + rng.uniform(-0.00025, 0.00025),
            lon=-101.180 + rng.uniform(-0.00025, 0.00025),
            affected=rng.randint(1, 5),
        )
        ingest_hex(frame.encode().hex())
        sent += 1

    for _ in range(3):
        frame = Frame(
            flags=0,
            kind=2,
            node_id=rng.randint(1, 5),
            seq=_next_seq(),
            node_time=now,
            lat=20.160 + rng.uniform(-0.0002, 0.0002),
            lon=-101.160 + rng.uniform(-0.0002, 0.0002),
            affected=rng.randint(1, 3),
        )
        ingest_hex(frame.encode().hex())
        sent += 1

    return {"sent": sent}


@app.post("/demo/reset")
def demo_reset() -> dict:
    clear_reports()
    return {"reset": True}
