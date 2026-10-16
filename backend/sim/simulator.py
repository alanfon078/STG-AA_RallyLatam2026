import argparse
import math
import random
import time

import httpx

from app.frame import FLAG_BRIGADISTA, FLAG_PRIORITY, Frame

METERS_PER_DEGREE = 111_320.0


def jitter(lat: float, lon: float, radius_m: float, rng: random.Random) -> tuple[float, float]:
    angle = rng.uniform(0, 2 * math.pi)
    distance = radius_m * math.sqrt(rng.random())
    dlat = distance * math.cos(angle) / METERS_PER_DEGREE
    dlon = distance * math.sin(angle) / (METERS_PER_DEGREE * math.cos(math.radians(lat)))
    return lat + dlat, lon + dlon


class Sender:
    def __init__(self, url: str) -> None:
        self._client = httpx.Client(base_url=url, timeout=10)
        self._seq: dict[int, int] = {}

    def next_seq(self, node_id: int) -> int:
        self._seq[node_id] = self._seq.get(node_id, 0) + 1
        return self._seq[node_id]

    def send(self, frame: Frame) -> None:
        response = self._client.post("/ingest/frame", json={"hex": frame.encode().hex()})
        response.raise_for_status()

    def clusters(self) -> list[dict]:
        response = self._client.get("/clusters")
        response.raise_for_status()
        return response.json()


def citizen_burst(
    sender: Sender, rng: random.Random, lat: float, lon: float, count: int, kind: int
) -> None:
    for _ in range(count):
        node_id = rng.randint(1, 5)
        point_lat, point_lon = jitter(lat, lon, 35.0, rng)
        sender.send(
            Frame(
                flags=0,
                kind=kind,
                node_id=node_id,
                seq=sender.next_seq(node_id),
                node_time=int(time.time()) & 0xFFFFFFFF,
                lat=point_lat,
                lon=point_lon,
                affected=rng.randint(1, 6),
            )
        )


def verified_report(sender: Sender, lat: float, lon: float) -> None:
    node_id = 900
    sender.send(
        Frame(
            flags=FLAG_BRIGADISTA | FLAG_PRIORITY,
            kind=0,
            node_id=node_id,
            seq=sender.next_seq(node_id),
            node_time=int(time.time()) & 0xFFFFFFFF,
            lat=lat,
            lon=lon,
            severity=9,
            affected=4,
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Simulador de nodos STG-AA")
    parser.add_argument("--url", default="http://localhost:8000")
    parser.add_argument("--lat", type=float, default=20.14)
    parser.add_argument("--lon", type=float, default=-101.18)
    parser.add_argument("--citizens", type=int, default=18)
    parser.add_argument("--far-citizens", type=int, default=3)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    sender = Sender(args.url)

    citizen_burst(sender, rng, args.lat, args.lon, args.citizens, kind=0)
    far_lat, far_lon = args.lat + 0.02, args.lon + 0.02
    citizen_burst(sender, rng, far_lat, far_lon, args.far_citizens, kind=2)
    if args.verify:
        verified_report(sender, args.lat, args.lon)

    for cluster in sender.clusters():
        print(
            f"cluster {cluster['id']:>4}  reportes={cluster['report_count']:>3}  "
            f"verificado={cluster['verified']!s:<5}  urgencia={cluster['urgency']:>5}  "
            f"-> {cluster['recommendation']}"
        )


if __name__ == "__main__":
    main()
