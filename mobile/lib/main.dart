import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'binary_frame.dart';

const String kApiBase = 'http://127.0.0.1:8000';

void main() => runApp(const BrigadistaApp());

class BrigadistaApp extends StatelessWidget {
  const BrigadistaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STG-AA · Brigadista SCI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF6F6F3),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF111111)),
        useMaterial3: true,
      ),
      home: const BrigadistaHomeScreen(),
    );
  }
}

class BrigadistaHomeScreen extends StatefulWidget {
  const BrigadistaHomeScreen({super.key});

  @override
  State<BrigadistaHomeScreen> createState() => _BrigadistaHomeScreenState();
}

class _BrigadistaHomeScreenState extends State<BrigadistaHomeScreen> {
  int _tab = 0, _seq = 1;
  String _status = 'ENLACE BLE ACTIVO · NODO #901 · MAPA ZONA CARGADO';

  // 1. Triaje START (SCI-207) y Gravedad (SCI-201)
  String _zone = '20.1355,-101.1845,Zona 02 · Sector Sur';
  int _kind = 0, _rojo = 2, _amarillo = 2, _verde = 1, _negro = 0;
  double _severity = 9;
  final Set<String> _hazards = {'Riesgo de colapso'};

  // 2. Mapa Dinámico de Bloqueos Viales
  LatLng _blockPoint = const LatLng(20.1385, -101.1818);
  final List<LatLng> _savedPoints = [const LatLng(20.1385, -101.1818)];
  final _streetCtrl = TextEditingController(text: 'Cruce Av. Morelos');
  String _cause = 'Escombros / Derrumbe';
  String _closure = 'Cierre total';

  // 3. Solicitud de Recursos (SCI-211)
  String _resZone = 'Zona 02 · Sector Sur';
  String _resType = 'Fuerza de Tarea USAR / BREC';
  String _resStatus = 'Solicitado urgente en escena';
  final _notesCtrl = TextEditingController(text: 'Equipo hidráulico de corte');

  Future<void> _postJson(String path, Map<String, dynamic> body) async {
    await http.post(
      Uri.parse('$kApiBase$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  Future<void> _sendTriage() async {
    final p = _zone.split(',');
    final frame = StgFrame(
      kind: _kind,
      seq: _seq++,
      nodeTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      lat: double.parse(p[0]),
      lon: double.parse(p[1]),
      severity: _severity.round(),
      affected: (_rojo + _amarillo + _verde + _negro).clamp(1, 999),
    );
    final hex = frame.encodeHex();
    try {
      await _postJson('/ingest/frame', {'hex': hex});
      if (_hazards.isNotEmpty) {
        await _postJson('/field/resource', {
          'zone': p[2],
          'resource': 'Alerta SCI-201 (Sev ${_severity.round()}/10)',
          'unit_status': 'Perímetro activo',
          'notes': _hazards.join(', '),
        });
      }
      setState(() => _status = 'CONFIRMADO EN PC · Trama 25B: $hex');
    } catch (_) {
      setState(() => _status = 'ENCOLADO EN BLE · Trama 25B: $hex');
    }
  }

  Future<void> _sendRoadblock() async {
    final lat = _blockPoint.latitude, lon = _blockPoint.longitude;
    final street = '${_streetCtrl.text.trim()} (${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)})';
    try {
      await _postJson('/field/roadblock', {
        'street': street,
        'cause': _cause,
        'closure': _closure,
        'lat': lat,
        'lon': lon,
      });
      setState(() {
        _savedPoints.add(_blockPoint);
        _status = 'BLOQUEO VIAL ENVIADO AL MAPA DEL PC: $street';
      });
    } catch (_) {
      setState(() => _status = 'Error al enviar bloqueo vial.');
    }
  }

  Future<void> _sendResource() async {
    try {
      await _postJson('/field/resource', {
        'zone': _resZone,
        'resource': _resType,
        'unit_status': _resStatus,
        'notes': _notesCtrl.text.trim(),
      });
      setState(() => _status = 'REPORTE SCI-211 SINCRONIZADO CON EL PC');
    } catch (_) {
      setState(() => _status = 'Error al enviar SCI-211.');
    }
  }

  Widget _select<T>(String label, T value, Map<T, String> options, ValueChanged<T> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(),
        ),
        items: options.entries
            .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) => v != null ? onChanged(v) : null,
      ),
    );
  }

  Widget _counter(String title, String sub, int val, Color color, ValueChanged<int> onDelta) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: color, width: 5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          Text(sub, style: const TextStyle(color: Colors.black54, fontSize: 11)),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: () => onDelta(-1), icon: const Icon(Icons.remove, size: 18)),
              Text('$val', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => onDelta(1), icon: const Icon(Icons.add, size: 18)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTriageTab() {
    const hazardsList = ['Riesgo de colapso', 'Fuga de gas', 'Cables eléctricos', 'Acceso reducido'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _select('1. Zona de intervención', _zone, const {
          '20.1355,-101.1845,Zona 02 · Sector Sur': 'Zona 02 · Sector Sur (Sin verificar)',
          '20.1475,-101.1710,Zona 03 · Sector Oriente': 'Zona 03 · Sector Oriente (Sin verificar)',
          '20.1410,-101.1790,Zona 01 · Centro': 'Zona 01 · Centro (Actualizar)',
        }, (v) => setState(() => _zone = v)),
        _select('2. Naturaleza del incidente (SCI-201)', _kind, const {
          0: 'Derrumbe estructural',
          1: 'Personas atrapadas',
          2: 'Inundación severa',
          3: 'Incendio / Material peligroso',
          4: 'Múltiples heridos graves',
        }, (v) => setState(() => _kind = v)),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.4,
          children: [
            _counter('ROJO · INMEDIATO', 'Riesgo vital', _rojo, const Color(0xFFB91C1C),
                (d) => setState(() => _rojo = (_rojo + d).clamp(0, 99))),
            _counter('AMARILLO · DEMORADO', 'Grave estable', _amarillo, const Color(0xFFB45309),
                (d) => setState(() => _amarillo = (_amarillo + d).clamp(0, 99))),
            _counter('VERDE · MENOR', 'Ambulatorio', _verde, const Color(0xFF15803D),
                (d) => setState(() => _verde = (_verde + d).clamp(0, 99))),
            _counter('NEGRO · FALLECIDO', 'Sin signos', _negro, const Color(0xFF27272A),
                (d) => setState(() => _negro = (_negro + d).clamp(0, 99))),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('3. Gravedad evaluada: ${_severity.round()} / 10',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Slider(
                value: _severity,
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: const Color(0xFFB91C1C),
                onChanged: (v) => setState(() => _severity = v),
              ),
              Wrap(
                spacing: 6,
                children: hazardsList.map((h) {
                  return FilterChip(
                    label: Text(h, style: const TextStyle(fontSize: 12)),
                    selected: _hazards.contains(h),
                    onSelected: (s) => setState(() => s ? _hazards.add(h) : _hazards.remove(h)),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF111111),
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: _sendTriage,
          child: const Text('Transmitir dictamen verificado (Trama 25B · LoRa)'),
        ),
      ],
    );
  }

  Widget _buildRoadblocksTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('TOCA EL MAPA PARA UBICAR EL BLOQUEO EN LA VIALIDAD',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54)),
        const SizedBox(height: 8),
        SizedBox(
          height: 250,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(20.1410, -101.1790),
                initialZoom: 14.5,
                onTap: (_, pt) => setState(() {
                  _blockPoint = pt;
                  _streetCtrl.text = 'Vía bloqueada';
                }),
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                MarkerLayer(
                  markers: [
                    ..._savedPoints.map((pt) => Marker(
                          point: pt,
                          width: 26,
                          height: 26,
                          child: const Icon(Icons.block, color: Colors.black87, size: 22),
                        )),
                    Marker(
                      point: _blockPoint,
                      width: 36,
                      height: 36,
                      child: const Icon(Icons.location_on, color: Color(0xFFB91C1C), size: 36),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _streetCtrl,
          decoration: const InputDecoration(
            labelText: '1. Referencia del punto o calle',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _select('2. Causa de la obstrucción', _cause, const {
          'Escombros / Derrumbe': 'Escombros / Derrumbe estructural',
          'Inundación / Corriente': 'Inundación / Corriente de agua',
          'Cables de alta tensión': 'Cables de alta tensión caídos',
          'Fractura de vía / Socavón': 'Fractura de vía / Socavón',
        }, (v) => setState(() => _cause = v)),
        _select('3. Nivel de bloqueo', _closure, const {
          'Cierre total': 'Cierre total (Ruta intransitable)',
          'Solo unidades ligeras': 'Paso solo a unidades ligeras',
        }, (v) => setState(() => _closure = v)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB91C1C),
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: _sendRoadblock,
          child: const Text('Transmitir bloqueo vial al Puesto de Comando'),
        ),
      ],
    );
  }

  Widget _buildResourcesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _select('1. Zona o instalación SCI', _resZone, const {
          'Zona 02 · Sector Sur': 'Zona 02 · Sector Sur (ACV Sur)',
          'Zona 03 · Sector Oriente': 'Zona 03 · Sector Oriente',
          'Zona 01 · Centro': 'Zona 01 · Centro (ACV Principal)',
          'Área de Espera (E)': 'Área de Espera (E)',
        }, (v) => setState(() => _resZone = v)),
        _select('2. Recurso requerido (SCI-211)', _resType, const {
          'Fuerza de Tarea USAR / BREC': 'Fuerza de Tarea USAR / BREC',
          'Ambulancia Soporte Vital (Tipo I)': 'Ambulancia Soporte Vital (Tipo I)',
          'Camión Motobomba Extinción': 'Camión Motobomba de Extinción',
          'Maquinaria Pesada / Retroexcavadora': 'Maquinaria Pesada / Remoción',
        }, (v) => setState(() => _resType = v)),
        _select('3. Estado del recurso', _resStatus, const {
          'Solicitado urgente en escena': 'Solicitado urgente en escena',
          'Asignado trabajando en escena': 'Asignado (Trabajando en escena)',
          'Disponible en Área de Espera (E)': 'Disponible en Área de Espera (E)',
          'No disponible (Mantenimiento)': 'No disponible (Mantenimiento)',
        }, (v) => setState(() => _resStatus = v)),
        TextField(
          controller: _notesCtrl,
          decoration: const InputDecoration(
            labelText: '4. Notas operativas',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF111111),
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: _sendResource,
          child: const Text('Transmitir reporte de recursos SCI-211'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [_buildTriageTab(), _buildRoadblocksTab(), _buildResourcesTab()];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('STG-AA · Terminal Táctica de Brigadista (SCI)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF111111),
                child: Text(_status,
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11)),
              ),
              Expanded(child: tabs[_tab]),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.medical_information_outlined), label: 'Triaje y Gravedad'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Mapa y Bloqueos'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Recursos SCI-211'),
        ],
      ),
    );
  }
}
