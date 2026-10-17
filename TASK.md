# TASK.md — Pendientes de STG-AA

> [!IMPORTANT]
> **Regla para agentes (obligatoria):**
> - Cada feature debe de ser implementada en una rama de git nueva con el nombre de la feature
> - Cada tarea es un checkbox `- [ ]` (pendiente).
> - Al terminar de implementar una tarea, **cambia su marca a `- [X]`** en este mismo archivo, en el mismo cambio que la implementa.
> - Solo márcala `[X]` si el código está hecho **y verificado** (tests pasando o comprobación manual documentada). Si queda a medias, déjala `[ ]` y anota el avance al lado.
> - No borres tareas completadas; si surgen tareas nuevas, agrégalas en la sección correspondiente con su prioridad.
> - Antes de empezar a trabajar, revisa este archivo y elige primero las tareas P0.

Lista de lo que falta para que STG-AA sea un producto de calidad. Fuentes: `README.md`, informe `INFORME_ESTADO_Y_REVISION_STG_AA.md` y auditoría del código.

Prioridad: **P0** bloqueante / demo · **P1** necesario para producto · **P2** deseable.

## Ya implementado (referencia)

- [x] Trama binaria de 25 bytes + CRC16 (C++ y Python, vector dorado)
- [x] Portal cautivo `SOS_MUNICIPIO` (DNS + LittleFS + cola FreeRTOS)
- [x] Malla LoRa con relevo, TTL y deduplicación
- [x] Gateway USB (`FRAME <hex>`) e ingesta serial
- [x] API FastAPI (`/health`, `/ingest/frame`, `/clusters`) + PostGIS
- [x] Clustering DBSCAN (haversine) y despacho en dos fases
- [x] Simulador y pruebas unitarias (frame, clustering, scoring)

---

## 1. Dashboard web del Puesto de Comando — P0

- [ ] Frontend (Leaflet/MapLibre) que consuma `GET /clusters`
- [ ] Mapa con mapas base **offline** (MBTiles/PMTiles servidos localmente)
- [ ] Marcadores por urgencia (0–100) y color por recomendación (`RECONOCIMIENTO` / `FUERZA_TAREA`)
- [ ] Simbología SCI normada (PC, E, ACV, B, C, H1)
- [ ] Mapa de calor de avisos ciudadanos
- [ ] Cola de despacho ordenada por urgencia
- [ ] Panel de detalle del clúster (reportes, tipos, afectados, severidad)
- [ ] Actualización en vivo (WebSocket o SSE) en lugar de polling
- [ ] Indicadores de estado: gateway conectado, última trama recibida, nodos activos
- [ ] Accesibilidad y uso en laptop de campo (alto contraste, sin dependencias de CDN)

## 2. Puntaje de urgencia multicriterio — P0

- [ ] Tabla PostGIS de infraestructura crítica (hospitales, escuelas, asilos)
- [ ] Cálculo de `vulnerability` por clúster con consultas espaciales (hoy fijo en `0.0` en `service.py`)
- [ ] Tabla de vías/puentes bloqueados y cálculo de `road_penalty` (hoy fijo en `0.0`)
- [ ] Endpoints CRUD para reportar/liberar bloqueos viales
- [ ] Carga de capas GIS (GeoJSON/Shapefile) con script de importación
- [ ] Pruebas unitarias con los nuevos factores
- [ ] Hacer los pesos (`W_*`) configurables y documentar la fórmula

## 3. Motor de asignación de recursos — P1

- [ ] Modelo de recursos (SCI-211): clase, tipo 1–4, categoría, estado (*Disponible/Asignado/No disponible*)
- [ ] Algoritmo de asignación óptima N recursos ↔ M incidentes (voraz o programación lineal)
- [ ] Ruteo/ETA considerando bloqueos viales
- [ ] Consola de despacho: asignar, reasignar y liberar recursos
- [ ] Ciclo de vida del incidente: *Pendiente → En atención → Resuelto / Falsa alarma*, con hora de cierre
- [ ] Auditoría (quién/cuándo/qué) de cada decisión de despacho

## 4. App móvil para brigadistas (Flutter) — P1

- [X] Crear proyecto Flutter (`mobile/`) con arquitectura *Feature-First* y tema oscuro nativo **OLED Black (`#000000`)** para ahorro de batería
- [X] Configurar persistencia local reactiva *offline-first* en SQLite (`drift` / `sqflite`) con identificadores únicos compactos
- [X] `lib/services/ble_service.dart`: cliente BLE (`flutter_blue_plus`) con escaneo, emparejamiento, reconexión automática permanente y cola de transmisión hacia el nodo portátil
- [X] Servicio GATT BLE en el firmware del nodo portátil (`[env:portable]`): recibir tramas por BLE desde el smartphone, empaquetarlas y transmitirlas por LoRa (con Wi-Fi deshabilitado para cumplir `< 0.5 W`)
- [X] `lib/features/formularios_sci/`:
  - [X] **SCI-201:** resumen del incidente, asunción de mando, polígono/perímetro de seguridad y georreferenciación de instalaciones (`PC`, `E`, `ACV`, `B`, `C`, `H1`)
  - [X] **SCI-211:** registro y check-in de recursos por Clase, Tipo (1 a 4), Categoría y cambio de estado (*Disponible*, *Asignado*, *No Disponible*)
- [X] `lib/features/triaje/`:
  - [X] **SCI-207:** módulo de registro táctico de víctimas en el ACV por código de colores **START** (conteo y fichas de Rojo, Amarillo, Verde, Negro)
- [X] Módulo de reporte rápido de **bloqueos viales** y peligros en ruta georreferenciados
- [X] Flujo UX de **máximo 3 toques** para acciones críticas, botones grandes ($\ge 60 \times 60\text{ dp}$) para uso con guantes y dictado por voz offline
- [X] Cartografía vectorial offline (MBTiles / PMTiles locales) con visualización de clústeres, instalaciones SCI y bloqueos cercanos
- [X] Recepción de órdenes de despacho y alertas desde el Puesto de Comando vía LoRa $\rightarrow$ BLE (enlace descendente / *downlink*)
- [X] Cola local de reintento y confirmación de entrega (ACK) con indicador visual de estado de sincronización
- [X] Transferencia de mando digital cara a cara mediante código QR o proximidad BLE (CU-G05)
- [X] Alerta de alcance de control (3–7 subordinados, óptimo 5, CU-G03) en app y dashboard
- [X] Configuración de permisos en Android/iOS (BLE, ubicación en primer plano, almacenamiento) y generación de APK firmado para despliegue sin tienda


## 5. Seguridad — P0/P1

- [ ] **P0** Autenticación en la API (`/ingest/frame`, `/clusters`): hoy es pública sin credenciales
- [ ] **P0** Autenticar tramas de brigadista: hoy cualquiera con `flags=0x01` fuerza `FUERZA_TAREA` (HMAC o firma por nodo)
- [ ] **P1** Cifrado AES de la trama (`mbedtls` en ESP32 y `cryptography` en Python); no existe nada aún en el código, solo está en la propuesta
- [ ] **P1** Protección anti-replay (el nonce/contador debe sobrevivir reinicios)
- [ ] **P1** Gestión de claves: aprovisionamiento por nodo, rotación y revocación
- [ ] **P1** Límite de tasa y validación contra spam desde el portal cautivo abierto
- [ ] **P1** Secretos fuera del repo (credenciales `stg/stg` de `docker-compose.yml` y `config.py`), `.env.example` (el README lo menciona pero no existe)
- [ ] **P2** CORS/TLS para el dashboard local

## 6. Robustez del firmware y extensión del protocolo binario — P1

- [ ] **Extensión del protocolo binario (`< 200 bytes`):** hoy la trama fija de 25 bytes solo soporta un `kind` (0–4) y un `affected` general; definir tipos de paquete o extensión TLV/sub-tramas para transportar:
  - [ ] Desglose de triaje START (contadores Rojo, Amarillo, Verde, Negro) para SCI-207
  - [ ] Georreferenciación de instalaciones SCI (`PC`, `E`, `ACV`, `B`, `C`, `H1`) y perímetros para SCI-201
  - [ ] Estado y tipo de recursos (Clase, Tipo 1–4, Estado) para SCI-211
  - [ ] Reporte de bloqueo vial (coordenadas, severidad del bloqueo, radio afectado)
  - [ ] Órdenes de despacho y alertas descendentes (*downlink*: Puesto de Comando $\rightarrow$ Gateway $\rightarrow$ Nodos/Brigadistas)
- [ ] **Enlace descendente (Downlink) en Gateway y Nodos:** permitir que el Gateway lea tramas por puerto serial desde FastAPI y las transmita por LoRa hacia los brigadistas
- [ ] **Tercer perfil en `platformio.ini` (`[env:portable]`):** rol específico para el nodo portátil del brigadista (BLE activo + LoRa, sin AP Wi-Fi) diferenciado del nodo fijo/vehicular (`[env:node]`) y del receptor (`[env:gateway]`)
- [ ] **`firmware/src/power_management.cpp`:** implementar el módulo de gestión energética especificado en la arquitectura (control de modos *Deep-Sleep* / *Light-Sleep* para mantener consumo $< 0.5\text{ W}$, lectura ADC de voltaje de batería $\text{LiFePO}_4$ y estado de carga del panel solar de 5–10 W)
- [ ] Persistir `seq` en NVS: hoy `sequence` se reinicia a 0 en cada reboot y la deduplicación `(node_id, seq)` puede descartar reportes legítimos nuevos
- [ ] Incluir `node_time` (o un epoch de arranque) en la clave de deduplicación del nodo, igual que en la BD
- [ ] Manejar el desbordamiento de `seq` (uint16)
- [ ] Reloj real: `node_time = millis()/1000` no es hora real; sincronizar con GPS/RTC o con el gateway
- [ ] Evitar `delay()` bloqueante en el relevo (usar cola con temporizador) para no perder paquetes ni degradar el portal
- [ ] Respetar duty cycle y ajustar potencia/SF según normativa de la banda
- [ ] Configuración en campo de `NODE_ID` y coordenadas (portal admin + NVS/LittleFS) en lugar de `build_flags`
- [ ] Watchdog y recuperación automática ante fallos de radio (hoy se queda en `while(true)`)
- [ ] Telemetría: batería, RSSI/SNR, contador de saltos, uptime; tramas de diagnóstico/heartbeat
- [ ] Pruebas de alcance y de saturación de la malla (nodos reales)
- [ ] Soporte de múltiples gateways y de OTA firmado

## 7. Backend: calidad y escalabilidad — P1

- [ ] Diferenciar en el controlador de ingesta los flujos de reporte ciudadano (CU-C01 $\rightarrow$ clustering) vs. dictámenes SCI verificados (CU-C03 $\rightarrow$ actualización directa de estado de recursos, instalaciones, triaje START y bloqueos viales)
- [ ] Endpoint y cola de salida serial para emitir órdenes de despacho (*downlink*) a través del Gateway USB hacia la red Mesh
- [ ] Corregir `fetch_reports`: incluye todos los verificados sin límite de tiempo (`OR` en la consulta) y la ventana solo aplica a ciudadanos; definir regla de caducidad
- [ ] Persistir clústeres y su historial (hoy se recalculan en cada petición)
- [ ] Migraciones de BD (Alembic) en lugar de DDL en `init_db()`
- [ ] El arranque no debe fallar si la BD aún no está lista (reintentos + `/health` real con check de BD)
- [ ] Ingesta serial desacoplada de la API (proceso/servicio aparte) y métricas
- [ ] Validación estricta de coordenadas (descartar lat/lon `0,0` del nodo sin configurar)
- [ ] Rechazar o registrar tramas con `node_time` inconsistente
- [ ] Tipos de siniestro por escenario (sismo, inundación, incendio, huracán)
- [ ] Logging estructurado y observabilidad básica
- [ ] Dockerfile del backend y servicio en `docker-compose.yml` (hoy solo la BD)

## 8. Módulos por escenario — P2

- [ ] **Sismo** (CU-T01–T03): etiquetado estructural Verde/Amarillo/Rojo
- [ ] **Inundación** (CU-A01–A03): bombas de achique, cercos sanitarios
- [ ] **Incendio** (CU-I01–I03): vector de viento, brechas cortafuego
- [ ] **Huracán** (CU-H01–H03): víveres en refugios, orden de resguardo obligatorio

## 9. Sincronización con la nube — P2

- [ ] Servicio en segundo plano que replique clústeres a una API central
- [ ] Detección de enlace (4G/5G/satelital), cola con reintentos y resolución de conflictos
- [ ] Modo 100% offline como comportamiento por defecto

## 10. Hardware y energía — P2

- [ ] Diseño e impresión 3D de carcasas resistentes (IP/temperatura)
- [ ] Alimentación LiFePO4 con panel solar 5–10 W y circuito de carga
- [ ] Telemetría de batería y modos deep-sleep
- [ ] Pruebas térmicas y de campo

## 11. Pruebas y calidad — P0/P1

- [ ] **P0** Pruebas de integración API + PostGIS (contenedor de test) — hoy solo hay tests unitarios
- [ ] **P0** Pruebas de `repository.py`, `ingest.py` y `main.py` (sin cobertura actual)
- [ ] **P1** Pruebas unitarias de firmware con PlatformIO (`pio test`) en lugar de solo `frame_check`
- [ ] **P1** Automatizar `frame_check` vs `GOLDEN_HEX` en CI (hoy se compara a mano)
- [ ] **P1** CI (GitHub Actions): lint (`ruff`), tipos (`mypy`), `pytest`, build de ambos `env` de PlatformIO
- [ ] **P1** Pruebas de carga con el simulador (cientos de alertas y varios nodos)
- [ ] **P1** Pruebas de campo con smartphones reales (portal cautivo en Android/iOS)
- [ ] **P2** Pruebas end-to-end hardware-in-the-loop

## 12. Documentación y entrega — P1

- [ ] Crear `backend/.env.example` (referenciado en el README, inexistente)
- [ ] Corregir README para Windows (`.venv\Scripts\activate`, `COM5`) además de Linux/macOS
- [ ] **Alinear el Documento de Arquitectura del Software con el repositorio real:**
  - [ ] Completar e insertar la **Imagen 6 (Modelo de Datos Relacional adaptado al STG-AA)** en la sección 4.2 Vista de Datos (actualmente tiene el placeholder `(Nota: Aquí deberás insertar la Imagen 6...)`)
  - [ ] Unificar los nombres de archivos de la sección 4.3 Vista de Implementación (`wifi_captive.cpp`, `lora_mesh.cpp`, `src/gateway_listener.py`, `src/api/routes.py`, `src/algorithms/clustering.py`) con los nombres reales del repo (`portal.cpp`, `radio_link.cpp`, `app/ingest.py`, `app/main.py`, `app/clustering.py`)
  - [ ] Unificar menciones de `WatermelonDB` por `SQLite (drift / sqflite)`, `ESP-IDF / Meshtastic` por `Arduino Framework + RadioLib`, y eliminar la mención a `Node.js` en el backend (es 100% Python + FastAPI)
- [ ] Corregir el informe de estado: afirma que AES está "definido en la cabecera de trama", pero no existe en el código
- [ ] Manual de despliegue en campo (flasheo, configuración de nodos, gateway, puesto de comando)
- [ ] Manual de operación para comandante y brigadistas
- [ ] Documentación de API (OpenAPI completa) y del protocolo de trama versionado
- [ ] Plan de versionado de trama (`version` > 1) y compatibilidad hacia atrás
- [ ] Licencia, `CONTRIBUTING.md` y changelog

## 13. Calidad del algoritmo de clustering — P1

- [ ] Clustering incremental/por tipo de siniestro (hoy mezcla derrumbe e inundación si están a < 80 m)
- [ ] Ponderar por antigüedad del reporte (decaimiento temporal) y por `affected`, que hoy no entra al puntaje
- [ ] Usar `FLAG_PRIORITY` (hoy se transmite pero el backend lo ignora)
- [ ] Deduplicar avisos repetidos del mismo ciudadano/nodo para evitar inflar la densidad
- [ ] Calibrar `DENSITY_SATURATION` y `cluster_radius_m` con datos de simulación realistas
- [ ] Resultados de clustering estables entre peticiones (IDs de clúster consistentes, hoy `id = min(report.id)`)
- [ ] Manejo de clústeres que crecen por encadenamiento (efecto *chaining* de DBSCAN)
- [ ] Pruebas de propiedades y benchmarks con 10k+ reportes (`ball_tree` en cada request)

## 14. Experiencia del ciudadano (portal cautivo) — P1

- [ ] Confirmación de entrega real (ACK desde el gateway); hoy el portal dice "SOS enviado" aunque la trama nunca llegue
- [ ] Mensaje de estado cuando la cola está llena (503) con reintento automático
- [ ] Internacionalización (español/inglés/lenguas indígenas) y pictogramas
- [ ] Campo opcional de texto corto/teléfono de contacto
- [ ] Contador de espera y bloqueo de doble envío accidental
- [ ] Detección de portal cautivo en Android/iOS/Windows probada en dispositivos reales
- [ ] HTTPS no es viable offline: documentar que la geolocalización puede ser bloqueada por el navegador en contexto no seguro y definir alternativa
- [ ] Accesibilidad (lectores de pantalla, tamaño de fuente, contraste WCAG AA)
- [ ] Límite de clientes simultáneos (`kMaxClients = 8`) validado con carga real

## 15. Operación y mantenimiento — P1

- [ ] Backups y exportación de la BD (CSV/GeoJSON/PDF de reporte post-incidente)
- [ ] Modo simulacro/entrenamiento separado de datos reales
- [ ] Healthchecks y alertas: gateway caído, nodo sin heartbeat, BD llena
- [ ] Inventario de nodos (ID, ubicación, última vez visto, batería)
- [ ] Scripts de aprovisionamiento masivo de nodos (flasheo + configuración)
- [ ] Autoarranque del servidor táctico (servicio systemd/Windows) y UPS/laptop con batería
- [ ] Procedimiento de recuperación ante falla del Puesto de Comando
- [ ] Retención y purga de datos conforme a privacidad (ubicaciones de ciudadanos)

## 16. Privacidad y cumplimiento — P1

- [ ] Evaluación de privacidad de datos de ubicación (LFPDPPP/normativa aplicable)
- [ ] Aviso de privacidad en el portal cautivo
- [ ] Anonimización de reportes ciudadanos en exportaciones
- [ ] Verificar cumplimiento de la banda 915 MHz, potencia y duty cycle en México/LATAM
- [ ] Alinear formularios con la normativa oficial SCI vigente (Protección Civil)

## 17. Estructura del repositorio y DevEx — P2

- [ ] `Makefile` / scripts (`dev`, `test`, `lint`, `sim`) y script `setup` para Windows y Linux
- [ ] `pre-commit` con `ruff`, `clang-format` y verificación de trama
- [ ] Carpeta `docs/` con arquitectura (diagramas), decisiones (ADR) y especificaciones
- [ ] Mover `GOLDEN_HEX` a un archivo compartido entre Python y C++ (hoy duplicado)
- [ ] Fijar versiones de dependencias (`uv.lock`/`requirements.lock`) y de librerías PlatformIO
- [ ] Configurar `.gitattributes` para finales de línea (el repo tiene CRLF)
- [ ] Imagen Docker multi-stage del backend y `docker compose up` único para todo el servidor táctico
- [ ] Ignorar binarios de `frame_check` en Windows (`.exe`) en `.gitignore`

## 18. Hallazgos técnicos menores del código — P2

- [ ] `main.py`: `init_db()` bloquea el arranque; el hilo serial no tiene manejo de excepciones genéricas (solo `SerialException`)
- [ ] `ingest.py`: tramas truncadas por saltos de línea parciales y `ValueError` de `fromhex` no se distinguen en el log
- [ ] `radio_link.cpp`: `getPacketLength()` > `sizeof(buffer)` se recorta pero luego se decodifica; descartar directamente
- [ ] `radio_link.cpp`: no se registra RSSI/SNR de la trama recibida
- [ ] `portal.cpp`: `LittleFS.begin(true)` formatea la partición si falla el montaje; avisar y no ocultar el error
- [ ] `portal.cpp`: `NODE_LAT_E6=0`/`NODE_LON_E6=0` por defecto envían reportes en (0,0) si el nodo no se configuró
- [ ] `platformio.ini`: `NODE_ID` idéntico (=1) en todos los nodos por defecto
- [ ] `simulator.py`: usar un simulador de múltiples nodos con pérdida de paquetes y retransmisiones
- [ ] Añadir `tests/` para `service.py` con reportes verificados múltiples y empates de urgencia

---

## Ruta sugerida

1. Dashboard web (§1) + `vulnerability`/`road_penalty` (§2)
2. Autenticación de API y de tramas de brigadista (§5, P0) + tests de integración y CI (§11)
3. Robustez del firmware: `seq` persistente, reloj real, config en campo (§6)
4. App Flutter + BLE y formularios SCI (§4)
5. Motor de asignación y ciclo de vida de incidentes (§3)
6. AES, módulos por escenario, nube y hardware (§5, §8–§10)
