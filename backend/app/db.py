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
)


def init_db() -> None:
    with engine.begin() as conn:
        for statement in SCHEMA:
            conn.execute(text(statement))
