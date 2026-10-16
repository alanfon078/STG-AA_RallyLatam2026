import logging
import threading

import serial

from .frame import Frame
from .repository import insert_report

log = logging.getLogger("stg.ingest")

FRAME_PREFIX = "FRAME "


def ingest_hex(text: str) -> tuple[Frame, bool]:
    frame = Frame.decode(bytes.fromhex(text.strip()))
    return frame, insert_report(frame)


class SerialIngest:
    def __init__(self, port: str, baud: int) -> None:
        self._port = port
        self._baud = baud
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="serial-ingest", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=3)

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                with serial.Serial(self._port, self._baud, timeout=1) as conn:
                    log.info("gateway conectado en %s", self._port)
                    self._read(conn)
            except serial.SerialException as exc:
                log.warning("gateway no disponible (%s), reintentando", exc)
                self._stop.wait(2)

    def _read(self, conn: serial.Serial) -> None:
        while not self._stop.is_set():
            line = conn.readline().decode("ascii", errors="ignore").strip()
            if not line.startswith(FRAME_PREFIX):
                continue
            try:
                frame, created = ingest_hex(line[len(FRAME_PREFIX):])
            except ValueError as exc:
                log.warning("trama descartada: %s", exc)
                continue
            log.info("trama node=%s seq=%s nueva=%s", frame.node_id, frame.seq, created)
