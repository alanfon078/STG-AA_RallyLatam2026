import 'dart:async';
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
      title: 'STG-AA · Terminal Táctica Brigadista',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF6F6F3),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF111111)),
        useMaterial3: true,
      ),
      home: const BrigadistaScreen(),
    );
  }
}

class BrigadistaScreen extends StatefulWidget {
  const BrigadistaScreen({super.key});

  @override
  State<BrigadistaScreen> createState() => _BrigadistaScreenState();
}

class _BrigadistaScreenState extends State<BrigadistaScreen> {
  int _seq = 1;
  bool _isRoadblock = false; // false = Incidente/Triaje, true = Bloqueo Vial
  LatLng _point = const LatLng(20.1355, -101.1845);
  String _status = 'Toca cualquier ubicación en el mapa para reportar incidente o bloqueo.';

  // Datos sincronizados del mapa (clústeres y bloqueos actuales)
  final _mapCtrl = MapController();
  List<dynamic> _clusters = [];
  List<dynamic> _roadblocks = [];
  Timer? _pollTimer;

  // Campos de Modo Incidente (Triaje START + Gravedad + Recurso SCI-211)
  int _kind = 0, _rojo = 2, _amarillo = 1, _verde = 1, _negro = 0;
  double _severity = 8;
  String _resource = 'Fuerza de Tarea USAR / BREC';

  // Campos de Modo Bloqueo Vial
  final _streetCtrl = TextEditingController(text: 'Tramo vial obstruido');
  String _cause = 'Escombros / Derrumbe';
  String _closure = 'Cierre total';

  @override
  void initState() {
    super.initState();
    _syncMap();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _syncMap());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncMap() async {
    try {
      final res = await http.get(Uri.parse('$kApiBase/demo/state'));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _clusters = data['clusters'] ?? [];
          _roadblocks = data['roadblocks'] ?? [];
        });
      }
    } catch (_) {}
  }

  Future<void> _postJson(String path, Map<String, dynamic> body) async {
    await http.post(
      Uri.parse('$kApiBase$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  Future<void> _submit() async {
    final lat = _point.latitude, lon = _point.longitude;
    final coordText = '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';

    if (_isRoadblock) {
      final street = '${_streetCtrl.text.trim()} ($coordText)';
      await _postJson('/field/roadblock', {
        'street': street,
        'cause': _cause,
        'closure': _closure,
        'lat': lat,
        'lon': lon,
      });
      setState(() => _status = 'BLOQUEO VIAL REGISTRADO EN ($coordText)');
    } else {
      final frame = StgFrame(
        kind: _kind,
        seq: _seq++,
        nodeTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        lat: lat,
        lon: lon,
        severity: _severity.round(),
        affected: (_rojo + _amarillo + _verde + _negro).clamp(1, 999),
      );
      final hex = frame.encodeHex();
      await _postJson('/ingest/frame', {'hex': hex});
      if (_resource != 'Ninguno') {
        await _postJson('/field/resource', {
          'zone': 'Ubicación ($coordText)',
          'resource': _resource,
          'unit_status': 'Solicitado en sitio (Sev ${_severity.round()}/10)',
          'notes': 'Triaje START: R:$_rojo A:$_amarillo V:$_verde N:$_negro',
        });
      }
      setState(() => _status = 'DICTAMEN SCI TRANSMITIDO · Trama 25B: $hex');
    }
    _syncMap();
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
        items: options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) => v != null ? onChanged(v) : null,
      ),
    );
  }

  Widget _counter(String title, int val, Color color, ValueChanged<int> onDelta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: color, width: 5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          Row(
            children: [
              IconButton(onPressed: () => onDelta(-1), icon: const Icon(Icons.remove, size: 16)),
              Text('$val', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => onDelta(1), icon: const Icon(Icons.add, size: 16)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _select('1. Naturaleza del incidente (SCI-201)', _kind, const {
          0: 'Derrumbe estructural',
          1: 'Personas atrapadas',
          2: 'Inundación severa',
          3: 'Incendio / Fuga de gas',
          4: 'Heridos graves',
        }, (v) => setState(() => _kind = v)),
        const Text('2. Triaje START de víctimas (SCI-207)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.5,
          children: [
            _counter('ROJO', _rojo, const Color(0xFFB91C1C), (d) => setState(() => _rojo = (_rojo + d).clamp(0, 99))),
            _counter('AMARILLO', _amarillo, const Color(0xFFB45309), (d) => setState(() => _amarillo = (_amarillo + d).clamp(0, 99))),
            _counter('VERDE', _verde, const Color(0xFF15803D), (d) => setState(() => _verde = (_verde + d).clamp(0, 99))),
            _counter('NEGRO', _negro, const Color(0xFF27272A), (d) => setState(() => _negro = (_negro + d).clamp(0, 99))),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('3. Gravedad en sitio: ${_severity.round()} / 10',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Slider(
                value: _severity,
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: const Color(0xFFB91C1C),
                onChanged: (v) => setState(() => _severity = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _select('4. Solicitar recurso táctico (SCI-211)', _resource, const {
          'Fuerza de Tarea USAR / BREC': 'Fuerza de Tarea USAR / BREC',
          'Ambulancia Soporte Vital (Tipo I)': 'Ambulancia Soporte Vital (Tipo I)',
          'Camión Motobomba Extinción': 'Camión Motobomba de Extinción',
          'Ninguno': 'Sin solicitud adicional',
        }, (v) => setState(() => _resource = v)),
      ],
    );
  }

  Widget _buildRoadblockForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _streetCtrl,
          decoration: const InputDecoration(
            labelText: '1. Nombre de calle o referencia del punto',
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
        _select('3. Nivel de cierre', _closure, const {
          'Cierre total': 'Cierre total (Paso bloqueado)',
          'Solo unidades ligeras': 'Paso solo a unidades ligeras',
        }, (v) => setState(() => _closure = v)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapWidget = Stack(
      children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: const LatLng(20.1410, -101.1790),
            initialZoom: 14.5,
            minZoom: 11,
            maxZoom: 19,
            onTap: (_, pt) => setState(() => _point = pt),
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
            CircleLayer(
              circles: _clusters.map((c) {
                final verified = c['verified'] == true;
                final color = verified ? const Color(0xFFB91C1C) : const Color(0xFFB45309);
                return CircleMarker(
                  point: LatLng((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble()),
                  radius: 80,
                  useRadiusInMeter: true,
                  color: color.withValues(alpha: 0.22),
                  borderColor: color,
                  borderStrokeWidth: 2,
                );
              }).toList(),
            ),
            MarkerLayer(
              markers: [
                ..._roadblocks.map((rb) => Marker(
                      point: LatLng((rb['lat'] as num).toDouble(), (rb['lon'] as num).toDouble()),
                      width: 24,
                      height: 24,
                      child: const Center(
                        child: Text('✕', style: TextStyle(color: Color(0xFFD90429), fontSize: 20, fontWeight: FontWeight.w900)),
                      ),
                    )),
                Marker(
                  point: _point,
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.location_on,
                    color: _isRoadblock ? const Color(0xFFD90429) : const Color(0xFF111111),
                    size: 38,
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'z_in',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                onPressed: () => _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom + 1),
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 6),
              FloatingActionButton.small(
                heroTag: 'z_out',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                onPressed: () => _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom - 1),
                child: const Icon(Icons.remove),
              ),
            ],
          ),
        ),
      ],
    );

    final formPanel = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE2E2DC)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'UBICACIÓN SELECCIONADA: ${_point.latitude.toStringAsFixed(4)}, ${_point.longitude.toStringAsFixed(4)}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Incidente / Triaje SCI'), icon: Icon(Icons.medical_information_outlined)),
            ButtonSegment(value: true, label: Text('Bloqueo Vial'), icon: Icon(Icons.close)),
          ],
          selected: {_isRoadblock},
          onSelectionChanged: (s) => setState(() => _isRoadblock = s.first),
        ),
        const SizedBox(height: 16),
        _isRoadblock ? _buildRoadblockForm() : _buildIncidentForm(),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _isRoadblock ? const Color(0xFFB91C1C) : const Color(0xFF111111),
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: _submit,
          child: Text(_isRoadblock
              ? 'Marcar bloqueo vial en esta ubicación'
              : 'Transmitir dictamen en esta ubicación (LoRa 25B)'),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('STG-AA · Terminal Táctica de Brigadista (SCI)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF111111),
            child: Text(_status,
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11)),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 760) {
            return Row(
              children: [
                Expanded(child: mapWidget),
                SizedBox(width: 440, child: formPanel),
              ],
            );
          }
          return Column(
            children: [
              SizedBox(height: 260, child: mapWidget),
              Expanded(child: formPanel),
            ],
          );
        },
      ),
    );
  }
}
