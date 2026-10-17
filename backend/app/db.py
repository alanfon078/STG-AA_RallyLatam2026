from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from .config import settings

engine: Engine = create_engine(settings.database_url, pool_pre_ping=True)

SCHEMA = (
    "CREATE EXTENSION IF NOT EXISTS postgis",
    """
    CREATE TABLE IF NOT EXISTS reports (
        id BIGSERIAL PRIMARY KEY,
        node_id INTEGER NOT NULL,
        seq INTEGER NOT NULL,
        node_time BIGINT NOT NULL,
        flags SMALLINT NOT NULL,
        kind SMALLINT NOT NULL,
        severity SMALLINT NOT NULL,
        affected INTEGER NOT NULL,
        received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        geom geometry(Point, 4326) NOT NULL,
        UNIQUE (node_id, seq, node_time)
    )
    """,
    "CREATE INDEX IF NOT EXISTS reports_geom_idx ON reports USING GIST (geom)",
    "CREATE INDEX IF NOT EXISTS reports_received_idx ON reports (received_at)",
    """
    CREATE TABLE IF NOT EXISTS resources (
        id BIGSERIAL PRIMARY KEY,
        code VARCHAR(64) NOT NULL UNIQUE,
        name VARCHAR(128) NOT NULL,
        resource_class VARCHAR(32) NOT NULL,
        resource_type SMALLINT NOT NULL CHECK (resource_type BETWEEN 1 AND 4),
        category VARCHAR(32) NOT NULL,
        status VARCHAR(32) NOT NULL,
        speed_kmh DOUBLE PRECISION NOT NULL DEFAULT 45.0,
        capacity INTEGER NOT NULL DEFAULT 4,
        assigned_cluster_id BIGINT NULL,
        leader VARCHAR(128) NULL,
        subordinates_count INTEGER NOT NULL DEFAULT 0,
        geom geometry(Point, 4326) NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS road_blocks (
        id BIGSERIAL PRIMARY KEY,
        radius_m DOUBLE PRECISION NOT NULL DEFAULT 60.0,
        severity SMALLINT NOT NULL CHECK (severity BETWEEN 1 AND 10),
        description TEXT NOT NULL DEFAULT '',
        active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        geom geometry(Point, 4326) NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS incident_states (
        cluster_id BIGINT PRIMARY KEY,
        status VARCHAR(32) NOT NULL DEFAULT 'PENDIENTE',
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        closed_at TIMESTAMPTZ NULL,
        notes TEXT NOT NULL DEFAULT '',
        commander VARCHAR(128) NOT NULL DEFAULT 'COMANDANTE_PC'
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS dispatch_audit (
        id BIGSERIAL PRIMARY KEY,
        timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
        actor VARCHAR(128) NOT NULL,
        action VARCHAR(64) NOT NULL,
        resource_id BIGINT NULL,
        cluster_id BIGINT NULL,
        previous_state VARCHAR(64) NULL,
        new_state VARCHAR(64) NULL,
        details TEXT NOT NULL DEFAULT ''
    )
    """,
)


def init_db() -> None:
    with engine.begin() as conn:
        for statement in SCHEMA:
            conn.execute(text(statement))

