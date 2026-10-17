# STG-AA

**Sistema de Triaje Georreferenciado y Asignación Algorítmica.** Equipo *404 skill not found* (ITSUR).

Prototipo ligero para demostración en vivo del **Desafío 09 (Rally Latinoamericano de Innovación 2026)**:
1. **Nivel 1 — Portal Cautivo Ciudadano (`SOS_MUNICIPIO`):** Captura avisos ciudadanos sin internet ni apps instaladas.
2. **Nivel 2 — App Táctica del Brigadista (Mock SCI / Triaje START):** Verificación en campo con bandera `FLAG_BRIGADISTA`.
3. **Puesto de Comando:** Servidor FastAPI con **Clustering Espacial DBSCAN** y **Puntaje de Urgencia (0–100)** que distingue entre `RECONOCIMIENTO` (alta incertidumbre ciudadana) y `FUERZA_TAREA` (triaje confirmado).

---

## Estructura del Repositorio

```
stg-aa/
├── backend/                  Servidor FastAPI en memoria, clustering DBSCAN y simulador
│   ├── app/
│   │   ├── frame.py          Empaquetado binario de 25 bytes + CRC16-CCITT
│   │   ├── clustering.py     Agrupamiento espacial DBSCAN con distancia Haversine
│   │   ├── scoring.py        Fórmula de Puntaje de Urgencia y recomendación SCI
│   │   ├── service.py        Construcción y ordenamiento de clústeres
│   │   ├── repository.py     Almacenamiento ligero en memoria con deduplicación
│   │   ├── main.py              API REST y servidor del Dashboard
│   │   └── static/dashboard.html Dashboard interactivo del Puesto de Comando (SCI)
│   ├── sim/simulator.py      Simulador por línea de comandos
│   └── tests/                Pruebas unitarias automatizadas (pytest)
└── firmware/                 PlatformIO (Heltec WiFi LoRa 32 V3: ESP32-S3 + SX1262)
    ├── src/                  Nodo (portal cautivo + relevo mesh) y Gateway USB
    ├── include/              Trama binaria C++ (25 bytes) y configuración LoRa 915 MHz
    ├── data/index.html       Formulario web del portal cautivo (LittleFS)
    └── tools/frame_check.cpp Verifica paridad binaria C++ vs Python
```

---

## Ejecución Rápida del Prototipo (Sin Docker)

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\activate
pip install -e ".[dev]"

pytest
uvicorn app.main:app --reload
```

Abre en tu navegador: **`http://localhost:8000`**

Verás en una sola pantalla los **3 Mocks interactivos**:
1. **Celular del Ciudadano (`SOS_MUNICIPIO`):** Envía reportes individuales o simula una ráfaga de 18 alertas vecinas para ver cómo DBSCAN las agrupa en un único clúster en estado `RECONOCIMIENTO` (evitando desviar ambulancias por falsas alarmas).
2. **Celular del Brigadista (Triaje START SCI-207):** Registra víctimas por color (Rojo, Amarillo, Verde, Negro) y transmite el dictamen verificado (`FLAG_BRIGADISTA`), elevando el clúster a `FUERZA_TAREA`.
3. **Centro de Control (Puesto de Comando):** Visualiza la trama binaria real de 25 bytes en hexadecimal, el mapa táctico de clústeres y la cola priorizada por urgencia.

---

## Trama Binaria LoRa (25 bytes, little-endian)

| Offset | Tamaño | Campo |
| ---: | ---: | :--- |
| 0 | 1 | versión (`1`) |
| 1 | 1 | flags (`bit0` brigadista/SCI, `bit1` prioridad) |
| 2 | 1 | tipo (`0` derrumbe, `1` persona atrapada, `2` inundación, `3` incendio, `4` herido grave) |
| 3 | 1 | ttl |
| 4 | 2 | `node_id` |
| 6 | 2 | `seq` |
| 8 | 4 | `node_time` |
| 12 | 4 | latitud × $10^6$ (con signo) |
| 16 | 4 | longitud × $10^6$ (con signo) |
| 20 | 1 | severidad (`0` a `10`) |
| 21 | 2 | personas afectadas |
| 23 | 2 | `CRC16-CCITT` de los bytes `0` a `22` |
