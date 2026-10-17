# TASK.md — Alcance del Prototipo Simulado (Rally Latam 2026)

> [!IMPORTANT]
> **Enfoque del Rally:**
> - Código limpio, modular y muy fácil de explicar ante el jurado.
> - Ejecución 100% local en memoria sin depender de Docker ni servicios pesados.
> - Demostración interactiva mediante Mocks visuales que conectan con el algoritmo real de empaquetado binario (25 bytes), clustering espacial (DBSCAN) y priorización SCI.

## Estado del Mini-Prototipo

- [X] **Protocolo Binario LoRa (25 bytes + CRC16-CCITT):** Paridad C++ (`firmware/include/frame.h`) y Python (`backend/app/frame.py`).
- [X] **Firmware ESP32 + SX1262 (`firmware/`):** Portal cautivo Wi-Fi `SOS_MUNICIPIO` (`portal.cpp` + `data/index.html`), relevo Mesh con TTL/deduplicación y Gateway USB (`main.cpp`).
- [X] **Motor Algorítmico (`backend/app/`):**
  - [X] Almacenamiento ligero en memoria con deduplicación (`repository.py`).
  - [X] Clustering espacial con `DBSCAN` y distancia Haversine a 80 m (`clustering.py`).
  - [X] Cálculo de Puntaje de Urgencia (0–100) y despacho en dos fases: `RECONOCIMIENTO` vs `FUERZA_TAREA` (`scoring.py`, `service.py`).
- [X] **Dashboard del Puesto de Comando y Mocks (`backend/app/static/dashboard.html`):**
  - [X] **Mock Nivel 1:** Celular Ciudadano conectado al Portal Cautivo `SOS_MUNICIPIO` + botón de ráfaga de 18 alertas.
  - [X] **Mock Nivel 2:** Celular del Brigadista en modo OLED Black con Triaje START (SCI-207: Rojo, Amarillo, Verde, Negro) y envío de dictamen verificado (`FLAG_BRIGADISTA`).
  - [X] **Mock Nivel 3:** Centro de Control (Puesto de Comando) con inspector de trama binaria en vivo, mapa táctico de clústeres y cola priorizada de despacho.
- [X] **Pruebas Unitarias (`backend/tests/`):** Validación de trama binaria, clustering y puntaje de urgencia.
