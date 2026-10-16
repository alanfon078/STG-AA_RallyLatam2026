# STG-AA

Sistema de Triaje Georreferenciado y Asignación Algorítmica. Equipo 404 skill not found.

## Estructura

```
stg-aa/
├── docker-compose.yml        PostgreSQL 16 + PostGIS 3
├── backend/                  FastAPI, clustering, puntaje de urgencia, simulador
│   ├── app/
│   ├── sim/
│   └── tests/
└── firmware/                 PlatformIO (Heltec WiFi LoRa 32 V3: ESP32-S3 + SX1262)
    ├── src/                  nodo (portal + relevo) y gateway
    ├── include/              trama binaria y configuración
    ├── data/index.html       formulario del portal cautivo (LittleFS)
    └── tools/frame_check.cpp compara la trama de C++ contra la de Python
```

## Backend

```bash
docker compose up -d db

cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env

pytest
uvicorn app.main:app --reload
```

En otra terminal, con el servidor corriendo:

```bash
python -m sim.simulator
python -m sim.simulator --verify
```

El primer comando envía 18 alertas ciudadanas en un mismo punto y 3 en otro; el segundo agrega un dictamen verificado y el clúster pasa de `RECONOCIMIENTO` a `FUERZA_TAREA`. El resultado también está en `GET /clusters` y la documentación interactiva en `/docs`.

Para conectar el Gateway real, define `STG_SERIAL_PORT` (por ejemplo `/dev/ttyUSB0` o `COM5`) en `.env`. El gateway imprime una línea `FRAME <hex>` por cada trama válida.

## Firmware

Requiere VS Code con la extensión PlatformIO.

```bash
cd firmware
pio run -e node -t upload
pio run -e node -t uploadfs
pio run -e gateway -t upload
```

Cada nodo necesita un `NODE_ID` distinto (en `platformio.ini`) y las coordenadas aproximadas de su ubicación fija (`NODE_LAT_E6`, `NODE_LON_E6`), que se usan cuando el teléfono del ciudadano no entrega ubicación.

Verificación de la trama sin hardware:

```bash
g++ -std=c++17 -o tools/frame_check tools/frame_check.cpp && ./tools/frame_check
```

La salida debe ser idéntica a `GOLDEN_HEX` en `backend/tests/test_frame.py`.

## Trama binaria (25 bytes, little-endian)

| Offset | Tamaño | Campo |
| ---: | ---: | :--- |
| 0 | 1 | versión |
| 1 | 1 | flags (bit0 brigadista/SCI, bit1 prioridad) |
| 2 | 1 | tipo (0 derrumbe, 1 persona atrapada, 2 inundación, 3 incendio, 4 herido grave) |
| 3 | 1 | ttl |
| 4 | 2 | node_id |
| 6 | 2 | seq |
| 8 | 4 | node_time |
| 12 | 4 | latitud × 1e6 (con signo) |
| 16 | 4 | longitud × 1e6 (con signo) |
| 20 | 1 | severidad (0 a 10) |
| 21 | 2 | personas afectadas |
| 23 | 2 | CRC16-CCITT de los bytes 0 a 22 |

El ttl se modifica en cada salto, por lo que cada relevo recalcula el CRC. La deduplicación usa `(node_id, seq)`.

## Pendiente

- Cifrado simétrico de la trama (AES con `mbedtls`)
- App móvil Flutter y enlace BLE al nodo portátil
- Dashboard del Puesto de Comando
- Vulnerabilidad de zona y penalización vial en el puntaje de urgencia (hoy son parámetros en cero)
