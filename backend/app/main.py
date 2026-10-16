import logging
from contextlib import asynccontextmanager
from dataclasses import asdict

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .config import settings
from .db import init_db
from .ingest import SerialIngest, ingest_hex
from .repository import fetch_reports
from .service import build_clusters

logging.basicConfig(level=logging.INFO)


class FrameIn(BaseModel):
    hex: str


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
    return [asdict(c) for c in build_clusters(reports, settings.cluster_radius_m)]
